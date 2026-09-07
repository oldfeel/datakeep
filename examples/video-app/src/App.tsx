import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert,
  AppBar,
  Box,
  Button,
  Card,
  CardActionArea,
  CardContent,
  CardMedia,
  Chip,
  CssBaseline,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  IconButton,
  InputAdornment,
  InputLabel,
  List,
  ListItemButton,
  ListItemText,
  MenuItem,
  Select,
  Stack,
  TextField,
  Toolbar,
  Typography,
} from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import EditIcon from '@mui/icons-material/Edit';
import FolderIcon from '@mui/icons-material/Folder';
import SearchIcon from '@mui/icons-material/Search';
import MovieIcon from '@mui/icons-material/Movie';
import { dataUrl, getDataJson, putDataFile, putDataJson, watchData } from './datakeep';
import VideoEntryDialog from './VideoEntryDialog';
import {
  formatDuration,
  hasPlayVideoHost,
  hasProbeDurationHost,
  playVideoFromRel,
  probeDurationFromRel,
} from './host';
import {
  KEEP_NAME,
  META_NAME,
  RESERVED_NAMES,
  collapseToLibraryItems,
  countEntriesInL1,
  emptyLibrary,
  filterEntries,
  isReservedName,
  l1Names,
  l2Names,
  normalizeCatName,
  scanLibrary,
  sortEntries,
  type EntryMeta,
  type EntrySort,
  type Library,
  type SeriesGroup,
  type VideoEntry,
} from './library';

type L1Id = 'all' | string;

type SeriesFocus = { l1: string; l2: string; name: string };

export default function App() {
  const [library, setLibrary] = useState<Library>(emptyLibrary);
  const [l1, setL1] = useState<L1Id>('all');
  const [l2, setL2] = useState<string>('all');
  const [seriesFocus, setSeriesFocus] = useState<SeriesFocus | null>(null);
  const [query, setQuery] = useState('');
  const [playing, setPlaying] = useState<VideoEntry | null>(null);
  const [playError, setPlayError] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [editEntry, setEditEntry] = useState<VideoEntry | null>(null);
  const [sortBy, setSortBy] = useState<EntrySort>('createdAt_desc');
  const [addingL1, setAddingL1] = useState(false);
  const [l1Input, setL1Input] = useState('');
  const [l1Error, setL1Error] = useState('');
  const [l1Busy, setL1Busy] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const lib = await scanLibrary();
      setLibrary(lib);
      setL1((prev) => {
        if (prev === 'all') return prev;
        if (!lib.l1ToL2[prev]) {
          setL2('all');
          setSeriesFocus(null);
          return 'all';
        }
        return prev;
      });
    } catch (e) {
      console.error(e);
    }
  }, []);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => watchData(() => void refresh()), [refresh]);

  const l1List = useMemo(() => l1Names(library), [library]);
  const l2List = useMemo(() => l2Names(library, l1), [library, l1]);

  const filtered = useMemo(() => {
    let list = filterEntries(library, {
      l1,
      l2,
      collection: null,
      query: seriesFocus ? '' : query,
    });
    if (seriesFocus) {
      list = list.filter(
        (e) =>
          e.l1 === seriesFocus.l1 &&
          e.l2 === seriesFocus.l2 &&
          e.collection === seriesFocus.name,
      );
    }
    return list;
  }, [library, l1, l2, seriesFocus, query]);

  /** 点进剧集：只列各集；否则折叠合集为一张卡（搜索时扁平列出命中） */
  const gridItems = useMemo(() => {
    const sorted = sortEntries(filtered, sortBy);
    if (seriesFocus || query.trim()) {
      return sorted.map((entry) => ({ kind: 'video' as const, entry }));
    }
    return collapseToLibraryItems(sorted, sortBy);
  }, [filtered, sortBy, seriesFocus, query]);

  const selectL1 = (id: L1Id) => {
    setL1(id);
    setL2('all');
    setSeriesFocus(null);
    setPlaying(null);
  };

  const selectL2 = (id: string) => {
    setL2(id);
    setSeriesFocus(null);
    setPlaying(null);
  };

  const openSeries = (g: SeriesGroup) => {
    setSeriesFocus({ l1: g.l1, l2: g.l2, name: g.name });
    setPlaying(null);
  };

  const closePlayer = () => {
    setPlaying(null);
    setPlayError('');
  };

  const bumpPlayCount = async (e: VideoEntry) => {
    if (e.legacy || !e.dir) return;
    try {
      const metaPath = `${e.dir}/${META_NAME}`;
      const meta = await getDataJson<EntryMeta>(metaPath);
      if (!meta) return;
      const next: EntryMeta = {
        ...meta,
        playCount: (meta.playCount ?? 0) + 1,
        createdAt: meta.createdAt || new Date().toISOString(),
        updatedAt: meta.updatedAt || meta.createdAt || new Date().toISOString(),
      };
      await putDataJson(metaPath, next);
      setLibrary((lib) => ({
        ...lib,
        entries: lib.entries.map((x) =>
          x.dir === e.dir ? { ...x, playCount: next.playCount ?? 0 } : x,
        ),
      }));
      setPlaying((cur) =>
        cur && cur.dir === e.dir ? { ...cur, playCount: next.playCount ?? 0 } : cur,
      );
    } catch (err) {
      console.error(err);
    }
  };

  const openWithHostPlayer = async (e: VideoEntry) => {
    try {
      await playVideoFromRel(e.videoRel, e.title);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      setPlaying(e);
      setPlayError(
        msg === 'NO_HOST'
          ? '无法调用 DataKeep 播放器，改用网页播放（部分格式可能不支持）。'
          : `播放失败：${msg}`,
      );
    }
  };

  const openEntry = async (e: VideoEntry) => {
    setPlayError('');
    void bumpPlayCount(e);

    // 有宿主时走与文件浏览相同的 media_kit（可播 mkv 等）
    if (hasPlayVideoHost()) {
      await openWithHostPlayer(e);
      return;
    }

    setPlaying(e);
  };

  /** 缺时长时探测并写回 meta（静默） */
  const ensureEntryDuration = useCallback(async (e: VideoEntry) => {
    if (e.durationSec != null && e.durationSec > 0) return;
    if (e.legacy || !e.dir || !hasProbeDurationHost()) return;
    try {
      const sec = await probeDurationFromRel(e.videoRel);
      if (sec == null || !(sec > 0)) return;
      const durationSec = Math.round(sec * 10) / 10;
      const metaPath = `${e.dir}/${META_NAME}`;
      const meta = await getDataJson<EntryMeta>(metaPath);
      if (!meta) return;
      await putDataJson(metaPath, { ...meta, durationSec });
      setLibrary((lib) => ({
        ...lib,
        entries: lib.entries.map((x) =>
          x.dir === e.dir ? { ...x, durationSec } : x,
        ),
      }));
    } catch (err) {
      console.error('探测时长失败', err);
    }
  }, []);

  const submitAddL1 = async () => {
    const name = normalizeCatName(l1Input);
    if (!name) {
      setL1Error('请输入分类名称');
      return;
    }
    if (isReservedName(name) || RESERVED_NAMES[name]) {
      setL1Error('该名称已保留');
      return;
    }
    if (library.l1ToL2[name]) {
      setL1Error('分类已存在');
      return;
    }
    setL1Busy(true);
    setL1Error('');
    try {
      await putDataFile(`${name}/${KEEP_NAME}`, '');
      setAddingL1(false);
      setL1Input('');
      setL1(name);
      setL2('all');
      await refresh();
    } catch (e) {
      setL1Error(e instanceof Error ? e.message : '添加失败');
    } finally {
      setL1Busy(false);
    }
  };

  return (
    <>
      <CssBaseline />
      <Box sx={{ minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
        <Box
          sx={{
            flex: 1,
            display: 'flex',
            minHeight: 0,
            flexDirection: { xs: 'column', sm: 'row' },
          }}
        >
          <Box
            component="nav"
            aria-label="一级分类"
            sx={{
              width: { xs: '100%', sm: 200 },
              flexShrink: 0,
              display: 'flex',
              flexDirection: { xs: 'row', sm: 'column' },
              borderRight: { sm: 1 },
              borderBottom: { xs: 1, sm: 'none' },
              borderColor: 'divider',
              bgcolor: 'background.paper',
              minHeight: 0,
            }}
          >
            <List
              dense
              sx={{
                flex: 1,
                py: 1,
                overflow: 'auto',
                display: { xs: 'flex', sm: 'block' },
                minHeight: 0,
              }}
            >
              <ListItemButton selected={l1 === 'all'} onClick={() => selectL1('all')}>
                <ListItemText primary="全部" />
                <Typography variant="body2" color="text.secondary" sx={{ flexShrink: 0, ml: 1 }}>
                  {countEntriesInL1(library, 'all')}
                </Typography>
              </ListItemButton>
              {l1List.map((name) => (
                <ListItemButton
                  key={name}
                  selected={l1 === name}
                  onClick={() => selectL1(name)}
                  sx={{ whiteSpace: 'nowrap' }}
                >
                  <ListItemText
                    primary={name}
                    slotProps={{
                      primary: {
                        noWrap: true,
                        sx: { overflow: 'hidden', textOverflow: 'ellipsis' },
                      },
                    }}
                  />
                  <Typography variant="body2" color="text.secondary" sx={{ flexShrink: 0, ml: 1 }}>
                    {countEntriesInL1(library, name)}
                  </Typography>
                </ListItemButton>
              ))}
            </List>
            <Button
              variant="outlined"
              size="small"
              onClick={() => {
                setL1Error('');
                setL1Input('');
                setAddingL1(true);
              }}
              sx={{ m: 1, flexShrink: 0 }}
            >
              添加分类
            </Button>
          </Box>

          <Box component="section" sx={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
            <Stack
              spacing={1.5}
              sx={{
                px: 2,
                pt: 1.5,
                pb: 1,
                borderBottom: 1,
                borderColor: 'divider',
                bgcolor: 'background.paper',
              }}
            >
              <Stack
                direction="row"
                spacing={1}
                sx={{ alignItems: 'center', flexWrap: 'wrap', gap: 1 }}
              >
                <Box sx={{ flex: 1, display: 'flex', flexWrap: 'wrap', gap: 0.75, minWidth: 0 }}>
                  {(l1 !== 'all' ? l2List : l2Names(library, 'all')).length > 0 || l1 !== 'all' ? (
                    <>
                      <Chip
                        label="全部"
                        size="small"
                        color={l2 === 'all' ? 'primary' : 'default'}
                        variant={l2 === 'all' ? 'filled' : 'outlined'}
                        onClick={() => selectL2('all')}
                      />
                      {(l1 !== 'all' ? l2List : l2Names(library, 'all')).map((name) => (
                        <Chip
                          key={name}
                          label={name}
                          size="small"
                          color={l2 === name ? 'primary' : 'default'}
                          variant={l2 === name ? 'filled' : 'outlined'}
                          onClick={() => selectL2(name)}
                        />
                      ))}
                    </>
                  ) : (
                    <Typography variant="body2" color="text.secondary">
                      二级分类
                    </Typography>
                  )}
                </Box>
                <Button
                  variant="contained"
                  size="small"
                  startIcon={<AddIcon />}
                  onClick={() => setAddOpen(true)}
                  sx={{ flexShrink: 0 }}
                >
                  添加视频
                </Button>
              </Stack>

              <Stack
                direction="row"
                spacing={1}
                sx={{ alignItems: 'center', flexWrap: 'wrap', gap: 1 }}
              >
                <TextField
                  size="small"
                  placeholder="搜索标题 / 描述"
                  value={query}
                  onChange={(e) => setQuery(e.target.value)}
                  sx={{ flex: 1, minWidth: 160 }}
                  slotProps={{
                    input: {
                      startAdornment: (
                        <InputAdornment position="start">
                          <SearchIcon fontSize="small" />
                        </InputAdornment>
                      ),
                    },
                  }}
                />
                <FormControl size="small" sx={{ minWidth: 132 }}>
                  <InputLabel id="sort-label">排序</InputLabel>
                  <Select
                    labelId="sort-label"
                    label="排序"
                    value={sortBy}
                    onChange={(e) => setSortBy(e.target.value as EntrySort)}
                  >
                    <MenuItem value="createdAt_desc">上传时间 · 新→旧</MenuItem>
                    <MenuItem value="createdAt_asc">上传时间 · 旧→新</MenuItem>
                    <MenuItem value="playCount_desc">播放次数 · 多→少</MenuItem>
                    <MenuItem value="playCount_asc">播放次数 · 少→多</MenuItem>
                  </Select>
                </FormControl>
              </Stack>
            </Stack>

            <Box sx={{ flex: 1, p: 2, pb: 4, overflowY: 'auto' }}>
              {seriesFocus && (
                <Button
                  startIcon={<ArrowBackIcon />}
                  onClick={() => setSeriesFocus(null)}
                  sx={{ mb: 2 }}
                >
                  返回列表 · {seriesFocus.name}
                </Button>
              )}

              <Box
                sx={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(10rem, 1fr))',
                  gap: 2,
                }}
              >
                {gridItems.map((item) => {
                  if (item.kind === 'series') {
                    return (
                      <SeriesCard
                        key={item.key}
                        group={item}
                        onOpen={() => openSeries(item)}
                      />
                    );
                  }
                  const e = item.entry;
                  return (
                    <EntryCard
                      key={e.dir || e.videoRel}
                      entry={e}
                      onOpen={() => void openEntry(e)}
                      onEnsureDuration={() => void ensureEntryDuration(e)}
                      onEdit={
                        e.legacy
                          ? undefined
                          : () => {
                              setEditEntry(e);
                            }
                      }
                    />
                  );
                })}
              </Box>

              {!gridItems.length && (
                <Typography color="text.secondary" sx={{ mt: 4, textAlign: 'center' }}>
                  {seriesFocus
                    ? '该合集暂无剧集。'
                    : '暂无视频。点击右上角「添加视频」，或将文件放入应用 data 目录。'}
                </Typography>
              )}
            </Box>
          </Box>
        </Box>
      </Box>

      <Dialog open={addingL1} onClose={() => !l1Busy && setAddingL1(false)} fullWidth maxWidth="xs">
        <DialogTitle>添加一级分类</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="分类名称"
            value={l1Input}
            error={!!l1Error}
            helperText={l1Error || ' '}
            disabled={l1Busy}
            onChange={(e) => {
              setL1Input(e.target.value);
              if (l1Error) setL1Error('');
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                void submitAddL1();
              }
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAddingL1(false)} disabled={l1Busy}>
            取消
          </Button>
          <Button variant="contained" onClick={() => void submitAddL1()} disabled={l1Busy}>
            确定
          </Button>
        </DialogActions>
      </Dialog>

      <VideoEntryDialog
        open={addOpen}
        mode="add"
        library={library}
        defaultL1={l1}
        defaultL2={l2}
        onClose={() => setAddOpen(false)}
        onDone={() => void refresh()}
      />

      <VideoEntryDialog
        open={!!editEntry}
        mode="edit"
        library={library}
        entry={editEntry}
        onClose={() => setEditEntry(null)}
        onDone={() => void refresh()}
      />

      {playing && (
        <Box
          sx={{
            position: 'fixed',
            inset: 0,
            zIndex: (t) => t.zIndex.modal,
            bgcolor: 'common.black',
            display: 'flex',
            flexDirection: 'column',
          }}
        >
          <AppBar position="static" color="default" elevation={0}>
            <Toolbar variant="dense">
              <Button startIcon={<ArrowBackIcon />} onClick={closePlayer} sx={{ mr: 1 }}>
                返回列表
              </Button>
              <Typography variant="subtitle1" noWrap sx={{ flex: 1 }}>
                {playing.title}
              </Typography>
            </Toolbar>
          </AppBar>
          <Box
            component="video"
            key={playing.videoRel}
            controls
            playsInline
            autoPlay
            src={dataUrl(playing.videoRel)}
            onError={() => {
              setPlayError('网页播放器无法解码此格式。');
              if (hasPlayVideoHost()) {
                void openWithHostPlayer(playing);
              }
            }}
            sx={{
              flex: 1,
              width: '100%',
              maxHeight: 'calc(100vh - 48px)',
              bgcolor: 'common.black',
              outline: 'none',
            }}
          />
          {playError && (
            <Alert severity="warning" sx={{ borderRadius: 0 }}>
              {playError}
            </Alert>
          )}
        </Box>
      )}
    </>
  );
}

function CoverDurationBadge({ sec }: { sec: number | null | undefined }) {
  const text = formatDuration(sec);
  if (!text) return null;
  return (
    <Box
      sx={{
        position: 'absolute',
        right: 6,
        bottom: 6,
        px: 0.75,
        py: 0.15,
        borderRadius: 0.75,
        bgcolor: 'rgba(0,0,0,0.72)',
        color: 'common.white',
        typography: 'caption',
        fontWeight: 600,
        lineHeight: 1.4,
        letterSpacing: 0.2,
      }}
    >
      {text}
    </Box>
  );
}

function EntryCard({
  entry,
  onOpen,
  onEdit,
  onEnsureDuration,
}: {
  entry: VideoEntry;
  onOpen: () => void;
  onEdit?: () => void;
  onEnsureDuration?: () => void;
}) {
  const cover = entry.coverRel ? dataUrl(entry.coverRel) : null;

  useEffect(() => {
    onEnsureDuration?.();
  }, [entry.dir, entry.videoRel, entry.durationSec, onEnsureDuration]);

  return (
    <Card variant="outlined" sx={{ position: 'relative' }}>
      {onEdit && (
        <IconButton
          size="small"
          aria-label="编辑"
          onClick={(ev) => {
            ev.stopPropagation();
            onEdit();
          }}
          sx={{
            position: 'absolute',
            top: 4,
            right: 4,
            zIndex: 1,
            bgcolor: 'rgba(0,0,0,0.45)',
            color: 'common.white',
            '&:hover': { bgcolor: 'rgba(0,0,0,0.65)' },
          }}
        >
          <EditIcon fontSize="small" />
        </IconButton>
      )}
      <CardActionArea onClick={onOpen}>
        <Box sx={{ position: 'relative', aspectRatio: '16 / 10' }}>
          {cover ? (
            <CardMedia
              component="img"
              image={cover}
              alt={entry.title}
              sx={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          ) : (
            <Box
              sx={{
                width: '100%',
                height: '100%',
                bgcolor: 'action.hover',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'text.secondary',
                overflow: 'hidden',
              }}
            >
              {entry.legacy ? (
                <Box
                  component="video"
                  muted
                  preload="metadata"
                  src={`${dataUrl(entry.videoRel)}#t=0.5`}
                  sx={{
                    width: '100%',
                    height: '100%',
                    objectFit: 'cover',
                    pointerEvents: 'none',
                  }}
                />
              ) : (
                <MovieIcon fontSize="large" />
              )}
            </Box>
          )}
          <CoverDurationBadge sec={entry.durationSec} />
        </Box>
        <CardContent sx={{ py: 1.25, '&:last-child': { pb: 1.25 } }}>
          <Typography
            variant="subtitle2"
            sx={{
              display: '-webkit-box',
              WebkitLineClamp: 2,
              WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
            }}
          >
            {entry.title}
          </Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }}>
            {[entry.l1, entry.l2].filter(Boolean).join(' / ') || '未分类'}
          </Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }}>
            播放 {entry.playCount} 次
            {entry.createdAt ? ` · ${entry.createdAt.slice(0, 10)}` : ''}
          </Typography>
        </CardContent>
      </CardActionArea>
    </Card>
  );
}

function SeriesCard({ group, onOpen }: { group: SeriesGroup; onOpen: () => void }) {
  const cover = group.coverRel ? dataUrl(group.coverRel) : null;
  const n = group.episodes.length;
  return (
    <Card variant="outlined">
      <CardActionArea onClick={onOpen}>
        <Box sx={{ position: 'relative', aspectRatio: '16 / 10' }}>
          {cover ? (
            <CardMedia
              component="img"
              image={cover}
              alt={group.name}
              sx={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          ) : (
            <Box
              sx={{
                width: '100%',
                height: '100%',
                bgcolor: 'action.hover',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: 'text.secondary',
              }}
            >
              <FolderIcon fontSize="large" />
            </Box>
          )}
          <CoverDurationBadge sec={group.durationSec} />
        </Box>
        <CardContent sx={{ py: 1.25, '&:last-child': { pb: 1.25 } }}>
          <Typography
            variant="subtitle2"
            sx={{
              display: '-webkit-box',
              WebkitLineClamp: 2,
              WebkitBoxOrient: 'vertical',
              overflow: 'hidden',
            }}
          >
            {group.name}
          </Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }}>
            {[group.l1, group.l2].filter(Boolean).join(' / ') || '未分类'}
          </Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }}>
            {n} 集 · 播放 {group.playCount} 次
          </Typography>
        </CardContent>
      </CardActionArea>
    </Card>
  );
}
