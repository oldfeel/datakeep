import { useEffect, useMemo, useRef, useState } from 'react';
import type { OutputData } from '@editorjs/editorjs';
import {
  Alert,
  Autocomplete,
  Box,
  Button,
  Checkbox,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  LinearProgress,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import {
  dataUrl,
  deleteDataFile,
  getDataBlob,
  getDataJson,
  putDataFile,
  putDataFileWithProgress,
  putDataJson,
} from './datakeep';
import CoverPickerDialog from './CoverPickerDialog';
import DescriptionEditor from './DescriptionEditor';
import {
  generateCoverFromRel,
  isStagedPick,
  needsHostCover,
  pickFile,
  probeDurationFromRel,
  type PickedStagedFile,
} from './host';
import {
  KEEP_NAME,
  META_NAME,
  entryPath,
  findDuplicateTitles,
  isReservedName,
  l1Names,
  l2Names,
  collectionNamesFor,
  newEntryId,
  normalizeCatName,
  videoExtFromName,
  type EntryMeta,
  type Library,
  type VideoEntry,
} from './library';

export type VideoEntryDialogMode = 'add' | 'edit';

type Props = {
  open: boolean;
  mode: VideoEntryDialogMode;
  library: Library;
  /** 编辑时必填 */
  entry?: VideoEntry | null;
  defaultL1?: string;
  defaultL2?: string;
  onClose: () => void;
  onDone: () => void;
};

type VideoPick = File | PickedStagedFile;

const MIN_COVER_LUMA = 18;
const COVER_NAME = 'cover.jpg';

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

function coverSeekCandidates(duration: number): number[] {
  const d = Number.isFinite(duration) && duration > 0 ? duration : 120;
  const raw = [1, 5, 10, 30, 60, 120, d * 0.05, d * 0.1, d * 0.2];
  const out: number[] = [];
  for (const s of raw) {
    const t = Math.min(Math.max(0.5, s), Math.max(0.5, d - 0.5));
    if (out.some((x) => Math.abs(x - t) < 0.4)) continue;
    out.push(t);
  }
  return out.sort((a, b) => a - b);
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

async function captureCoverFromVideoSrc(src: string): Promise<Blob> {
  const video = document.createElement('video');
  video.muted = true;
  video.playsInline = true;
  video.preload = 'auto';
  video.crossOrigin = 'anonymous';
  video.src = src;
  await new Promise<void>((resolve, reject) => {
    video.onloadeddata = () => resolve();
    video.onerror = () => reject(new Error('无法读取视频以生成封面'));
  });

  const canvas = document.createElement('canvas');
  const w = video.videoWidth || 640;
  const h = video.videoHeight || 360;
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('无法创建画布');

  let bestBlob: Blob | null = null;
  let bestMean = -1;
  for (const t of coverSeekCandidates(video.duration || 0)) {
    await seekVideo(video, t);
    ctx.drawImage(video, 0, 0, w, h);
    const mean = canvasLumaMean(canvas);
    const blob = await new Promise<Blob | null>((resolve) => {
      canvas.toBlob((b) => resolve(b), 'image/jpeg', 0.85);
    });
    if (!blob) continue;
    if (mean > bestMean) {
      bestMean = mean;
      bestBlob = blob;
    }
    if (mean >= MIN_COVER_LUMA) return blob;
  }
  if (bestBlob) return bestBlob;
  throw new Error('封面编码失败');
}

function pickDisplayName(pick: VideoPick | null): string {
  if (!pick) return '未选择';
  return isStagedPick(pick) ? pick.name : pick.name;
}

async function ensureCatKeeps(l1n: string, l2n: string, coln: string) {
  await putDataFile(`${l1n}/${KEEP_NAME}`, '');
  await putDataFile(`${l1n}/${l2n}/${KEEP_NAME}`, '');
  if (coln) {
    await putDataFile(`${l1n}/${l2n}/${coln}/${KEEP_NAME}`, '');
  }
}

async function resolveDurationSec(
  videoPick: VideoPick,
  videoRelInData: string,
): Promise<number | undefined> {
  try {
    if (isStagedPick(videoPick) || videoRelInData) {
      const rel = isStagedPick(videoPick) ? videoPick.rel : videoRelInData;
      const d = await probeDurationFromRel(rel);
      if (d != null) return Math.round(d * 10) / 10;
    }
  } catch {
    /* fall through */
  }
  if (!isStagedPick(videoPick) && videoPick instanceof File) {
    try {
      const url = URL.createObjectURL(videoPick);
      const dur = await new Promise<number | null>((resolve) => {
        const v = document.createElement('video');
        v.preload = 'metadata';
        v.onloadedmetadata = () => {
          const d = v.duration;
          URL.revokeObjectURL(url);
          resolve(Number.isFinite(d) && d > 0 ? d : null);
        };
        v.onerror = () => {
          URL.revokeObjectURL(url);
          resolve(null);
        };
        v.src = url;
      });
      if (dur != null) return Math.round(dur * 10) / 10;
    } catch {
      /* ignore */
    }
  }
  return undefined;
}

async function resolveAutoCover(videoPick: VideoPick, fileName: string): Promise<Blob | null> {
  if (isStagedPick(videoPick) && needsHostCover(fileName)) {
    try {
      const gen = await generateCoverFromRel(videoPick.rel);
      return (await getDataBlob(gen.rel)) ?? null;
    } catch {
      return null;
    }
  }
  try {
    const src = isStagedPick(videoPick) ? dataUrl(videoPick.rel) : URL.createObjectURL(videoPick);
    try {
      return await captureCoverFromVideoSrc(src);
    } finally {
      if (!isStagedPick(videoPick)) URL.revokeObjectURL(src);
    }
  } catch {
    if (isStagedPick(videoPick)) {
      try {
        const gen = await generateCoverFromRel(videoPick.rel);
        return (await getDataBlob(gen.rel)) ?? null;
      } catch {
        return null;
      }
    }
    return null;
  }
}

export default function VideoEntryDialog({
  open,
  mode,
  library,
  entry,
  defaultL1,
  defaultL2,
  onClose,
  onDone,
}: Props) {
  const isEdit = mode === 'edit';
  const [l1, setL1] = useState('');
  const [l2, setL2] = useState('');
  const [collection, setCollection] = useState('');
  const [title, setTitle] = useState('');
  const [videoPick, setVideoPick] = useState<VideoPick | null>(null);
  const [videoChanged, setVideoChanged] = useState(false);
  const [coverBlob, setCoverBlob] = useState<Blob | null>(null);
  const [coverPreview, setCoverPreview] = useState<string | null>(null);
  const [coverChanged, setCoverChanged] = useState(false);
  const [coverPickerOpen, setCoverPickerOpen] = useState(false);
  const [initialDesc, setInitialDesc] = useState<OutputData | null>(null);
  const [meta, setMeta] = useState<EntryMeta | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState<number | null>(null);
  const [editorKey, setEditorKey] = useState(0);
  const [favorite, setFavorite] = useState(false);
  const [subtitlePick, setSubtitlePick] = useState<VideoPick | null>(null);
  const [subtitleChanged, setSubtitleChanged] = useState(false);
  const [dupHint, setDupHint] = useState('');
  const saveDescRef = useRef<(() => Promise<OutputData>) | null>(null);
  const objectUrls = useRef<string[]>([]);

  const revokeUrls = () => {
    for (const u of objectUrls.current) URL.revokeObjectURL(u);
    objectUrls.current = [];
  };

  const resetAdd = () => {
    setL1(defaultL1 && defaultL1 !== 'all' ? defaultL1 : '');
    setL2(defaultL2 && defaultL2 !== 'all' ? defaultL2 : '');
    setCollection('');
    setTitle('');
    setVideoPick(null);
    setVideoChanged(false);
    setCoverBlob(null);
    setCoverPreview(null);
    setCoverChanged(false);
    setCoverPickerOpen(false);
    setInitialDesc(null);
    setMeta(null);
    setError('');
    setProgress(null);
    setLoading(false);
    setFavorite(false);
    setSubtitlePick(null);
    setSubtitleChanged(false);
    setDupHint('');
    saveDescRef.current = null;
    setEditorKey((k) => k + 1);
    revokeUrls();
  };

  useEffect(() => {
    if (!open) return;
    if (!isEdit) {
      resetAdd();
      return;
    }
    if (!entry || entry.legacy || !entry.dir) {
      setError('无法编辑该条目');
      return;
    }
    let cancelled = false;
    const run = async () => {
      setLoading(true);
      setError('');
      setCoverBlob(null);
      setCoverChanged(false);
      setVideoChanged(false);
      setCoverPickerOpen(false);
      setProgress(null);
      revokeUrls();
      try {
        const m = await getDataJson<EntryMeta>(`${entry.dir}/${META_NAME}`);
        if (cancelled) return;
        if (!m) throw new Error('读取条目失败');
        setMeta(m);
        setL1(entry.l1 || '');
        setL2(entry.l2 || '');
        setCollection(entry.collection || '');
        setTitle(m.title || entry.title);
        setInitialDesc(m.description || { blocks: [] });
        setFavorite(!!m.favorite);
        setEditorKey((k) => k + 1);
        setVideoPick({
          rel: entry.videoRel,
          name: m.video || entry.videoRel.split('/').pop() || 'video.mp4',
        });
        if (m.subtitle) {
          setSubtitlePick({
            rel: `${entry.dir}/${m.subtitle}`,
            name: m.subtitle,
          });
        } else {
          setSubtitlePick(null);
        }
        setSubtitleChanged(false);
        if (m.cover) {
          setCoverPreview(dataUrl(`${entry.dir}/${m.cover}`));
        } else if (entry.coverRel) {
          setCoverPreview(dataUrl(entry.coverRel));
        } else {
          setCoverPreview(null);
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : '加载失败');
      } finally {
        if (!cancelled) setLoading(false);
      }
    };
    void run();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, mode, entry, defaultL1, defaultL2]);

  useEffect(() => {
    if (open) return;
    revokeUrls();
  }, [open]);

  const l1Options = useMemo(() => l1Names(library), [library]);
  const l2Options = useMemo(() => (l1 ? l2Names(library, l1) : []), [library, l1]);
  const collectionOptions = useMemo(
    () => (l1 && l2 ? collectionNamesFor(library, l1, l2) : []),
    [library, l1, l2],
  );

  const handleClose = () => {
    if (busy) return;
    revokeUrls();
    onClose();
  };

  const onPickVideo = async () => {
    setError('');
    try {
      const picked = await pickFile('video/*');
      setVideoPick(picked);
      setVideoChanged(true);
      setCoverBlob(null);
      setCoverChanged(false);
      if (coverPreview?.startsWith('blob:')) URL.revokeObjectURL(coverPreview);
      setCoverPreview(null);
      const name = isStagedPick(picked) ? picked.name : picked.name;
      if (!title.trim() || !isEdit) {
        const i = name.lastIndexOf('.');
        const t = i > 0 ? name.slice(0, i) : name;
        setTitle(t);
        const dups = findDuplicateTitles(library, t, entry?.dir);
        setDupHint(dups.length ? `库中已有同名条目：${dups[0].title}` : '');
      }
    } catch (e) {
      if (e instanceof Error && e.message === 'cancelled') return;
      setError(e instanceof Error ? e.message : '选择视频失败');
    }
  };

  const onPickSubtitle = async () => {
    setError('');
    try {
      const picked = await pickFile('.srt,.ass,.ssa,.vtt,text/plain');
      setSubtitlePick(picked);
      setSubtitleChanged(true);
    } catch (e) {
      if (e instanceof Error && e.message === 'cancelled') return;
      setError(e instanceof Error ? e.message : '选择字幕失败');
    }
  };

  const openCoverPicker = () => {
    if (!videoPick) {
      setError('请先选择视频文件');
      return;
    }
    setError('');
    setCoverPickerOpen(true);
  };

  const onCoverConfirmed = (blob: Blob, previewUrl: string) => {
    setCoverBlob(blob);
    setCoverChanged(true);
    if (coverPreview?.startsWith('blob:')) URL.revokeObjectURL(coverPreview);
    objectUrls.current.push(previewUrl);
    setCoverPreview(previewUrl);
  };

  const saveDescription = async (): Promise<OutputData> => {
    if (saveDescRef.current) {
      try {
        return await saveDescRef.current();
      } catch {
        /* fallthrough */
      }
    }
    return initialDesc || meta?.description || { blocks: [] };
  };

  const submitAdd = async () => {
    const l1n = normalizeCatName(l1);
    const l2n = normalizeCatName(l2);
    const coln = normalizeCatName(collection);
    if (!l1n || isReservedName(l1n)) {
      setError('请填写有效的一级分类');
      return;
    }
    if (!l2n || isReservedName(l2n)) {
      setError('请填写有效的二级分类');
      return;
    }
    if (coln && isReservedName(coln)) {
      setError('合集名称不可用');
      return;
    }
    if (!videoPick) {
      setError('请选择视频文件');
      return;
    }
    const fileName = isStagedPick(videoPick) ? videoPick.name : videoPick.name;
    const titleN = title.trim() || fileName;
    setBusy(true);
    setError('');
    setProgress(0);
    const entryId = newEntryId();
    const dir = entryPath(l1n, l2n, coln || null, entryId);
    const videoName = `video.${videoExtFromName(fileName)}`;

    try {
      await ensureCatKeeps(l1n, l2n, coln);

      let videoBlob: Blob;
      if (isStagedPick(videoPick)) {
        const b = await getDataBlob(videoPick.rel);
        if (!b) throw new Error('读取暂存视频失败');
        videoBlob = b;
      } else {
        videoBlob = videoPick;
      }
      await putDataFileWithProgress(`${dir}/${videoName}`, videoBlob, (r) =>
        setProgress(r * 0.85),
      );

      let cover = coverBlob;
      if (!cover) cover = await resolveAutoCover(videoPick, fileName);
      let hasCover = false;
      if (cover) {
        await putDataFile(`${dir}/${COVER_NAME}`, cover);
        hasCover = true;
        setProgress(0.92);
      }

      let subtitleName: string | undefined;
      if (subtitlePick) {
        const subFileName = isStagedPick(subtitlePick)
          ? subtitlePick.name
          : subtitlePick.name;
        const ext = (() => {
          const i = subFileName.lastIndexOf('.');
          const e = i > 0 ? subFileName.slice(i + 1).toLowerCase() : 'srt';
          return ['srt', 'ass', 'ssa', 'vtt'].includes(e) ? e : 'srt';
        })();
        subtitleName = `subtitle.${ext}`;
        let subBlob: Blob;
        if (isStagedPick(subtitlePick)) {
          const b = await getDataBlob(subtitlePick.rel);
          if (!b) throw new Error('读取字幕失败');
          subBlob = b;
        } else {
          subBlob = subtitlePick;
        }
        await putDataFile(`${dir}/${subtitleName}`, subBlob);
      }

      const description = await saveDescription();
      const now = new Date().toISOString();
      const durationSec =
        (await resolveDurationSec(videoPick, `${dir}/${videoName}`)) ??
        undefined;
      const next: EntryMeta = {
        title: titleN,
        description,
        cover: hasCover ? COVER_NAME : undefined,
        video: videoName,
        subtitle: subtitleName,
        playCount: 0,
        durationSec,
        favorite,
        createdAt: now,
        updatedAt: now,
      };
      await putDataJson(`${dir}/${META_NAME}`, next);
      setProgress(1);
      revokeUrls();
      onDone();
      onClose();
    } catch (e) {
      console.error(e);
      setError(e instanceof Error ? e.message : '添加失败');
    } finally {
      setBusy(false);
      setProgress(null);
    }
  };

  const submitEdit = async () => {
    if (!entry || entry.legacy || !entry.dir || !meta || !videoPick) {
      setError('条目未就绪');
      return;
    }
    const l1n = normalizeCatName(l1);
    const l2n = normalizeCatName(l2);
    const coln = normalizeCatName(collection);
    if (!l1n || isReservedName(l1n)) {
      setError('请填写有效的一级分类');
      return;
    }
    if (!l2n || isReservedName(l2n)) {
      setError('请填写有效的二级分类');
      return;
    }
    if (coln && isReservedName(coln)) {
      setError('合集名称不可用');
      return;
    }

    const titleN = title.trim() || entry.title;
    const oldDir = entry.dir;
    const newDir = entryPath(l1n, l2n, coln || null, entry.id);
    const pathChanged = newDir !== oldDir;

    setBusy(true);
    setError('');
    setProgress(0);

    try {
      await ensureCatKeeps(l1n, l2n, coln);

      let videoName = meta.video;
      if (videoChanged) {
        const fileName = isStagedPick(videoPick) ? videoPick.name : videoPick.name;
        videoName = `video.${videoExtFromName(fileName)}`;
        let videoBlob: Blob;
        if (isStagedPick(videoPick)) {
          const b = await getDataBlob(videoPick.rel);
          if (!b) throw new Error('读取视频失败');
          videoBlob = b;
        } else {
          videoBlob = videoPick;
        }
        await putDataFileWithProgress(`${newDir}/${videoName}`, videoBlob, (r) =>
          setProgress(r * 0.7),
        );
      } else if (pathChanged) {
        const b = await getDataBlob(`${oldDir}/${meta.video}`);
        if (!b) throw new Error('读取原视频失败');
        await putDataFile(`${newDir}/${videoName}`, b);
        setProgress(0.5);
      }

      let coverName = meta.cover;
      if (coverChanged && coverBlob) {
        coverName = COVER_NAME;
        await putDataFile(`${newDir}/${COVER_NAME}`, coverBlob);
      } else if (pathChanged && meta.cover) {
        const b = await getDataBlob(`${oldDir}/${meta.cover}`);
        if (b) {
          coverName = meta.cover.endsWith('.jpg') ? meta.cover : COVER_NAME;
          await putDataFile(`${newDir}/${coverName}`, b);
        }
      } else if (!coverName && videoChanged) {
        const fileName = isStagedPick(videoPick) ? videoPick.name : videoPick.name;
        const auto = await resolveAutoCover(videoPick, fileName);
        if (auto) {
          coverName = COVER_NAME;
          await putDataFile(`${newDir}/${COVER_NAME}`, auto);
        }
      }

      let subtitleName = meta.subtitle;
      if (subtitleChanged && !subtitlePick) {
        subtitleName = undefined;
      } else if (subtitleChanged && subtitlePick) {
        const subFileName = isStagedPick(subtitlePick)
          ? subtitlePick.name
          : subtitlePick.name;
        const ext = (() => {
          const i = subFileName.lastIndexOf('.');
          const e = i > 0 ? subFileName.slice(i + 1).toLowerCase() : 'srt';
          return ['srt', 'ass', 'ssa', 'vtt'].includes(e) ? e : 'srt';
        })();
        subtitleName = `subtitle.${ext}`;
        let subBlob: Blob;
        if (isStagedPick(subtitlePick)) {
          const b = await getDataBlob(subtitlePick.rel);
          if (!b) throw new Error('读取字幕失败');
          subBlob = b;
        } else {
          subBlob = subtitlePick;
        }
        await putDataFile(`${newDir}/${subtitleName}`, subBlob);
      } else if (pathChanged && meta.subtitle) {
        const b = await getDataBlob(`${oldDir}/${meta.subtitle}`);
        if (b) {
          await putDataFile(`${newDir}/${meta.subtitle}`, b);
          subtitleName = meta.subtitle;
        }
      }

      const description = await saveDescription();
      let durationSec = meta.durationSec;
      if (videoChanged || durationSec == null || !(durationSec > 0)) {
        durationSec =
          (await resolveDurationSec(videoPick, `${newDir}/${videoName}`)) ??
          durationSec;
      }
      const next: EntryMeta = {
        ...meta,
        title: titleN,
        description,
        cover: coverName,
        video: videoName,
        subtitle: subtitleName,
        playCount: meta.playCount ?? 0,
        durationSec,
        favorite,
        createdAt: meta.createdAt || new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };
      await putDataJson(`${newDir}/${META_NAME}`, next);
      setProgress(0.95);

      if (pathChanged || videoChanged || subtitleChanged) {
        // 清理旧路径多余文件
        const toDelete = new Set<string>();
        if (pathChanged) {
          toDelete.add(`${oldDir}/${META_NAME}`);
          toDelete.add(`${oldDir}/${meta.video}`);
          if (meta.cover) toDelete.add(`${oldDir}/${meta.cover}`);
          if (meta.subtitle) toDelete.add(`${oldDir}/${meta.subtitle}`);
        } else {
          if (videoChanged && meta.video !== videoName) {
            toDelete.add(`${oldDir}/${meta.video}`);
          }
          if (
            subtitleChanged &&
            meta.subtitle &&
            meta.subtitle !== subtitleName
          ) {
            toDelete.add(`${oldDir}/${meta.subtitle}`);
          }
        }
        for (const rel of toDelete) {
          try {
            await deleteDataFile(rel);
          } catch {
            /* ignore */
          }
        }
      }

      setProgress(1);
      revokeUrls();
      onDone();
      onClose();
    } catch (e) {
      console.error(e);
      setError(e instanceof Error ? e.message : '保存失败');
    } finally {
      setBusy(false);
      setProgress(null);
    }
  };

  const submit = () => {
    if (isEdit) void submitEdit();
    else void submitAdd();
  };

  const formReady = !loading && (!isEdit || !!meta);

  return (
    <>
      <Dialog open={open} onClose={handleClose} fullWidth maxWidth="sm">
        <DialogTitle>{isEdit ? '编辑视频' : '添加视频'}</DialogTitle>
        <DialogContent>
          <Stack spacing={2} sx={{ marginTop: '10px' }}>
            {loading ? (
              <Typography color="text.secondary">加载中…</Typography>
            ) : (
              <>
                <Autocomplete
                  freeSolo
                  options={l1Options}
                  value={l1}
                  onInputChange={(_, v) => {
                    setL1(v);
                    setL2('');
                    setCollection('');
                  }}
                  renderInput={(params) => (
                    <TextField {...params} label="一级分类" required disabled={busy} />
                  )}
                />
                <Autocomplete
                  freeSolo
                  options={l2Options}
                  value={l2}
                  onInputChange={(_, v) => {
                    setL2(v);
                    setCollection('');
                  }}
                  renderInput={(params) => (
                    <TextField {...params} label="二级分类" required disabled={busy || !l1} />
                  )}
                />
                <Autocomplete
                  freeSolo
                  options={collectionOptions}
                  value={collection}
                  onInputChange={(_, v) => setCollection(v)}
                  renderInput={(params) => (
                    <TextField
                      {...params}
                      label="合集 / 剧集名（可选）"
                      disabled={busy || !l1 || !l2}
                      helperText="同名多集会在列表收成一张卡（显示名称与集数）"
                    />
                  )}
                />
                <TextField
                  label="标题"
                  value={title}
                  onChange={(e) => {
                    const v = e.target.value;
                    setTitle(v);
                    const dups = findDuplicateTitles(library, v, entry?.dir);
                    setDupHint(dups.length ? `库中已有同名条目（${dups.length}）` : '');
                  }}
                  disabled={busy}
                  fullWidth
                />
                {dupHint && <Alert severity="warning">{dupHint}</Alert>}
                <FormControlLabel
                  control={
                    <Checkbox
                      checked={favorite}
                      onChange={(e) => setFavorite(e.target.checked)}
                      disabled={busy}
                    />
                  }
                  label="收藏 / 稍后再看"
                />
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center', flexWrap: 'wrap' }}>
                  <Button variant="outlined" disabled={busy} onClick={() => void onPickVideo()}>
                    {isEdit ? '更换视频' : '选择视频'}
                  </Button>
                  <Typography variant="body2" color="text.secondary" noWrap sx={{ maxWidth: 220 }}>
                    {pickDisplayName(videoPick)}
                  </Typography>
                  {isEdit && (
                    <Typography variant="body2" color="text.secondary">
                      播放 {meta?.playCount ?? entry?.playCount ?? 0} 次
                    </Typography>
                  )}
                </Stack>
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center', flexWrap: 'wrap' }}>
                  <Button
                    variant="outlined"
                    disabled={busy}
                    onClick={() => void onPickSubtitle()}
                  >
                    {subtitlePick ? '更换字幕' : '外挂字幕'}
                  </Button>
                  <Typography variant="body2" color="text.secondary" noWrap sx={{ maxWidth: 220 }}>
                    {subtitlePick ? pickDisplayName(subtitlePick) : '未选择（可选 .srt/.ass）'}
                  </Typography>
                  {subtitlePick && (
                    <Button
                      size="small"
                      disabled={busy}
                      onClick={() => {
                        setSubtitlePick(null);
                        setSubtitleChanged(true);
                      }}
                    >
                      清除
                    </Button>
                  )}
                </Stack>
                <Stack direction="row" spacing={1} sx={{ alignItems: 'center', flexWrap: 'wrap' }}>
                  <Button
                    variant="outlined"
                    onClick={openCoverPicker}
                    disabled={busy || !videoPick}
                  >
                    选择封面
                  </Button>
                </Stack>
                {coverPreview && (
                  <Box
                    component="img"
                    src={coverPreview}
                    alt="封面预览"
                    sx={{ maxWidth: 240, maxHeight: 135, objectFit: 'cover', borderRadius: 1 }}
                  />
                )}
                <Typography variant="subtitle2">描述</Typography>
                {open && formReady && (
                  <DescriptionEditor
                    key={editorKey}
                    initial={initialDesc}
                    onReady={(api) => {
                      saveDescRef.current = api.save;
                    }}
                    disabled={busy}
                  />
                )}
              </>
            )}
            {progress != null && (
              <LinearProgress variant="determinate" value={Math.round(progress * 100)} />
            )}
            {error && (
              <Typography color="error" variant="body2">
                {error}
              </Typography>
            )}
          </Stack>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} disabled={busy}>
            取消
          </Button>
          <Button
            variant="contained"
            onClick={submit}
            disabled={busy || loading || (isEdit && !meta)}
          >
            {busy ? (isEdit ? '保存中…' : '上传中…') : isEdit ? '保存' : '确定'}
          </Button>
        </DialogActions>
      </Dialog>

      {videoPick && (
        <CoverPickerDialog
          open={coverPickerOpen}
          videoPick={videoPick}
          onClose={() => setCoverPickerOpen(false)}
          onConfirm={onCoverConfirmed}
        />
      )}
    </>
  );
}
