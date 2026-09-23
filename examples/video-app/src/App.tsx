import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type DragEvent as ReactDragEvent,
} from 'react';
import {
  Alert,
  AppBar,
  Box,
  Button,
  Card,
  CardActionArea,
  CardContent,
  CardMedia,
  Checkbox,
  Chip,
  CssBaseline,
  Dialog,
  DialogActions,
  DialogContent,
  DialogContentText,
  DialogTitle,
  FormControl,
  FormControlLabel,
  IconButton,
  InputAdornment,
  InputLabel,
  LinearProgress,
  List,
  ListItemButton,
  ListItemText,
  Menu,
  MenuItem,
  Select,
  Stack,
  TextField,
  Toolbar,
  Tooltip,
  Typography,
} from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import DeleteIcon from '@mui/icons-material/Delete';
import DragIndicatorIcon from '@mui/icons-material/DragIndicator';
import EditIcon from '@mui/icons-material/Edit';
import FavoriteIcon from '@mui/icons-material/Favorite';
import FavoriteBorderIcon from '@mui/icons-material/FavoriteBorder';
import FolderIcon from '@mui/icons-material/Folder';
import FolderOpenIcon from '@mui/icons-material/FolderOpen';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import MovieIcon from '@mui/icons-material/Movie';
import PlaylistAddIcon from '@mui/icons-material/PlaylistAdd';
import SearchIcon from '@mui/icons-material/Search';
import SettingsIcon from '@mui/icons-material/Settings';
import ShareIcon from '@mui/icons-material/Share';
import StarIcon from '@mui/icons-material/Star';
import {
  dataUrl,
  deleteDataFile,
  deleteDataTree,
  getDataBlob,
  getDataJson,
  listDir,
  moveDataTree,
  putDataFile,
  putDataFileWithProgress,
  putDataJson,
  watchData,
} from './datakeep';
import VideoEntryDialog from './VideoEntryDialog';
import {
  formatDuration,
  hasPlayVideoHost,
  hasProbeDurationHost,
  hasRevealHost,
  hasShareHost,
  isStagedPick,
  pickFiles,
  playVideoFromRel,
  probeDurationFromRel,
  revealInFolder,
  shareFileFromRel,
  type PickedStagedFile,
} from './host';
import {
  KEEP_NAME,
  META_NAME,
  RESERVED_NAMES,
  collapseToLibraryItems,
  collectionNamesFor,
  countEntriesInL1,
  countEntriesInL2,
  countFavorites,
  emptyLibrary,
  entryPath,
  filterEntries,
  findDuplicateTitles,
  isL1Empty,
  isL2Empty,
  isReservedName,
  l1Names,
  l2Names,
  newEntryId,
  nextEpisode,
  nextEpisodeOrderBase,
  normalizeCatName,
  resolveCollectionName,
  scanLibrary,
  seriesEpisodes,
  sortEntries,
  sortSeriesEpisodes,
  videoExtFromName,
  type EntryMeta,
  type EntrySort,
  type Library,
  type LibraryItem,
  type SeriesGroup,
  type VideoEntry,
} from './library';
import {
  applyNameOrder,
  densityMinWidth,
  loadAutoNext,
  loadDensity,
  loadL1Order,
  loadL2Order,
  loadLibraryOrder,
  loadPosterRatio,
  posterAspect,
  saveAutoNext,
  saveDensity,
  saveL1Order,
  saveL2Order,
  saveLibraryOrder,
  savePosterRatio,
  type ListDensity,
  type PosterRatio,
} from './prefs';

type L1Id = 'all' | 'favorites' | string;
type SeriesFocus = { l1: string; l2: string; name: string };

type DragGhost =
  | {
      kind: 'l1';
      x: number;
      y: number;
      name: string;
      count: number;
      selected: boolean;
    }
  | {
      kind: 'episode';
      x: number;
      y: number;
      entry: VideoEntry;
      aspect: string;
    }
  | {
      kind: 'series';
      x: number;
      y: number;
      group: SeriesGroup;
      aspect: string;
    };

/** 列表项移动到目标前；向下拖时修正下标偏移 */
function moveBefore<T>(list: T[], fromIdx: number, toIdx: number): T[] {
  if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return list;
  const next = [...list];
  const [item] = next.splice(fromIdx, 1);
  const insertAt = fromIdx < toIdx ? toIdx - 1 : toIdx;
  next.splice(insertAt, 0, item);
  return next;
}

function libraryItemKey(item: LibraryItem): string {
  if (item.kind === 'series') return `s:${item.key}`;
  return `v:${item.entry.dir || item.entry.videoRel}`;
}

function applyLibraryItemOrder(items: LibraryItem[], order: string[]): LibraryItem[] {
  if (!order.length || items.length < 2) return items;
  const keys = items.map(libraryItemKey);
  const ordered = applyNameOrder(keys, order);
  const byKey = new Map(keys.map((k, i) => [k, items[i]]));
  return ordered.map((k) => byKey.get(k)!).filter(Boolean);
}

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
  const [renameL1, setRenameL1] = useState<string | null>(null);
  const [renameInput, setRenameInput] = useState('');
  const [renameError, setRenameError] = useState('');
  const [renameBusy, setRenameBusy] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<
    | { kind: 'entry'; entry: VideoEntry }
    | { kind: 'l1'; name: string }
    | null
  >(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [batchOpen, setBatchOpen] = useState(false);
  const [prefsOpen, setPrefsOpen] = useState(false);
  const [density, setDensity] = useState<ListDensity>(() => loadDensity());
  const [posterRatio, setPosterRatio] = useState<PosterRatio>(() => loadPosterRatio());
  const [autoNext, setAutoNext] = useState(() => loadAutoNext());
  const [l1Order, setL1Order] = useState<string[]>(() => loadL1Order());
  const [l2OrderMap, setL2OrderMap] = useState<Record<string, string[]>>(() => loadL2Order());
  const [libraryOrderMap, setLibraryOrderMap] = useState<Record<string, string[]>>(
    () => loadLibraryOrder(),
  );
  const [l2EditOpen, setL2EditOpen] = useState(false);
  const [dragL1, setDragL1] = useState<string | null>(null);
  const [dropL1, setDropL1] = useState<string | null>(null);
  const [dragGhost, setDragGhost] = useState<DragGhost | null>(null);
  const [dragEpisodeDir, setDragEpisodeDir] = useState<string | null>(null);
  const [dropEpisodeDir, setDropEpisodeDir] = useState<string | null>(null);
  const [dragLibKey, setDragLibKey] = useState<string | null>(null);
  const [dropLibKey, setDropLibKey] = useState<string | null>(null);
  const dragLibKeyRef = useRef<string | null>(null);
  const dragEpisodeDirRef = useRef<string | null>(null);
  const dragL1Ref = useRef<string | null>(null);
  const dropLibKeyRef = useRef<string | null>(null);
  const dropEpisodeDirRef = useRef<string | null>(null);
  const gridRef = useRef<HTMLDivElement | null>(null);
  const [renameSeries, setRenameSeries] = useState<SeriesFocus | null>(null);
  const [dissolveSeries, setDissolveSeries] = useState<SeriesFocus | null>(null);
  const [seriesBusy, setSeriesBusy] = useState(false);
  const [snack, setSnack] = useState('');
  const webVideoRef = useRef<HTMLVideoElement | null>(null);
  const playingRef = useRef<VideoEntry | null>(null);
  playingRef.current = playing;

  const refresh = useCallback(async () => {
    try {
      const lib = await scanLibrary();
      setLibrary(lib);
      setL1((prev) => {
        if (prev === 'all' || prev === 'favorites') return prev;
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

  useEffect(() => {
    if (!snack) return;
    const t = window.setTimeout(() => setSnack(''), 3200);
    return () => window.clearTimeout(t);
  }, [snack]);

  // 拖拽结束 / 落到空隙：必须清虚影（CEF 在未命中 drop 目标时 dragend 偶发丢失）
  useEffect(() => {
    const clearDrag = () => {
      dragLibKeyRef.current = null;
      dragEpisodeDirRef.current = null;
      dragL1Ref.current = null;
      dropLibKeyRef.current = null;
      dropEpisodeDirRef.current = null;
      setDragGhost(null);
      setDragL1(null);
      setDropL1(null);
      setDragEpisodeDir(null);
      setDropEpisodeDir(null);
      setDragLibKey(null);
      setDropLibKey(null);
    };
    const isDragging = () =>
      !!(
        dragLibKeyRef.current ||
        dragEpisodeDirRef.current ||
        dragL1Ref.current
      );
    const allowDrop = (e: DragEvent) => {
      if (!isDragging()) return;
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
    };
    const onDropAnywhere = (e: DragEvent) => {
      if (!isDragging()) return;
      e.preventDefault();
      // 卡片自身 onDrop 已处理排序；此处兜底清状态（含空隙松开）
      window.setTimeout(clearDrag, 0);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isDragging()) clearDrag();
    };
    window.addEventListener('dragend', clearDrag, true);
    window.addEventListener('dragover', allowDrop, true);
    window.addEventListener('drop', onDropAnywhere);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('dragend', clearDrag, true);
      window.removeEventListener('dragover', allowDrop, true);
      window.removeEventListener('drop', onDropAnywhere);
      window.removeEventListener('keydown', onKey);
    };
  }, []);

  const clearLibDrag = () => {
    dragLibKeyRef.current = null;
    dropLibKeyRef.current = null;
    setDragLibKey(null);
    setDropLibKey(null);
    setDragGhost(null);
  };

  const nearestLibKeyAt = (clientX: number, clientY: number): string | null => {
    const root = gridRef.current;
    if (!root) return null;
    const nodes = root.querySelectorAll<HTMLElement>('[data-lib-key]');
    let best: string | null = null;
    let bestDist = Infinity;
    nodes.forEach((el) => {
      const key = el.dataset.libKey;
      if (!key || key === dragLibKeyRef.current) return;
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const d = (cx - clientX) ** 2 + (cy - clientY) ** 2;
      if (d < bestDist) {
        bestDist = d;
        best = key;
      }
    });
    return best;
  };

  const nearestEpisodeDirAt = (clientX: number, clientY: number): string | null => {
    const root = gridRef.current;
    if (!root) return null;
    const nodes = root.querySelectorAll<HTMLElement>('[data-ep-dir]');
    let best: string | null = null;
    let bestDist = Infinity;
    nodes.forEach((el) => {
      const dir = el.dataset.epDir;
      if (!dir || dir === dragEpisodeDirRef.current) return;
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width / 2;
      const cy = r.top + r.height / 2;
      const d = (cx - clientX) ** 2 + (cy - clientY) ** 2;
      if (d < bestDist) {
        bestDist = d;
        best = dir;
      }
    });
    return best;
  };

  const l1List = useMemo(
    () => applyNameOrder(l1Names(library), l1Order),
    [library, l1Order],
  );
  const l2List = useMemo(() => {
    const base = l2Names(library, l1 === 'favorites' ? 'all' : l1);
    if (l1 === 'all' || l1 === 'favorites') return base;
    return applyNameOrder(base, l2OrderMap[l1] || []);
  }, [library, l1, l2OrderMap]);
  const favCount = useMemo(() => countFavorites(library), [library]);

  const filtered = useMemo(() => {
    const favoriteOnly = l1 === 'favorites';
    let list = filterEntries(library, {
      l1: favoriteOnly ? 'all' : l1,
      l2: favoriteOnly ? 'all' : l2,
      collection: null,
      query: seriesFocus ? '' : query,
      favoriteOnly,
    });
    if (seriesFocus) {
      const focusCol = normalizeCatName(seriesFocus.name);
      list = list.filter(
        (e) =>
          e.l1 === seriesFocus.l1 &&
          e.l2 === seriesFocus.l2 &&
          !!e.collection &&
          normalizeCatName(e.collection) === focusCol,
      );
    }
    return list;
  }, [library, l1, l2, seriesFocus, query]);

  const libraryOrderScope = useMemo(() => {
    if (l1 === 'all' || l1 === 'favorites') return 'all';
    if (l2 === 'all') return l1;
    return `${l1}/${l2}`;
  }, [l1, l2]);

  const gridItems = useMemo(() => {
    if (seriesFocus) {
      return sortEntries(filtered, sortBy).map((entry) => ({
        kind: 'video' as const,
        entry,
      }));
    }
    const sortKey = sortBy === 'custom' ? 'createdAt_desc' : sortBy;
    const sorted = sortEntries(filtered, sortKey);
    let items: LibraryItem[] =
      query.trim() || l1 === 'favorites'
        ? sorted.map((entry) => ({ kind: 'video' as const, entry }))
        : collapseToLibraryItems(sorted, sortKey);

    if (sortBy === 'custom') {
      items = applyLibraryItemOrder(items, libraryOrderMap[libraryOrderScope] || []);
    }
    return items;
  }, [filtered, sortBy, seriesFocus, query, l1, libraryOrderMap, libraryOrderScope]);

  const selectL1 = (id: L1Id) => {
    setL1(id);
    setL2('all');
    setSeriesFocus(null);
    setPlaying(null);
    if (sortBy === 'custom') setSortBy('createdAt_desc');
  };

  const selectL2 = (id: string) => {
    setL2(id);
    setSeriesFocus(null);
    setPlaying(null);
    if (sortBy === 'custom') setSortBy('createdAt_desc');
  };

  const openSeries = (g: SeriesGroup) => {
    setSeriesFocus({ l1: g.l1, l2: g.l2, name: g.name });
    setPlaying(null);
    const hasCustom = g.episodes.some((e) => e.episodeOrder != null);
    setSortBy(hasCustom ? 'custom' : sortBy === 'custom' ? 'createdAt_asc' : sortBy);
  };

  const patchEntryLocal = (dir: string, patch: Partial<VideoEntry>) => {
    setLibrary((lib) => ({
      ...lib,
      entries: lib.entries.map((x) => (x.dir === dir ? { ...x, ...patch } : x)),
    }));
  };

  const saveMetaPatch = async (e: VideoEntry, patch: Partial<EntryMeta>) => {
    if (e.legacy || !e.dir) return;
    const metaPath = `${e.dir}/${META_NAME}`;
    const meta = await getDataJson<EntryMeta>(metaPath);
    if (!meta) return;
    const next: EntryMeta = {
      ...meta,
      ...patch,
      updatedAt: new Date().toISOString(),
      createdAt: meta.createdAt || new Date().toISOString(),
    };
    await putDataJson(metaPath, next);
    return next;
  };

  const bumpPlayCount = async (e: VideoEntry) => {
    if (e.legacy || !e.dir) return;
    try {
      const next = await saveMetaPatch(e, {
        playCount: (e.playCount ?? 0) + 1,
      });
      if (!next) return;
      patchEntryLocal(e.dir, { playCount: next.playCount ?? 0 });
    } catch (err) {
      console.error(err);
    }
  };

  const saveWatchProgress = async (
    e: VideoEntry,
    positionSec: number,
    completed?: boolean,
  ) => {
    if (e.legacy || !e.dir) return;
    try {
      let pos = Math.max(0, Math.round(positionSec));
      if (completed) pos = 0;
      else if (e.durationSec && pos >= e.durationSec - 2) pos = 0;
      await saveMetaPatch(e, { positionSec: pos });
      patchEntryLocal(e.dir, { positionSec: pos });
    } catch (err) {
      console.error(err);
    }
  };

  const toggleFavorite = async (e: VideoEntry) => {
    if (e.legacy || !e.dir) return;
    try {
      const next = !e.favorite;
      await saveMetaPatch(e, { favorite: next });
      patchEntryLocal(e.dir, { favorite: next });
      setSnack(next ? '已加入收藏' : '已取消收藏');
    } catch (err) {
      setSnack(err instanceof Error ? err.message : '操作失败');
    }
  };

  const moveEpisode = async (e: VideoEntry, delta: -1 | 1) => {
    if (!e.collection || e.legacy || !e.dir) return;
    const eps = sortSeriesEpisodes(
      library.entries.filter(
        (x) =>
          x.l1 === e.l1 &&
          x.l2 === e.l2 &&
          x.collection === e.collection &&
          !x.legacy,
      ),
    );
    const i = eps.findIndex((x) => x.dir === e.dir);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= eps.length) return;
    try {
      for (let k = 0; k < eps.length; k++) {
        const order = k === i ? j : k === j ? i : k;
        await saveMetaPatch(eps[k], { episodeOrder: order });
        patchEntryLocal(eps[k].dir, { episodeOrder: order });
      }
      setSortBy('custom');
      await refresh();
    } catch (err) {
      setSnack(err instanceof Error ? err.message : '排序失败');
    }
  };

  const resumeStart = (e: VideoEntry) =>
    e.positionSec > 5 &&
    (!e.durationSec || e.positionSec < e.durationSec * 0.95)
      ? e.positionSec
      : 0;

  const playOne = async (e: VideoEntry): Promise<boolean> => {
    setPlayError('');
    void bumpPlayCount(e);

    const start = resumeStart(e);
    // 播放列表顺序与当前合集列表展示一致（含自定义 / 时间等排序）
    const eps =
      seriesFocus && e.collection
        ? sortEntries(
            library.entries.filter(
              (x) =>
                x.l1 === seriesFocus.l1 &&
                x.l2 === seriesFocus.l2 &&
                !!x.collection &&
                normalizeCatName(x.collection) ===
                  normalizeCatName(seriesFocus.name) &&
                !x.legacy,
            ),
            sortBy,
          )
        : seriesEpisodes(library, e);
    const playlist = eps.map((x) => ({
      rel: x.videoRel,
      title: x.title,
      subtitleRel: x.subtitleRel || undefined,
      startPosition: resumeStart(x),
      entryDir: x.dir,
      favorite: x.favorite,
    }));

    if (hasPlayVideoHost()) {
      try {
        const result = await playVideoFromRel(e.videoRel, e.title, {
          startPosition: start,
          subtitleRel: e.subtitleRel || undefined,
          entryDir: e.dir,
          favorite: e.favorite,
          autoNext,
          playlist,
        });
        await refresh();
        return !!result.completed;
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        setPlaying(e);
        setPlayError(
          msg === 'NO_HOST'
            ? '无法调用 DataKeep 播放器，改用网页播放（部分格式可能不支持）。'
            : `播放失败：${msg}`,
        );
        return false;
      }
    }

    setPlaying(e);
    return false;
  };

  const openEntry = async (e: VideoEntry) => {
    const completed = await playOne(e);
    if (!completed || !autoNext || hasPlayVideoHost()) return;
    const nxt = nextEpisode(library, e);
    if (nxt) {
      setSnack(`即将播放下一集：${nxt.title}`);
      await openEntry(nxt);
    }
  };

  const reorderL1 = (from: string, to: string) => {
    if (from === to) return;
    const i = l1List.indexOf(from);
    const j = l1List.indexOf(to);
    if (i < 0 || j < 0) return;
    const next = moveBefore(l1List, i, j);
    setL1Order(next);
    saveL1Order(next);
  };

  const reorderEpisodes = async (fromDir: string, toDir: string) => {
    if (!seriesFocus || fromDir === toDir) return;
    const focusCol = normalizeCatName(seriesFocus.name);
    const eps = sortSeriesEpisodes(
      library.entries.filter(
        (x) =>
          x.l1 === seriesFocus.l1 &&
          x.l2 === seriesFocus.l2 &&
          !!x.collection &&
          normalizeCatName(x.collection) === focusCol &&
          !x.legacy,
      ),
    );
    const i = eps.findIndex((x) => x.dir === fromDir);
    const j = eps.findIndex((x) => x.dir === toDir);
    if (i < 0 || j < 0) return;
    const next = moveBefore(eps, i, j);
    try {
      for (let k = 0; k < next.length; k++) {
        await saveMetaPatch(next[k], { episodeOrder: k });
        patchEntryLocal(next[k].dir, { episodeOrder: k });
      }
      setSortBy('custom');
      setSnack('已更新合集顺序（自定义排序）');
      await refresh();
    } catch (err) {
      setSnack(err instanceof Error ? err.message : '排序失败');
    } finally {
      setDragGhost(null);
      setDragEpisodeDir(null);
      setDropEpisodeDir(null);
    }
  };

  const reorderLibraryItems = (fromKey: string, toKey: string) => {
    if (!fromKey || !toKey || fromKey === toKey) return;
    const keys = gridItems.map(libraryItemKey);
    const i = keys.indexOf(fromKey);
    const j = keys.indexOf(toKey);
    if (i < 0 || j < 0) return;
    const nextKeys = moveBefore(keys, i, j);
    const nextMap = { ...libraryOrderMap, [libraryOrderScope]: nextKeys };
    setLibraryOrderMap(nextMap);
    saveLibraryOrder(nextMap);
    setSortBy('custom');
    clearLibDrag();
  };

  const submitRenameSeries = async () => {
    if (!renameSeries) return;
    const newName = normalizeCatName(renameInput);
    if (!newName) {
      setRenameError('请输入名称');
      return;
    }
    if (newName === renameSeries.name) {
      setRenameSeries(null);
      return;
    }
    if (isReservedName(newName)) {
      setRenameError('该名称已保留');
      return;
    }
    const existing = collectionNamesFor(library, renameSeries.l1, renameSeries.l2);
    if (existing.includes(newName)) {
      setRenameError('同名合集已存在');
      return;
    }
    setSeriesBusy(true);
    setRenameError('');
    try {
      const from = `${renameSeries.l1}/${renameSeries.l2}/${renameSeries.name}`;
      const to = `${renameSeries.l1}/${renameSeries.l2}/${newName}`;
      await moveDataTree(from, to);
      if (
        seriesFocus &&
        seriesFocus.l1 === renameSeries.l1 &&
        seriesFocus.l2 === renameSeries.l2 &&
        seriesFocus.name === renameSeries.name
      ) {
        setSeriesFocus({ ...seriesFocus, name: newName });
      }
      setRenameSeries(null);
      setSnack('合集已重命名');
      await refresh();
    } catch (e) {
      setRenameError(e instanceof Error ? e.message : '重命名失败');
    } finally {
      setSeriesBusy(false);
    }
  };

  const submitDissolveSeries = async () => {
    if (!dissolveSeries) return;
    setSeriesBusy(true);
    try {
      const eps = library.entries.filter(
        (x) =>
          x.l1 === dissolveSeries.l1 &&
          x.l2 === dissolveSeries.l2 &&
          x.collection === dissolveSeries.name &&
          !x.legacy &&
          x.dir,
      );
      for (const e of eps) {
        // l1/l2/collection/entryId → l1/l2/entryId
        const parts = e.dir.split('/');
        if (parts.length < 4) continue;
        const entryId = parts[parts.length - 1];
        const dest = `${dissolveSeries.l1}/${dissolveSeries.l2}/${entryId}`;
        await moveDataTree(e.dir, dest);
        // 清除自定义集序
        try {
          const meta = await getDataJson<EntryMeta>(`${dest}/${META_NAME}`);
          if (meta && meta.episodeOrder != null) {
            const { episodeOrder: _, ...rest } = meta;
            await putDataJson(`${dest}/${META_NAME}`, {
              ...rest,
              updatedAt: new Date().toISOString(),
            });
          }
        } catch {
          /* ignore */
        }
      }
      try {
        await deleteDataTree(
          `${dissolveSeries.l1}/${dissolveSeries.l2}/${dissolveSeries.name}`,
        );
      } catch {
        /* ignore */
      }
      if (
        seriesFocus &&
        seriesFocus.l1 === dissolveSeries.l1 &&
        seriesFocus.l2 === dissolveSeries.l2 &&
        seriesFocus.name === dissolveSeries.name
      ) {
        setSeriesFocus(null);
      }
      setDissolveSeries(null);
      setSnack('合集已解散，视频保留在原分类下');
      await refresh();
    } catch (e) {
      setSnack(e instanceof Error ? e.message : '解散失败');
    } finally {
      setSeriesBusy(false);
    }
  };

  const closePlayer = async () => {
    const e = playingRef.current;
    const v = webVideoRef.current;
    if (e && v) {
      await saveWatchProgress(e, v.currentTime, v.ended);
    }
    setPlaying(null);
    setPlayError('');
  };

  const ensureEntryDuration = useCallback(async (e: VideoEntry) => {
    if (e.durationSec != null && e.durationSec > 0) return;
    if (e.legacy || !e.dir || !hasProbeDurationHost()) return;
    try {
      const sec = await probeDurationFromRel(e.videoRel);
      if (sec == null || !(sec > 0)) return;
      const durationSec = Math.round(sec * 10) / 10;
      await saveMetaPatch(e, { durationSec });
      patchEntryLocal(e.dir, { durationSec });
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
    if (isReservedName(name) || RESERVED_NAMES[name] || name === 'favorites') {
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

  const confirmDelete = async () => {
    if (!deleteTarget) return;
    setDeleteBusy(true);
    try {
      if (deleteTarget.kind === 'entry') {
        const e = deleteTarget.entry;
        if (e.legacy) {
          await deleteDataTree(e.videoRel);
        } else if (e.dir) {
          await deleteDataTree(e.dir);
        }
        setSnack('已删除条目');
      } else {
        const name = deleteTarget.name;
        if (!isL1Empty(library, name)) {
          throw new Error('分类下仍有视频，请先删除条目');
        }
        await deleteDataTree(name);
        if (l1 === name) selectL1('all');
        setSnack('已删除空分类');
      }
      setDeleteTarget(null);
      await refresh();
    } catch (e) {
      setSnack(e instanceof Error ? e.message : '删除失败');
    } finally {
      setDeleteBusy(false);
    }
  };

  const submitRenameL1 = async () => {
    if (!renameL1) return;
    const newName = normalizeCatName(renameInput);
    if (!newName) {
      setRenameError('请输入新名称');
      return;
    }
    if (newName === renameL1) {
      setRenameL1(null);
      return;
    }
    if (isReservedName(newName) || RESERVED_NAMES[newName] || newName === 'favorites') {
      setRenameError('该名称已保留');
      return;
    }
    if (library.l1ToL2[newName]) {
      setRenameError('目标分类已存在');
      return;
    }
    setRenameBusy(true);
    setRenameError('');
    try {
      const all = await listDir('');
      const under = all.filter((f) => f === renameL1 || f.startsWith(renameL1 + '/'));
      under.sort((a, b) => a.length - b.length);
      for (const rel of under) {
        const dest = newName + rel.slice(renameL1.length);
        const blob = await getDataBlob(rel);
        if (blob) await putDataFile(dest, blob);
        else await putDataFile(dest, '');
      }
      under.sort((a, b) => b.length - a.length);
      for (const rel of under) {
        try {
          await deleteDataFile(rel);
        } catch {
          /* ignore */
        }
      }
      if (l1 === renameL1) setL1(newName);
      setRenameL1(null);
      setSnack('分类已重命名');
      await refresh();
    } catch (e) {
      setRenameError(e instanceof Error ? e.message : '重命名失败');
    } finally {
      setRenameBusy(false);
    }
  };

  const onReveal = async (e: VideoEntry) => {
    try {
      await revealInFolder(e.dir || e.videoRel);
    } catch (err) {
      setSnack(err instanceof Error ? err.message : '无法打开目录');
    }
  };

  const onShare = async (e: VideoEntry) => {
    try {
      await shareFileFromRel(e.videoRel);
    } catch (err) {
      setSnack(err instanceof Error ? err.message : '分享失败');
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
                '& .MuiListItemButton-root': {
                  borderRadius: 1,
                  mx: 0.75,
                  my: 0.25,
                  borderLeft: '3px solid transparent',
                  '&.Mui-selected': {
                    bgcolor: 'primary.main',
                    color: 'primary.contrastText',
                    borderLeftColor: 'primary.dark',
                    fontWeight: 600,
                    '&:hover': { bgcolor: 'primary.dark' },
                    '& .MuiTypography-root': { color: 'inherit', fontWeight: 600 },
                  },
                },
              }}
            >
              <ListItemButton selected={l1 === 'all'} onClick={() => selectL1('all')}>
                <ListItemText primary="全部" />
                <Typography variant="body2" sx={{ flexShrink: 0, ml: 1, opacity: 0.85 }}>
                  {countEntriesInL1(library, 'all')}
                </Typography>
              </ListItemButton>
              <ListItemButton
                selected={l1 === 'favorites'}
                onClick={() => selectL1('favorites')}
              >
                <StarIcon fontSize="small" sx={{ mr: 0.75, opacity: 0.9 }} />
                <ListItemText primary="收藏" />
                <Typography variant="body2" sx={{ flexShrink: 0, ml: 1, opacity: 0.85 }}>
                  {favCount}
                </Typography>
              </ListItemButton>
              {l1List.map((name) => (
                <L1NavItem
                  key={name}
                  name={name}
                  selected={l1 === name}
                  count={countEntriesInL1(library, name)}
                  empty={isL1Empty(library, name)}
                  dragging={dragL1 === name}
                  dropTarget={dropL1 === name && dragL1 !== name}
                  onSelect={() => selectL1(name)}
                  onRename={() => {
                    setRenameInput(name);
                    setRenameError('');
                    setRenameL1(name);
                  }}
                  onDelete={() => setDeleteTarget({ kind: 'l1', name })}
                  onDragStart={(ev) => {
                    setDragL1(name);
                    setDropL1(null);
                    setDragGhost({
                      kind: 'l1',
                      x: ev.clientX,
                      y: ev.clientY,
                      name,
                      count: countEntriesInL1(library, name),
                      selected: l1 === name,
                    });
                  }}
                  onDrag={(ev) => {
                    if (ev.clientX === 0 && ev.clientY === 0) return;
                    setDragGhost((g) =>
                      g && g.kind === 'l1'
                        ? { ...g, x: ev.clientX, y: ev.clientY }
                        : {
                            kind: 'l1',
                            x: ev.clientX,
                            y: ev.clientY,
                            name,
                            count: countEntriesInL1(library, name),
                            selected: l1 === name,
                          },
                    );
                  }}
                  onDragEnter={() => {
                    if (dragL1 && dragL1 !== name) setDropL1(name);
                  }}
                  onDragLeave={() => {
                    setDropL1((cur) => (cur === name ? null : cur));
                  }}
                  onDragEnd={() => {
                    setDragL1(null);
                    setDropL1(null);
                    setDragGhost(null);
                  }}
                  onDrop={(from) => {
                    reorderL1(from || dragL1 || '', name);
                    setDragL1(null);
                    setDropL1(null);
                    setDragGhost(null);
                  }}
                />
              ))}
            </List>
            <Stack direction="row" spacing={0.5} sx={{ m: 1, flexShrink: 0 }}>
              <Button
                variant="outlined"
                size="small"
                onClick={() => {
                  setL1Error('');
                  setL1Input('');
                  setAddingL1(true);
                }}
                sx={{ flex: 1 }}
              >
                添加分类
              </Button>
              <Tooltip title="显示设置">
                <IconButton size="small" onClick={() => setPrefsOpen(true)}>
                  <SettingsIcon fontSize="small" />
                </IconButton>
              </Tooltip>
            </Stack>
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
                <Box sx={{ flex: 1, display: 'flex', flexWrap: 'wrap', gap: 1, minWidth: 0, alignItems: 'center' }}>
                  {l1 !== 'favorites' &&
                  ((l1 !== 'all' ? l2List : l2Names(library, 'all')).length > 0 ||
                    l1 !== 'all') ? (
                    <>
                      <Chip
                        label="全部"
                        color={l2 === 'all' ? 'primary' : 'default'}
                        variant={l2 === 'all' ? 'filled' : 'outlined'}
                        onClick={() => selectL2('all')}
                        sx={{ height: 36, fontSize: '0.9rem', px: 0.5 }}
                      />
                      {(l1 !== 'all' ? l2List : l2Names(library, 'all')).map((name) => (
                        <Chip
                          key={name}
                          label={
                            l1 !== 'all' && l1 !== 'favorites'
                              ? `${name} (${countEntriesInL2(library, l1, name)})`
                              : name
                          }
                          color={l2 === name ? 'primary' : 'default'}
                          variant={l2 === name ? 'filled' : 'outlined'}
                          onClick={() => selectL2(name)}
                          sx={{ height: 36, fontSize: '0.9rem', px: 0.5 }}
                        />
                      ))}
                    </>
                  ) : (
                    <Typography variant="body2" color="text.secondary">
                      {l1 === 'favorites' ? '已收藏的视频' : '二级分类'}
                    </Typography>
                  )}
                </Box>
                {l1 !== 'all' && l1 !== 'favorites' && (
                  <Button
                    size="small"
                    variant="outlined"
                    startIcon={<EditIcon />}
                    onClick={() => setL2EditOpen(true)}
                    sx={{ flexShrink: 0, height: 36 }}
                  >
                    编辑二级分类
                  </Button>
                )}
                <Button
                  variant="outlined"
                  size="small"
                  startIcon={<PlaylistAddIcon />}
                  onClick={() => setBatchOpen(true)}
                  sx={{ flexShrink: 0 }}
                >
                  批量导入
                </Button>
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
                <FormControl size="small" sx={{ minWidth: 148 }}>
                  <InputLabel id="sort-label">排序</InputLabel>
                  <Select
                    labelId="sort-label"
                    label="排序"
                    value={sortBy}
                    onChange={(e) => setSortBy(e.target.value as EntrySort)}
                  >
                    <MenuItem value="custom">自定义（拖拽顺序）</MenuItem>
                    <MenuItem value="createdAt_desc">上传时间 · 新→旧</MenuItem>
                    <MenuItem value="createdAt_asc">上传时间 · 旧→新</MenuItem>
                    <MenuItem value="title_asc">标题 · A→Z</MenuItem>
                    <MenuItem value="title_desc">标题 · Z→A</MenuItem>
                    <MenuItem value="duration_desc">时长 · 长→短</MenuItem>
                    <MenuItem value="duration_asc">时长 · 短→长</MenuItem>
                    <MenuItem value="playCount_desc">播放次数 · 多→少</MenuItem>
                    <MenuItem value="playCount_asc">播放次数 · 少→多</MenuItem>
                  </Select>
                </FormControl>
              </Stack>
            </Stack>

            <Box sx={{ flex: 1, p: 2, pb: 4, overflowY: 'auto' }}>
              {seriesFocus ? (
                <Stack direction="row" spacing={1} sx={{ mb: 2, alignItems: 'center' }}>
                  <Button
                    startIcon={<ArrowBackIcon />}
                    onClick={() => setSeriesFocus(null)}
                  >
                    返回列表 · {seriesFocus.name}
                  </Button>
                  <Typography variant="caption" color="text.secondary">
                    {sortBy === 'custom'
                      ? '按住左侧手柄拖拽可调整集顺序'
                      : '拖拽排序将切换为「自定义」'}
                  </Typography>
                </Stack>
              ) : (
                !query.trim() &&
                l1 !== 'favorites' && (
                  <Typography variant="caption" color="text.secondary" sx={{ mb: 1.5, display: 'block' }}>
                    按住卡片左侧手柄可拖拽排序（视频与合集均可）
                  </Typography>
                )
              )}

              <Box
                ref={gridRef}
                onDragOver={(ev) => {
                  if (dragLibKeyRef.current) {
                    ev.preventDefault();
                    ev.dataTransfer.dropEffect = 'move';
                    const near = nearestLibKeyAt(ev.clientX, ev.clientY);
                    if (near && near !== dropLibKeyRef.current) {
                      dropLibKeyRef.current = near;
                      setDropLibKey(near);
                    }
                  } else if (dragEpisodeDirRef.current) {
                    ev.preventDefault();
                    ev.dataTransfer.dropEffect = 'move';
                    const near = nearestEpisodeDirAt(ev.clientX, ev.clientY);
                    if (near && near !== dropEpisodeDirRef.current) {
                      dropEpisodeDirRef.current = near;
                      setDropEpisodeDir(near);
                    }
                  }
                }}
                onDrop={(ev) => {
                  ev.preventDefault();
                  if (dragLibKeyRef.current) {
                    const from =
                      ev.dataTransfer.getData('text/plain') ||
                      dragLibKeyRef.current;
                    const to =
                      dropLibKeyRef.current ||
                      nearestLibKeyAt(ev.clientX, ev.clientY);
                    if (from && to) reorderLibraryItems(from, to);
                    else clearLibDrag();
                    return;
                  }
                  if (dragEpisodeDirRef.current) {
                    const from =
                      ev.dataTransfer.getData('text/plain') ||
                      dragEpisodeDirRef.current;
                    const to =
                      dropEpisodeDirRef.current ||
                      nearestEpisodeDirAt(ev.clientX, ev.clientY);
                    if (from && to) {
                      void reorderEpisodes(from, to);
                    }
                    dragEpisodeDirRef.current = null;
                    dropEpisodeDirRef.current = null;
                    setDragEpisodeDir(null);
                    setDropEpisodeDir(null);
                    setDragGhost(null);
                  }
                }}
                sx={{
                  display: 'grid',
                  gridTemplateColumns: `repeat(auto-fill, minmax(${densityMinWidth(density)}, 1fr))`,
                  gap: density === 'compact' ? 1.25 : 2,
                  minHeight: 80,
                }}
              >
                {gridItems.map((item) => {
                  const canLibDrag =
                    !seriesFocus && !query.trim() && l1 !== 'favorites';
                  if (item.kind === 'series') {
                    const libKey = libraryItemKey(item);
                    return (
                      <Box key={item.key} data-lib-key={libKey} sx={{ minWidth: 0 }}>
                      <SeriesCard
                        group={item}
                        aspect={posterAspect(posterRatio)}
                        onOpen={() => openSeries(item)}
                        onRename={() => {
                          setRenameInput(item.name);
                          setRenameError('');
                          setRenameSeries({
                            l1: item.l1,
                            l2: item.l2,
                            name: item.name,
                          });
                        }}
                        onDissolve={() =>
                          setDissolveSeries({
                            l1: item.l1,
                            l2: item.l2,
                            name: item.name,
                          })
                        }
                        draggable={canLibDrag}
                        dragging={dragLibKey === libKey}
                        dropTarget={
                          !!dragLibKey &&
                          dropLibKey === libKey &&
                          dragLibKey !== libKey
                        }
                        onDragStart={(ev) => {
                          dragLibKeyRef.current = libKey;
                          setDragLibKey(libKey);
                          setDropLibKey(null);
                          dropLibKeyRef.current = null;
                          setDragGhost({
                            kind: 'series',
                            x: ev.clientX,
                            y: ev.clientY,
                            group: item,
                            aspect: posterAspect(posterRatio),
                          });
                        }}
                        onDrag={(ev) => {
                          if (ev.clientX === 0 && ev.clientY === 0) return;
                          setDragGhost((g) =>
                            g && g.kind === 'series'
                              ? { ...g, x: ev.clientX, y: ev.clientY }
                              : {
                                  kind: 'series',
                                  x: ev.clientX,
                                  y: ev.clientY,
                                  group: item,
                                  aspect: posterAspect(posterRatio),
                                },
                          );
                        }}
                        onDragEnter={() => {
                          if (
                            dragLibKeyRef.current &&
                            dragLibKeyRef.current !== libKey
                          ) {
                            dropLibKeyRef.current = libKey;
                            setDropLibKey(libKey);
                          }
                        }}
                        onDragLeave={() => {
                          setDropLibKey((cur) => {
                            if (cur === libKey) {
                              dropLibKeyRef.current = null;
                              return null;
                            }
                            return cur;
                          });
                        }}
                        onDragEnd={() => clearLibDrag()}
                        onDropSeries={(fromKey) => {
                          reorderLibraryItems(
                            fromKey || dragLibKeyRef.current || '',
                            libKey,
                          );
                        }}
                        dragPayload={libKey}
                      />
                      </Box>
                    );
                  }
                  const e = item.entry;
                  const libKey = libraryItemKey(item);
                  return (
                    <Box
                      key={e.dir || e.videoRel}
                      data-lib-key={canLibDrag ? libKey : undefined}
                      data-ep-dir={seriesFocus ? e.dir : undefined}
                      sx={{ minWidth: 0 }}
                    >
                    <EntryCard
                      entry={e}
                      aspect={posterAspect(posterRatio)}
                      showEpisodeMove={!!seriesFocus}
                      draggable={
                        (!!seriesFocus && !e.legacy) || (canLibDrag && !e.legacy)
                      }
                      dragging={
                        seriesFocus
                          ? dragEpisodeDir === e.dir
                          : dragLibKey === libKey
                      }
                      dropTarget={
                        seriesFocus
                          ? !!dragEpisodeDir &&
                            dropEpisodeDir === e.dir &&
                            dragEpisodeDir !== e.dir
                          : !!dragLibKey &&
                            dropLibKey === libKey &&
                            dragLibKey !== libKey
                      }
                      onDragStart={(ev) => {
                        if (seriesFocus) {
                          dragEpisodeDirRef.current = e.dir;
                          setDragEpisodeDir(e.dir);
                          setDropEpisodeDir(null);
                          dropEpisodeDirRef.current = null;
                          setDragGhost({
                            kind: 'episode',
                            x: ev.clientX,
                            y: ev.clientY,
                            entry: e,
                            aspect: posterAspect(posterRatio),
                          });
                        } else {
                          dragLibKeyRef.current = libKey;
                          setDragLibKey(libKey);
                          setDropLibKey(null);
                          dropLibKeyRef.current = null;
                          setDragGhost({
                            kind: 'episode',
                            x: ev.clientX,
                            y: ev.clientY,
                            entry: e,
                            aspect: posterAspect(posterRatio),
                          });
                        }
                      }}
                      onDrag={(ev) => {
                        if (ev.clientX === 0 && ev.clientY === 0) return;
                        setDragGhost((g) =>
                          g && g.kind === 'episode'
                            ? { ...g, x: ev.clientX, y: ev.clientY }
                            : {
                                kind: 'episode',
                                x: ev.clientX,
                                y: ev.clientY,
                                entry: e,
                                aspect: posterAspect(posterRatio),
                              },
                        );
                      }}
                      onDragEnter={() => {
                        if (seriesFocus) {
                          if (
                            dragEpisodeDirRef.current &&
                            dragEpisodeDirRef.current !== e.dir
                          ) {
                            dropEpisodeDirRef.current = e.dir;
                            setDropEpisodeDir(e.dir);
                          }
                        } else if (
                          dragLibKeyRef.current &&
                          dragLibKeyRef.current !== libKey
                        ) {
                          dropLibKeyRef.current = libKey;
                          setDropLibKey(libKey);
                        }
                      }}
                      onDragLeave={() => {
                        if (seriesFocus) {
                          setDropEpisodeDir((cur) => {
                            if (cur === e.dir) {
                              dropEpisodeDirRef.current = null;
                              return null;
                            }
                            return cur;
                          });
                        } else {
                          setDropLibKey((cur) => {
                            if (cur === libKey) {
                              dropLibKeyRef.current = null;
                              return null;
                            }
                            return cur;
                          });
                        }
                      }}
                      onDragEnd={() => {
                        if (seriesFocus) {
                          dragEpisodeDirRef.current = null;
                          dropEpisodeDirRef.current = null;
                          setDragEpisodeDir(null);
                          setDropEpisodeDir(null);
                          setDragGhost(null);
                        } else {
                          clearLibDrag();
                        }
                      }}
                      onDropEpisode={(fromPayload) => {
                        if (seriesFocus) {
                          void reorderEpisodes(
                            fromPayload || dragEpisodeDirRef.current || '',
                            e.dir,
                          );
                          dragEpisodeDirRef.current = null;
                          dropEpisodeDirRef.current = null;
                          setDragEpisodeDir(null);
                          setDropEpisodeDir(null);
                          setDragGhost(null);
                        } else {
                          reorderLibraryItems(
                            fromPayload || dragLibKeyRef.current || '',
                            libKey,
                          );
                        }
                      }}
                      dragPayload={seriesFocus ? e.dir : libKey}
                      onOpen={() => void openEntry(e)}
                      onEnsureDuration={() => void ensureEntryDuration(e)}
                      onEdit={e.legacy ? undefined : () => setEditEntry(e)}
                      onDelete={() => setDeleteTarget({ kind: 'entry', entry: e })}
                      onToggleFavorite={
                        e.legacy ? undefined : () => void toggleFavorite(e)
                      }
                      onReveal={hasRevealHost() ? () => void onReveal(e) : undefined}
                      onShare={hasShareHost() ? () => void onShare(e) : undefined}
                      onMoveUp={
                        seriesFocus ? () => void moveEpisode(e, -1) : undefined
                      }
                      onMoveDown={
                        seriesFocus ? () => void moveEpisode(e, 1) : undefined
                      }
                    />
                    </Box>
                  );
                })}
              </Box>

              {!gridItems.length && (
                <Typography color="text.secondary" sx={{ mt: 4, textAlign: 'center' }}>
                  {seriesFocus
                    ? '该合集暂无剧集。'
                    : l1 === 'favorites'
                      ? '还没有收藏。在条目菜单中点「收藏」。'
                      : '暂无视频。点击右上角「添加视频」，或将文件放入应用 data 目录。'}
                </Typography>
              )}
            </Box>
          </Box>
        </Box>
      </Box>

      {dragGhost && (
        <Box
          sx={{
            position: 'fixed',
            left: dragGhost.x + 12,
            top: dragGhost.y + 12,
            zIndex: 2000,
            pointerEvents: 'none',
            filter: 'drop-shadow(0 4px 12px rgba(0,0,0,.35))',
          }}
        >
          {dragGhost.kind === 'l1' ? (
            <Box
              sx={{
                display: 'flex',
                alignItems: 'center',
                minWidth: 160,
                maxWidth: 220,
                px: 1,
                py: 0.75,
                borderRadius: 1,
                bgcolor: dragGhost.selected ? 'primary.main' : 'background.paper',
                color: dragGhost.selected ? 'primary.contrastText' : 'text.primary',
                border: 1,
                borderColor: 'divider',
              }}
            >
              <DragIndicatorIcon fontSize="small" sx={{ mr: 0.5, opacity: 0.55 }} />
              <Typography
                variant="body2"
                noWrap
                sx={{ flex: 1, fontWeight: dragGhost.selected ? 600 : 400 }}
              >
                {dragGhost.name}
              </Typography>
              <Typography variant="body2" sx={{ ml: 0.5, opacity: 0.85 }}>
                {dragGhost.count}
              </Typography>
            </Box>
          ) : (
            <Card variant="outlined" sx={{ width: 160, bgcolor: 'background.paper' }}>
              <Box sx={{ position: 'relative', aspectRatio: dragGhost.aspect }}>
                {(dragGhost.kind === 'episode'
                  ? dragGhost.entry.coverRel
                  : dragGhost.group.coverRel) ? (
                  <CardMedia
                    component="img"
                    image={dataUrl(
                      (dragGhost.kind === 'episode'
                        ? dragGhost.entry.coverRel
                        : dragGhost.group.coverRel)!,
                    )}
                    alt=""
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
                    }}
                  >
                    {dragGhost.kind === 'series' ? (
                      <FolderIcon color="action" />
                    ) : (
                      <MovieIcon color="action" />
                    )}
                  </Box>
                )}
              </Box>
              <CardContent sx={{ py: 0.75, px: 1, '&:last-child': { pb: 0.75 } }}>
                <Typography variant="caption" noWrap sx={{ display: 'block' }}>
                  {dragGhost.kind === 'episode'
                    ? dragGhost.entry.title
                    : dragGhost.group.name}
                </Typography>
              </CardContent>
            </Card>
          )}
        </Box>
      )}

      {snack && (
        <Alert
          severity="info"
          onClose={() => setSnack('')}
          sx={{ position: 'fixed', bottom: 16, left: '50%', transform: 'translateX(-50%)', zIndex: 1400 }}
        >
          {snack}
        </Alert>
      )}

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

      <Dialog
        open={!!renameL1}
        onClose={() => !renameBusy && setRenameL1(null)}
        fullWidth
        maxWidth="xs"
      >
        <DialogTitle>重命名分类</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="新名称"
            value={renameInput}
            error={!!renameError}
            helperText={renameError || ' '}
            disabled={renameBusy}
            onChange={(e) => {
              setRenameInput(e.target.value);
              if (renameError) setRenameError('');
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameL1(null)} disabled={renameBusy}>
            取消
          </Button>
          <Button
            variant="contained"
            onClick={() => void submitRenameL1()}
            disabled={renameBusy}
          >
            确定
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!renameSeries}
        onClose={() => !seriesBusy && setRenameSeries(null)}
        fullWidth
        maxWidth="xs"
      >
        <DialogTitle>重命名合集</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="新名称"
            value={renameInput}
            error={!!renameError}
            helperText={renameError || ' '}
            disabled={seriesBusy}
            onChange={(e) => {
              setRenameInput(e.target.value);
              if (renameError) setRenameError('');
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                void submitRenameSeries();
              }
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameSeries(null)} disabled={seriesBusy}>
            取消
          </Button>
          <Button
            variant="contained"
            onClick={() => void submitRenameSeries()}
            disabled={seriesBusy}
          >
            确定
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!dissolveSeries}
        onClose={() => !seriesBusy && setDissolveSeries(null)}
      >
        <DialogTitle>解散合集</DialogTitle>
        <DialogContent>
          <DialogContentText>
            确定解散合集「{dissolveSeries?.name}」？视频将保留在「
            {dissolveSeries?.l1}/{dissolveSeries?.l2}」下，不再成组。
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDissolveSeries(null)} disabled={seriesBusy}>
            取消
          </Button>
          <Button
            color="error"
            variant="contained"
            onClick={() => void submitDissolveSeries()}
            disabled={seriesBusy}
          >
            解散
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={!!deleteTarget}
        onClose={() => !deleteBusy && setDeleteTarget(null)}
      >
        <DialogTitle>确认删除</DialogTitle>
        <DialogContent>
          <DialogContentText>
            {deleteTarget?.kind === 'entry'
              ? `确定删除「${deleteTarget.entry.title}」？将移除条目目录下的视频与封面，不可恢复。`
              : `确定删除空分类「${deleteTarget?.name}」？`}
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDeleteTarget(null)} disabled={deleteBusy}>
            取消
          </Button>
          <Button
            color="error"
            variant="contained"
            onClick={() => void confirmDelete()}
            disabled={deleteBusy}
          >
            删除
          </Button>
        </DialogActions>
      </Dialog>

      <PrefsDialog
        open={prefsOpen}
        density={density}
        posterRatio={posterRatio}
        autoNext={autoNext}
        onClose={() => setPrefsOpen(false)}
        onDensity={(v) => {
          setDensity(v);
          saveDensity(v);
        }}
        onRatio={(v) => {
          setPosterRatio(v);
          savePosterRatio(v);
        }}
        onAutoNext={(v) => {
          setAutoNext(v);
          saveAutoNext(v);
        }}
      />

      <BatchImportDialog
        open={batchOpen}
        library={library}
        defaultL1={l1}
        defaultL2={l2}
        onClose={() => setBatchOpen(false)}
        onDone={() => {
          setBatchOpen(false);
          void refresh();
        }}
      />

      {l1 !== 'all' && l1 !== 'favorites' && (
        <L2EditDialog
          open={l2EditOpen}
          l1={l1}
          library={library}
          order={l2List}
          onClose={() => setL2EditOpen(false)}
          onReorder={(names) => {
            const next = { ...l2OrderMap, [l1]: names };
            setL2OrderMap(next);
            saveL2Order(next);
          }}
          onRenamed={() => void refresh()}
          onDeleted={(name) => {
            if (l2 === name) setL2('all');
            void refresh();
          }}
        />
      )}

      <VideoEntryDialog
        open={addOpen}
        mode="add"
        library={library}
        defaultL1={l1 === 'favorites' ? 'all' : l1}
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
              <Button
                startIcon={<ArrowBackIcon />}
                onClick={() => void closePlayer()}
                sx={{ mr: 1 }}
              >
                返回列表
              </Button>
              <Typography variant="subtitle1" noWrap sx={{ flex: 1 }}>
                {playing.title}
              </Typography>
            </Toolbar>
          </AppBar>
          <Box
            component="video"
            ref={webVideoRef}
            key={playing.videoRel}
            controls
            playsInline
            autoPlay
            src={dataUrl(playing.videoRel)}
            onLoadedMetadata={(ev) => {
              const v = ev.currentTarget;
              const start = playing.positionSec;
              if (start > 5) {
                try {
                  v.currentTime = start;
                } catch {
                  /* ignore */
                }
              }
            }}
            onEnded={() => {
              void (async () => {
                const e = playing;
                await saveWatchProgress(e, 0, true);
                if (autoNext) {
                  const nxt = nextEpisode(library, e);
                  if (nxt) {
                    setPlaying(null);
                    await openEntry(nxt);
                    return;
                  }
                }
                setPlaying(null);
              })();
            }}
            onError={() => {
              setPlayError('网页播放器无法解码此格式。');
              if (hasPlayVideoHost()) {
                void playOne(playing);
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

function L1NavItem({
  name,
  selected,
  count,
  empty,
  dragging,
  dropTarget,
  onSelect,
  onRename,
  onDelete,
  onDragStart,
  onDrag,
  onDragEnter,
  onDragLeave,
  onDragEnd,
  onDrop,
}: {
  name: string;
  selected: boolean;
  count: number;
  empty: boolean;
  dragging?: boolean;
  dropTarget?: boolean;
  onSelect: () => void;
  onRename: () => void;
  onDelete: () => void;
  onDragStart: (ev: ReactDragEvent) => void;
  onDrag: (ev: ReactDragEvent) => void;
  onDragEnter: () => void;
  onDragLeave: () => void;
  onDragEnd: () => void;
  onDrop: (from: string) => void;
}) {
  const [anchor, setAnchor] = useState<null | HTMLElement>(null);
  return (
    <ListItemButton
      selected={selected}
      onClick={onSelect}
      draggable
      onDragStart={(ev) => {
        // CEF/Chromium 对自定义 MIME 不稳定，统一用 text/plain
        ev.dataTransfer.setData('text/plain', name);
        ev.dataTransfer.effectAllowed = 'move';
        // 隐藏浏览器默认幽灵图，改用自定义悬浮提示
        const img = new Image();
        img.src =
          'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
        ev.dataTransfer.setDragImage(img, 0, 0);
        onDragStart(ev);
      }}
      onDrag={onDrag}
      onDragEnd={onDragEnd}
      onDragEnter={(ev) => {
        ev.preventDefault();
        onDragEnter();
      }}
      onDragLeave={onDragLeave}
      onDragOver={(ev) => {
        ev.preventDefault();
        ev.dataTransfer.dropEffect = 'move';
        onDragEnter();
      }}
      onDrop={(ev) => {
        ev.preventDefault();
        const from = ev.dataTransfer.getData('text/plain');
        onDrop(from);
      }}
      sx={{
        whiteSpace: 'nowrap',
        pr: 0.5,
        opacity: dragging ? 0.45 : 1,
        cursor: 'grab',
        borderTop: dropTarget ? '2px solid' : '2px solid transparent',
        borderColor: dropTarget ? 'primary.main' : 'transparent',
        bgcolor: dropTarget ? 'action.selected' : undefined,
      }}
    >
      <DragIndicatorIcon
        fontSize="small"
        sx={{ mr: 0.5, opacity: 0.55, flexShrink: 0 }}
      />
      <ListItemText
        primary={name}
        slotProps={{
          primary: {
            noWrap: true,
            sx: { overflow: 'hidden', textOverflow: 'ellipsis' },
          },
        }}
      />
      <Typography variant="body2" sx={{ flexShrink: 0, ml: 0.5, opacity: 0.85 }}>
        {count}
      </Typography>
      <IconButton
        size="small"
        aria-label="分类菜单"
        onClick={(ev) => {
          ev.stopPropagation();
          setAnchor(ev.currentTarget);
        }}
        sx={{ ml: 0.25, color: 'inherit', opacity: 0.85 }}
      >
        <MoreVertIcon fontSize="small" />
      </IconButton>
      <Menu
        anchorEl={anchor}
        open={!!anchor}
        onClose={() => setAnchor(null)}
        onClick={(ev) => ev.stopPropagation()}
      >
        <MenuItem
          onClick={() => {
            setAnchor(null);
            onRename();
          }}
        >
          重命名
        </MenuItem>
        <MenuItem
          disabled={!empty}
          onClick={() => {
            setAnchor(null);
            onDelete();
          }}
        >
          删除空分类
        </MenuItem>
      </Menu>
    </ListItemButton>
  );
}

function PrefsDialog({
  open,
  density,
  posterRatio,
  autoNext,
  onClose,
  onDensity,
  onRatio,
  onAutoNext,
}: {
  open: boolean;
  density: ListDensity;
  posterRatio: PosterRatio;
  autoNext: boolean;
  onClose: () => void;
  onDensity: (v: ListDensity) => void;
  onRatio: (v: PosterRatio) => void;
  onAutoNext: (v: boolean) => void;
}) {
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="xs">
      <DialogTitle>显示与播放</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 1 }}>
          <FormControl fullWidth size="small">
            <InputLabel>列表密度</InputLabel>
            <Select
              label="列表密度"
              value={density}
              onChange={(e) => onDensity(e.target.value as ListDensity)}
            >
              <MenuItem value="comfortable">舒适</MenuItem>
              <MenuItem value="compact">紧凑</MenuItem>
            </Select>
          </FormControl>
          <FormControl fullWidth size="small">
            <InputLabel>海报比例</InputLabel>
            <Select
              label="海报比例"
              value={posterRatio}
              onChange={(e) => onRatio(e.target.value as PosterRatio)}
            >
              <MenuItem value="16/10">横版 16:10</MenuItem>
              <MenuItem value="2/3">竖版 2:3</MenuItem>
              <MenuItem value="1/1">方图 1:1</MenuItem>
            </Select>
          </FormControl>
          <FormControlLabel
            control={
              <Checkbox
                checked={autoNext}
                onChange={(e) => onAutoNext(e.target.checked)}
              />
            }
            label="剧集播完自动下一集"
          />
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>关闭</Button>
      </DialogActions>
    </Dialog>
  );
}

function L2EditDialog({
  open,
  l1,
  library,
  order,
  onClose,
  onReorder,
  onRenamed,
  onDeleted,
}: {
  open: boolean;
  l1: string;
  library: Library;
  order: string[];
  onClose: () => void;
  onReorder: (names: string[]) => void;
  onRenamed: () => void;
  onDeleted: (name: string) => void;
}) {
  const [renameTarget, setRenameTarget] = useState<string | null>(null);
  const [renameInput, setRenameInput] = useState('');
  const [renameError, setRenameError] = useState('');
  const [busy, setBusy] = useState(false);
  const [dragName, setDragName] = useState<string | null>(null);

  useEffect(() => {
    if (!open) {
      setRenameTarget(null);
      setRenameError('');
      setBusy(false);
    }
  }, [open]);

  const submitRename = async () => {
    if (!renameTarget) return;
    const newName = normalizeCatName(renameInput);
    if (!newName) {
      setRenameError('请输入名称');
      return;
    }
    if (newName === renameTarget) {
      setRenameTarget(null);
      return;
    }
    if (isReservedName(newName)) {
      setRenameError('该名称已保留');
      return;
    }
    const existing = l2Names(library, l1);
    if (existing.includes(newName)) {
      setRenameError('二级分类已存在');
      return;
    }
    setBusy(true);
    setRenameError('');
    try {
      const all = await listDir('');
      const prefix = `${l1}/${renameTarget}`;
      const under = all.filter((f) => f === prefix || f.startsWith(prefix + '/'));
      under.sort((a, b) => a.length - b.length);
      for (const rel of under) {
        const dest = `${l1}/${newName}${rel.slice(prefix.length)}`;
        const blob = await getDataBlob(rel);
        if (blob) await putDataFile(dest, blob);
        else await putDataFile(dest, '');
      }
      under.sort((a, b) => b.length - a.length);
      for (const rel of under) {
        try {
          await deleteDataFile(rel);
        } catch {
          /* ignore */
        }
      }
      onReorder(order.map((n) => (n === renameTarget ? newName : n)));
      setRenameTarget(null);
      onRenamed();
    } catch (e) {
      setRenameError(e instanceof Error ? e.message : '重命名失败');
    } finally {
      setBusy(false);
    }
  };

  const deleteEmpty = async (name: string) => {
    if (!isL2Empty(library, l1, name)) return;
    setBusy(true);
    try {
      await deleteDataTree(`${l1}/${name}`);
      onReorder(order.filter((n) => n !== name));
      onDeleted(name);
    } catch (e) {
      setRenameError(e instanceof Error ? e.message : '删除失败');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onClose={() => !busy && onClose()} fullWidth maxWidth="sm">
      <DialogTitle>编辑二级分类 · {l1}</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>
          拖拽可调整顺序；可重命名或删除空分类。
        </Typography>
        <List dense>
          {order.map((name) => {
            const count = countEntriesInL2(library, l1, name);
            return (
              <ListItemButton
                key={name}
                draggable
                onDragStart={(ev) => {
                  ev.dataTransfer.setData('text/plain', name);
                  setDragName(name);
                }}
                onDragEnd={() => setDragName(null)}
                onDragOver={(ev) => ev.preventDefault()}
                onDrop={(ev) => {
                  ev.preventDefault();
                  const from = ev.dataTransfer.getData('text/plain') || dragName;
                  if (!from || from === name) return;
                  const next = [...order];
                  const i = next.indexOf(from);
                  const j = next.indexOf(name);
                  if (i < 0 || j < 0) return;
                  next.splice(i, 1);
                  next.splice(j, 0, from);
                  onReorder(next);
                  setDragName(null);
                }}
                sx={{ opacity: dragName === name ? 0.5 : 1, cursor: 'grab', borderRadius: 1 }}
              >
                <DragIndicatorIcon fontSize="small" sx={{ mr: 1, opacity: 0.5 }} />
                <ListItemText primary={name} secondary={`${count} 个视频`} />
                <Button
                  size="small"
                  disabled={busy}
                  onClick={(ev) => {
                    ev.stopPropagation();
                    setRenameTarget(name);
                    setRenameInput(name);
                    setRenameError('');
                  }}
                >
                  重命名
                </Button>
                <Button
                  size="small"
                  color="error"
                  disabled={busy || count > 0}
                  onClick={(ev) => {
                    ev.stopPropagation();
                    void deleteEmpty(name);
                  }}
                >
                  删除
                </Button>
              </ListItemButton>
            );
          })}
          {!order.length && (
            <Typography color="text.secondary" sx={{ py: 2, textAlign: 'center' }}>
              暂无二级分类
            </Typography>
          )}
        </List>
        {renameError && (
          <Typography color="error" variant="body2" sx={{ mt: 1 }}>
            {renameError}
          </Typography>
        )}
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={busy}>
          关闭
        </Button>
      </DialogActions>

      <Dialog
        open={!!renameTarget}
        onClose={() => !busy && setRenameTarget(null)}
        fullWidth
        maxWidth="xs"
      >
        <DialogTitle>重命名二级分类</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="新名称"
            value={renameInput}
            disabled={busy}
            onChange={(e) => setRenameInput(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRenameTarget(null)} disabled={busy}>
            取消
          </Button>
          <Button variant="contained" onClick={() => void submitRename()} disabled={busy}>
            确定
          </Button>
        </DialogActions>
      </Dialog>
    </Dialog>
  );
}

function BatchImportDialog({
  open,
  library,
  defaultL1,
  defaultL2,
  onClose,
  onDone,
}: {
  open: boolean;
  library: Library;
  defaultL1: string;
  defaultL2: string;
  onClose: () => void;
  onDone: () => void;
}) {
  const [l1, setL1] = useState('');
  const [l2, setL2] = useState('');
  const [collection, setCollection] = useState('');
  const [picks, setPicks] = useState<Array<PickedStagedFile | File>>([]);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState('');
  const [dupHint, setDupHint] = useState('');

  useEffect(() => {
    if (!open) return;
    setL1(defaultL1 && defaultL1 !== 'all' && defaultL1 !== 'favorites' ? defaultL1 : '');
    setL2(defaultL2 && defaultL2 !== 'all' ? defaultL2 : '');
    setCollection('');
    setPicks([]);
    setBusy(false);
    setProgress(0);
    setError('');
    setDupHint('');
  }, [open, defaultL1, defaultL2]);

  const onPick = async () => {
    setError('');
    try {
      const files = await pickFiles('video/*');
      setPicks(files);
      const titles = files.map((f) => {
        const n = isStagedPick(f) ? f.name : f.name;
        const i = n.lastIndexOf('.');
        return (i > 0 ? n.slice(0, i) : n).trim().toLowerCase();
      });
      const dups = titles.filter((t) =>
        findDuplicateTitles(library, t).length > 0,
      );
      setDupHint(
        dups.length
          ? `提示：有 ${dups.length} 个文件标题与库中已有条目相同`
          : '',
      );
    } catch (e) {
      if (e instanceof Error && e.message === 'cancelled') return;
      setError(e instanceof Error ? e.message : '选择失败');
    }
  };

  const submit = async () => {
    const l1n = normalizeCatName(l1);
    const l2n = normalizeCatName(l2);
    const coln = resolveCollectionName(library, l1n, l2n, collection);
    if (!l1n || isReservedName(l1n)) {
      setError('请填写有效的一级分类');
      return;
    }
    if (!l2n || isReservedName(l2n)) {
      setError('请填写有效的二级分类');
      return;
    }
    if (!picks.length) {
      setError('请选择视频文件');
      return;
    }
    setBusy(true);
    setError('');
    try {
      await putDataFile(`${l1n}/${KEEP_NAME}`, '');
      await putDataFile(`${l1n}/${l2n}/${KEEP_NAME}`, '');
      if (coln) await putDataFile(`${l1n}/${l2n}/${coln}/${KEEP_NAME}`, '');

      const orderBase = coln ? nextEpisodeOrderBase(library, l1n, l2n, coln) : 0;
      for (let i = 0; i < picks.length; i++) {
        const pick = picks[i];
        const fileName = isStagedPick(pick) ? pick.name : pick.name;
        const titleN = (() => {
          const j = fileName.lastIndexOf('.');
          return j > 0 ? fileName.slice(0, j) : fileName;
        })();
        const entryId = newEntryId();
        const dir = entryPath(l1n, l2n, coln || null, entryId);
        const videoName = `video.${videoExtFromName(fileName)}`;
        let blob: Blob;
        if (isStagedPick(pick)) {
          const b = await getDataBlob(pick.rel);
          if (!b) throw new Error(`读取失败：${fileName}`);
          blob = b;
        } else {
          blob = pick;
        }
        await putDataFileWithProgress(`${dir}/${videoName}`, blob, (r) => {
          setProgress((i + r) / picks.length);
        });
        let durationSec: number | undefined;
        try {
          const d = await probeDurationFromRel(
            isStagedPick(pick) ? pick.rel : `${dir}/${videoName}`,
          );
          if (d != null) durationSec = Math.round(d * 10) / 10;
        } catch {
          /* ignore */
        }
        const now = new Date().toISOString();
        const meta: EntryMeta = {
          title: titleN,
          video: videoName,
          playCount: 0,
          durationSec,
          episodeOrder: coln ? orderBase + i : undefined,
          createdAt: now,
          updatedAt: now,
        };
        await putDataJson(`${dir}/${META_NAME}`, meta);
      }
      onDone();
    } catch (e) {
      setError(e instanceof Error ? e.message : '导入失败');
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onClose={() => !busy && onClose()} fullWidth maxWidth="sm">
      <DialogTitle>批量导入</DialogTitle>
      <DialogContent>
        <Stack spacing={2} sx={{ mt: 1 }}>
          <TextField
            label="一级分类"
            value={l1}
            onChange={(e) => setL1(e.target.value)}
            disabled={busy}
            required
          />
          <TextField
            label="二级分类"
            value={l2}
            onChange={(e) => setL2(e.target.value)}
            disabled={busy}
            required
          />
          <TextField
            label="合集 / 剧集名（可选）"
            value={collection}
            onChange={(e) => setCollection(e.target.value)}
            disabled={busy}
            helperText="填写后这些文件会归入同一合集"
          />
          <Button variant="outlined" onClick={() => void onPick()} disabled={busy}>
            选择多个视频（已选 {picks.length}）
          </Button>
          {dupHint && <Alert severity="warning">{dupHint}</Alert>}
          {busy && <LinearProgress variant="determinate" value={Math.round(progress * 100)} />}
          {error && (
            <Typography color="error" variant="body2">
              {error}
            </Typography>
          )}
        </Stack>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={busy}>
          取消
        </Button>
        <Button variant="contained" onClick={() => void submit()} disabled={busy}>
          {busy ? '导入中…' : '开始导入'}
        </Button>
      </DialogActions>
    </Dialog>
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

function ResumeBar({ entry }: { entry: VideoEntry }) {
  if (!entry.positionSec || entry.positionSec < 5) return null;
  const ratio =
    entry.durationSec && entry.durationSec > 0
      ? Math.min(1, entry.positionSec / entry.durationSec)
      : 0.15;
  return (
    <Box
      sx={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 0,
        height: 3,
        bgcolor: 'rgba(255,255,255,0.25)',
      }}
    >
      <Box sx={{ width: `${ratio * 100}%`, height: '100%', bgcolor: 'error.main' }} />
    </Box>
  );
}

function EntryCard({
  entry,
  aspect,
  onOpen,
  onEdit,
  onDelete,
  onToggleFavorite,
  onReveal,
  onShare,
  onMoveUp,
  onMoveDown,
  onEnsureDuration,
  showEpisodeMove,
  draggable,
  dragging,
  dropTarget,
  onDragStart,
  onDrag,
  onDragEnter,
  onDragLeave,
  onDragEnd,
  onDropEpisode,
  dragPayload,
}: {
  entry: VideoEntry;
  aspect: string;
  onOpen: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
  onToggleFavorite?: () => void;
  onReveal?: () => void;
  onShare?: () => void;
  onMoveUp?: () => void;
  onMoveDown?: () => void;
  onEnsureDuration?: () => void;
  showEpisodeMove?: boolean;
  draggable?: boolean;
  dragging?: boolean;
  dropTarget?: boolean;
  onDragStart?: (ev: ReactDragEvent) => void;
  onDrag?: (ev: ReactDragEvent) => void;
  onDragEnter?: () => void;
  onDragLeave?: () => void;
  onDragEnd?: () => void;
  onDropEpisode?: (fromDir: string) => void;
  dragPayload?: string;
}) {
  const cover = entry.coverRel ? dataUrl(entry.coverRel) : null;
  const [anchor, setAnchor] = useState<null | HTMLElement>(null);

  useEffect(() => {
    onEnsureDuration?.();
  }, [entry.dir, entry.videoRel, entry.durationSec, onEnsureDuration]);

  return (
    <Card
      variant="outlined"
      sx={{
        position: 'relative',
        opacity: dragging ? 0.5 : 1,
        outline: dropTarget ? '2px solid' : 'none',
        outlineColor: dropTarget ? 'primary.main' : undefined,
        bgcolor: dropTarget ? 'action.hover' : undefined,
      }}
      onDragEnter={(ev) => {
        if (!draggable) return;
        ev.preventDefault();
        onDragEnter?.();
      }}
      onDragLeave={() => {
        if (!draggable) return;
        onDragLeave?.();
      }}
      onDragOver={(ev) => {
        if (!draggable) return;
        ev.preventDefault();
        ev.dataTransfer.dropEffect = 'move';
        onDragEnter?.();
      }}
      onDrop={(ev) => {
        if (!draggable) return;
        ev.preventDefault();
        const from = ev.dataTransfer.getData('text/plain');
        onDropEpisode?.(from);
      }}
    >
      {draggable && (
        <Box
          draggable
          onDragStart={(ev) => {
            ev.stopPropagation();
            ev.dataTransfer.setData('text/plain', dragPayload || entry.dir);
            ev.dataTransfer.effectAllowed = 'move';
            const img = new Image();
            img.src =
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
            ev.dataTransfer.setDragImage(img, 0, 0);
            onDragStart?.(ev);
          }}
          onDrag={(ev) => onDrag?.(ev)}
          onDragEnd={() => onDragEnd?.()}
          onClick={(ev) => ev.stopPropagation()}
          sx={{
            position: 'absolute',
            top: 4,
            left: 4,
            zIndex: 2,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: 32,
            height: 32,
            borderRadius: 1,
            bgcolor: 'rgba(0,0,0,0.55)',
            color: 'common.white',
            cursor: 'grab',
            '&:active': { cursor: 'grabbing' },
          }}
          title="拖拽排序"
        >
          <DragIndicatorIcon fontSize="small" />
        </Box>
      )}
      <IconButton
        size="small"
        aria-label="更多"
        onClick={(ev) => {
          ev.stopPropagation();
          setAnchor(ev.currentTarget);
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
        <MoreVertIcon fontSize="small" />
      </IconButton>
      <Menu anchorEl={anchor} open={!!anchor} onClose={() => setAnchor(null)}>
        {onEdit && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onEdit();
            }}
          >
            <EditIcon fontSize="small" sx={{ mr: 1 }} /> 编辑
          </MenuItem>
        )}
        {onToggleFavorite && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onToggleFavorite();
            }}
          >
            {entry.favorite ? (
              <FavoriteIcon fontSize="small" sx={{ mr: 1 }} color="error" />
            ) : (
              <FavoriteBorderIcon fontSize="small" sx={{ mr: 1 }} />
            )}
            {entry.favorite ? '取消收藏' : '收藏'}
          </MenuItem>
        )}
        {onReveal && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onReveal();
            }}
          >
            <FolderOpenIcon fontSize="small" sx={{ mr: 1 }} /> 在文件管理中打开
          </MenuItem>
        )}
        {onShare && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onShare();
            }}
          >
            <ShareIcon fontSize="small" sx={{ mr: 1 }} /> 系统分享
          </MenuItem>
        )}
        {showEpisodeMove && onMoveUp && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onMoveUp();
            }}
          >
            合集内上移
          </MenuItem>
        )}
        {showEpisodeMove && onMoveDown && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onMoveDown();
            }}
          >
            合集内下移
          </MenuItem>
        )}
        {onDelete && (
          <MenuItem
            onClick={() => {
              setAnchor(null);
              onDelete();
            }}
          >
            <DeleteIcon fontSize="small" sx={{ mr: 1 }} color="error" /> 删除
          </MenuItem>
        )}
      </Menu>
      <CardActionArea onClick={onOpen}>
        <Box sx={{ position: 'relative', aspectRatio: aspect }}>
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
          <ResumeBar entry={entry} />
          {entry.favorite && (
            <FavoriteIcon
              fontSize="small"
              sx={{
                position: 'absolute',
                top: 6,
                left: draggable ? 40 : 6,
                color: 'error.light',
                filter: 'drop-shadow(0 1px 2px rgba(0,0,0,.6))',
              }}
            />
          )}
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
            {entry.positionSec > 5 ? ` · 续播 ${formatDuration(entry.positionSec)}` : ''}
            {entry.createdAt ? ` · ${entry.createdAt.slice(0, 10)}` : ''}
          </Typography>
        </CardContent>
      </CardActionArea>
    </Card>
  );
}

function SeriesCard({
  group,
  aspect,
  onOpen,
  onRename,
  onDissolve,
  draggable,
  dragging,
  dropTarget,
  onDragStart,
  onDrag,
  onDragEnter,
  onDragLeave,
  onDragEnd,
  onDropSeries,
  dragPayload,
}: {
  group: SeriesGroup;
  aspect: string;
  onOpen: () => void;
  onRename: () => void;
  onDissolve: () => void;
  draggable?: boolean;
  dragging?: boolean;
  dropTarget?: boolean;
  onDragStart?: (ev: ReactDragEvent) => void;
  onDrag?: (ev: ReactDragEvent) => void;
  onDragEnter?: () => void;
  onDragLeave?: () => void;
  onDragEnd?: () => void;
  onDropSeries?: (fromKey: string) => void;
  dragPayload?: string;
}) {
  const cover = group.coverRel ? dataUrl(group.coverRel) : null;
  const n = group.episodes.length;
  const [anchor, setAnchor] = useState<null | HTMLElement>(null);
  return (
    <Card
      variant="outlined"
      sx={{
        position: 'relative',
        opacity: dragging ? 0.5 : 1,
        outline: dropTarget ? '2px solid' : 'none',
        outlineColor: dropTarget ? 'primary.main' : undefined,
        bgcolor: dropTarget ? 'action.hover' : undefined,
      }}
      onDragEnter={(ev) => {
        if (!draggable) return;
        ev.preventDefault();
        onDragEnter?.();
      }}
      onDragLeave={() => {
        if (!draggable) return;
        onDragLeave?.();
      }}
      onDragOver={(ev) => {
        if (!draggable) return;
        ev.preventDefault();
        ev.dataTransfer.dropEffect = 'move';
        onDragEnter?.();
      }}
      onDrop={(ev) => {
        if (!draggable) return;
        ev.preventDefault();
        const from = ev.dataTransfer.getData('text/plain');
        onDropSeries?.(from);
      }}
    >
      {draggable && (
        <Box
          draggable
          onDragStart={(ev) => {
            ev.stopPropagation();
            ev.dataTransfer.setData('text/plain', dragPayload || group.key);
            ev.dataTransfer.effectAllowed = 'move';
            const img = new Image();
            img.src =
              'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
            ev.dataTransfer.setDragImage(img, 0, 0);
            onDragStart?.(ev);
          }}
          onDrag={(ev) => onDrag?.(ev)}
          onDragEnd={() => onDragEnd?.()}
          onClick={(ev) => ev.stopPropagation()}
          sx={{
            position: 'absolute',
            top: 4,
            left: 4,
            zIndex: 2,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            width: 32,
            height: 32,
            borderRadius: 1,
            bgcolor: 'rgba(0,0,0,0.55)',
            color: 'common.white',
            cursor: 'grab',
            '&:active': { cursor: 'grabbing' },
          }}
          title="拖拽排序"
        >
          <DragIndicatorIcon fontSize="small" />
        </Box>
      )}
      <IconButton
        size="small"
        aria-label="合集菜单"
        onClick={(ev) => {
          ev.stopPropagation();
          setAnchor(ev.currentTarget);
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
        <MoreVertIcon fontSize="small" />
      </IconButton>
      <Menu anchorEl={anchor} open={!!anchor} onClose={() => setAnchor(null)}>
        <MenuItem
          onClick={() => {
            setAnchor(null);
            onRename();
          }}
        >
          <EditIcon fontSize="small" sx={{ mr: 1 }} /> 重命名合集
        </MenuItem>
        <MenuItem
          onClick={() => {
            setAnchor(null);
            onDissolve();
          }}
        >
          <DeleteIcon fontSize="small" sx={{ mr: 1 }} color="error" /> 解散合集
        </MenuItem>
      </Menu>
      <CardActionArea onClick={onOpen}>
        <Box sx={{ position: 'relative', aspectRatio: aspect }}>
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
