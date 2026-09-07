import { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Stack,
  Typography,
} from '@mui/material';
import { dataUrl, getDataBlob, setDataWatchPaused } from './datakeep';
import {
  extractCoverFrameFromRel,
  hasCoverHost,
  isStagedPick,
  prepareCoverFramesFromRel,
  pickFile,
  type CoverFrameInfo,
  type PickedStagedFile,
} from './host';

type VideoPick = File | PickedStagedFile;

type Props = {
  open: boolean;
  videoPick: VideoPick;
  onClose: () => void;
  onConfirm: (blob: Blob, previewUrl: string) => void;
};

type Slot = {
  sec: number;
  status: 'pending' | 'ready' | 'error';
  frame?: CoverFrameInfo;
};

const MIN_COVER_LUMA = 18;
const GALLERY_FRAMES = 20;

function canvasLumaMean(canvas: HTMLCanvasElement): number {
  const ctx = canvas.getContext('2d');
  if (!ctx) return 0;
  const { width: w, height: h } = canvas;
  if (w <= 0 || h <= 0) return 0;
  const stepX = Math.max(1, Math.ceil(w / 64));
  const stepY = Math.max(1, Math.ceil(h / 64));
  const data = ctx.getImageData(0, 0, w, h).data;
  let sum = 0;
  let n = 0;
  for (let y = 0; y < h; y += stepY) {
    for (let x = 0; x < w; x += stepX) {
      const i = (y * w + x) * 4;
      sum += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2];
      n++;
    }
  }
  return n === 0 ? 0 : sum / n;
}

function gallerySeekSeconds(duration: number, maxFrames: number): number[] {
  const n = Math.min(36, Math.max(6, maxFrames));
  const d = Number.isFinite(duration) && duration > 2 ? duration : 120;
  const start = Math.min(Math.max(0.5, d * 0.02), d);
  const end = Math.max(start + 0.5, Math.min(d * 0.95, d));
  const out: number[] = [];
  for (let i = 0; i < n; i++) {
    out.push(start + ((end - start) * (i + 0.5)) / n);
  }
  return out;
}

async function seekVideo(video: HTMLVideoElement, t: number): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const onSeeked = () => {
      cleanup();
      resolve();
    };
    const onErr = () => {
      cleanup();
      reject(new Error('定位封面帧失败'));
    };
    const cleanup = () => {
      video.removeEventListener('seeked', onSeeked);
      video.removeEventListener('error', onErr);
    };
    video.addEventListener('seeked', onSeeked);
    video.addEventListener('error', onErr);
    try {
      video.currentTime = t;
    } catch {
      cleanup();
      resolve();
    }
  });
}

function formatSec(sec: number): string {
  const s = Math.max(0, Math.floor(sec));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r.toString().padStart(2, '0')}`;
}

function markRecommended(slots: Slot[]): Slot[] {
  const ready = slots.filter((s) => s.status === 'ready' && s.frame);
  if (ready.length === 0) {
    return slots.map((s) =>
      s.frame ? { ...s, frame: { ...s.frame, recommended: false } } : s,
    );
  }
  const usable = ready.filter((s) => (s.frame?.luma ?? 0) >= MIN_COVER_LUMA);
  const pool = usable.length > 0 ? usable : ready;
  let best = pool[0];
  for (const s of pool) {
    if ((s.frame?.luma ?? 0) > (best.frame?.luma ?? 0)) best = s;
  }
  return slots.map((s) => {
    if (!s.frame) return s;
    return {
      ...s,
      frame: { ...s.frame, recommended: s === best },
    };
  });
}

export default function CoverPickerDialog({ open, videoPick, onClose, onConfirm }: Props) {
  const [preparing, setPreparing] = useState(false);
  const [extracting, setExtracting] = useState(false);
  const [error, setError] = useState('');
  const [slots, setSlots] = useState<Slot[]>([]);
  const [selected, setSelected] = useState<number | null>(null);
  const [blobUrls, setBlobUrls] = useState<string[]>([]);
  const userPicked = useRef(false);
  const selectedRef = useRef<number | null>(null);

  selectedRef.current = selected;

  const selectedFrame = useMemo(() => {
    if (selected == null) return null;
    return slots[selected]?.frame ?? null;
  }, [slots, selected]);

  const previewSrc = selectedFrame?.url ?? '';
  const readyCount = slots.filter((s) => s.status === 'ready').length;

  const pickSlot = (index: number, manual: boolean) => {
    if (slots[index]?.status !== 'ready') return;
    if (manual) userPicked.current = true;
    setSelected(index);
  };

  const applySlots = (
    updater: (prev: Slot[]) => Slot[],
    opts?: { autoSelectIfNeeded?: boolean },
  ) => {
    setSlots((prev) => {
      const next = markRecommended(updater(prev));
      if (opts?.autoSelectIfNeeded && !userPicked.current) {
        const rec = next.findIndex((s) => s.frame?.recommended);
        const firstReady = next.findIndex((s) => s.status === 'ready');
        const prefer = rec >= 0 ? rec : firstReady;
        if (prefer >= 0) {
          const cur = selectedRef.current;
          const curOk = cur != null && next[cur]?.status === 'ready';
          // 尚未选中，或当前选中不是最新推荐时跟随推荐
          if (!curOk || (rec >= 0 && cur !== rec)) {
            queueMicrotask(() => setSelected(prefer));
          }
        }
      }
      return next;
    });
  };

  useEffect(() => {
    if (!open) return;
    setDataWatchPaused(true);
    let cancelled = false;
    const localBlobUrls: string[] = [];
    userPicked.current = false;

    const run = async () => {
      setPreparing(true);
      setExtracting(false);
      setError('');
      setSlots([]);
      setSelected(null);
      try {
        if (isStagedPick(videoPick) && hasCoverHost()) {
          const plan = await prepareCoverFramesFromRel(videoPick.rel);
          if (cancelled) return;
          const initial: Slot[] = plan.seeks.map((sec) => ({
            sec,
            status: 'pending',
          }));
          setSlots(initial);
          setPreparing(false);
          setExtracting(true);

          for (let i = 0; i < plan.seeks.length; i++) {
            if (cancelled) return;
            const sec = plan.seeks[i];
            try {
              const f = await extractCoverFrameFromRel(videoPick.rel, sec, i);
              if (cancelled) return;
              const frame: CoverFrameInfo = {
                rel: f.rel,
                url: `${dataUrl(f.rel)}?t=${Date.now()}`,
                sec: f.sec,
                luma: f.luma,
              };
              applySlots(
                (prev) =>
                  prev.map((s, idx) =>
                    idx === i ? { sec, status: 'ready', frame } : s,
                  ),
                { autoSelectIfNeeded: true },
              );
            } catch {
              if (cancelled) return;
              applySlots((prev) =>
                prev.map((s, idx) =>
                  idx === i ? { sec, status: 'error' } : s,
                ),
              );
            }
          }
          return;
        }

        // 浏览器逐帧
        const src = isStagedPick(videoPick)
          ? dataUrl(videoPick.rel)
          : URL.createObjectURL(videoPick);
        if (!isStagedPick(videoPick)) localBlobUrls.push(src);

        const video = document.createElement('video');
        video.muted = true;
        video.playsInline = true;
        video.preload = 'auto';
        video.crossOrigin = 'anonymous';
        video.src = src;
        await new Promise<void>((resolve, reject) => {
          video.onloadeddata = () => resolve();
          video.onerror = () => reject(new Error('无法读取视频以提取封面'));
        });
        if (cancelled) return;

        const seeks = gallerySeekSeconds(video.duration || 0, GALLERY_FRAMES);
        setSlots(seeks.map((sec) => ({ sec, status: 'pending' })));
        setPreparing(false);
        setExtracting(true);

        const canvas = document.createElement('canvas');
        const w = video.videoWidth || 640;
        const h = video.videoHeight || 360;
        canvas.width = Math.min(480, w);
        canvas.height = Math.round((canvas.width / w) * h) || 270;
        const ctx = canvas.getContext('2d');
        if (!ctx) throw new Error('无法创建画布');

        for (let i = 0; i < seeks.length; i++) {
          if (cancelled) return;
          const sec = seeks[i];
          try {
            await seekVideo(video, sec);
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const luma = canvasLumaMean(canvas);
            const blob = await new Promise<Blob | null>((resolve) => {
              canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.85);
            });
            if (!blob) throw new Error('encode');
            const url = URL.createObjectURL(blob);
            localBlobUrls.push(url);
            const frame: CoverFrameInfo = { url, sec, luma };
            applySlots(
              (prev) =>
                prev.map((s, idx) =>
                  idx === i ? { sec, status: 'ready', frame } : s,
                ),
              { autoSelectIfNeeded: true },
            );
          } catch {
            applySlots((prev) =>
              prev.map((s, idx) => (idx === i ? { sec, status: 'error' } : s)),
            );
          }
        }
        setBlobUrls([...localBlobUrls]);
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : '提取封面失败');
        }
      } finally {
        if (!cancelled) {
          setPreparing(false);
          setExtracting(false);
        }
      }
    };

    void run();
    return () => {
      cancelled = true;
      setDataWatchPaused(false);
    };
  }, [open, videoPick]);

  useEffect(() => {
    if (open) return;
    for (const u of blobUrls) URL.revokeObjectURL(u);
    setBlobUrls([]);
    setSlots([]);
    setError('');
    setSelected(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 仅在关闭时回收
  }, [open]);

  const confirmSelected = async () => {
    if (!selectedFrame) return;
    try {
      let blob: Blob | null = null;
      if (selectedFrame.rel) {
        blob = await getDataBlob(selectedFrame.rel);
      } else {
        const res = await fetch(selectedFrame.url);
        blob = await res.blob();
      }
      if (!blob) throw new Error('读取封面失败');
      const preview = URL.createObjectURL(blob);
      onConfirm(blob, preview);
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : '确认封面失败');
    }
  };

  const onUpload = async () => {
    try {
      const picked = await pickFile('image/*');
      let blob: Blob;
      if (isStagedPick(picked)) {
        const b = await getDataBlob(picked.rel);
        if (!b) throw new Error('读取封面失败');
        blob = b;
      } else {
        blob = picked;
      }
      const preview = URL.createObjectURL(blob);
      onConfirm(blob, preview);
      onClose();
    } catch (e) {
      if (e instanceof Error && e.message === 'cancelled') return;
      setError(e instanceof Error ? e.message : '上传封面失败');
    }
  };

  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="md">
      <DialogTitle>选择封面</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 0.5 }}>
          <Box
            sx={{
              width: '100%',
              minHeight: 220,
              bgcolor: 'action.hover',
              borderRadius: 1,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              overflow: 'hidden',
            }}
          >
            {preparing && !previewSrc ? (
              <Stack spacing={1} sx={{ alignItems: 'center' }}>
                <CircularProgress size={36} />
                <Typography variant="body2" color="text.secondary">
                  正在准备…
                </Typography>
              </Stack>
            ) : previewSrc ? (
              <Box
                component="img"
                src={previewSrc}
                alt="封面预览"
                sx={{ maxWidth: '100%', maxHeight: 360, objectFit: 'contain' }}
              />
            ) : (
              <Typography color="text.secondary">
                {extracting ? '正在提取画面…' : '暂无预览'}
              </Typography>
            )}
          </Box>

          <Box
            sx={{
              display: 'flex',
              gap: 1,
              overflowX: 'auto',
              pb: 1,
              px: 0.5,
              minHeight: 62,
            }}
          >
            <Box
              onClick={() => void onUpload()}
              sx={{
                flex: '0 0 auto',
                width: 96,
                height: 54,
                borderRadius: 1,
                border: '1px dashed',
                borderColor: 'divider',
                cursor: 'pointer',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                bgcolor: 'action.hover',
                '&:hover': { borderColor: 'primary.main', bgcolor: 'action.selected' },
              }}
            >
              <Typography variant="h6" component="span" sx={{ lineHeight: 1, color: 'text.secondary' }}>
                +
              </Typography>
              <Typography variant="caption" color="text.secondary" sx={{ fontSize: 10 }}>
                上传封面
              </Typography>
            </Box>

            {slots.map((s, i) => {
              const active = i === selected;
              if (s.status === 'ready' && s.frame) {
                return (
                  <Box
                    key={`ready-${i}-${s.sec}`}
                    onClick={() => pickSlot(i, true)}
                    sx={{
                      position: 'relative',
                      flex: '0 0 auto',
                      width: 96,
                      height: 54,
                      borderRadius: 1,
                      overflow: 'hidden',
                      cursor: 'pointer',
                      outline: active ? '2px solid' : '1px solid',
                      outlineColor: active ? 'primary.main' : 'divider',
                      opacity: s.frame.luma < MIN_COVER_LUMA ? 0.55 : 1,
                    }}
                  >
                    <Box
                      component="img"
                      src={s.frame.url}
                      alt={`t=${s.sec}`}
                      sx={{ width: '100%', height: '100%', objectFit: 'cover' }}
                    />
                    {s.frame.recommended && (
                      <Typography
                        variant="caption"
                        sx={{
                          position: 'absolute',
                          left: 2,
                          top: 2,
                          px: 0.5,
                          bgcolor: 'primary.main',
                          color: 'primary.contrastText',
                          borderRadius: 0.5,
                          fontSize: 10,
                          lineHeight: 1.4,
                        }}
                      >
                        推荐
                      </Typography>
                    )}
                    <Typography
                      variant="caption"
                      sx={{
                        position: 'absolute',
                        right: 2,
                        bottom: 2,
                        px: 0.5,
                        bgcolor: 'rgba(0,0,0,0.55)',
                        color: '#fff',
                        borderRadius: 0.5,
                        fontSize: 10,
                      }}
                    >
                      {formatSec(s.sec)}
                    </Typography>
                  </Box>
                );
              }
              return (
                <Box
                  key={`slot-${i}-${s.sec}`}
                  sx={{
                    flex: '0 0 auto',
                    width: 96,
                    height: 54,
                    borderRadius: 1,
                    border: '1px solid',
                    borderColor: 'divider',
                    bgcolor: 'action.hover',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                  }}
                >
                  {s.status === 'pending' ? (
                    <CircularProgress size={18} />
                  ) : (
                    <Typography variant="caption" color="text.disabled">
                      —
                    </Typography>
                  )}
                </Box>
              );
            })}
          </Box>

          {extracting && (
            <Typography variant="caption" color="text.secondary">
              已提取 {readyCount}/{slots.length} 帧，可先选已有画面或上传封面
            </Typography>
          )}

          {error && (
            <Typography color="error" variant="body2">
              {error}
            </Typography>
          )}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>取消</Button>
        <Button
          variant="contained"
          disabled={!selectedFrame}
          onClick={() => void confirmSelected()}
        >
          使用此封面
        </Button>
      </DialogActions>
    </Dialog>
  );
}
