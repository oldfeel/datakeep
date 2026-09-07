import { getDataJson, listDir } from './datakeep';
import type { OutputData } from '@editorjs/editorjs';

const VIDEO_EXT: Record<string, 1> = {
  mp4: 1,
  webm: 1,
  mkv: 1,
  mov: 1,
  m4v: 1,
  avi: 1,
  ogv: 1,
  mpeg: 1,
  mpg: 1,
};

export const KEEP_NAME = '.keep';
export const META_NAME = 'meta.json';

export const RESERVED_NAMES: Record<string, 1> = {
  all: 1,
  root: 1,
  全部: 1,
  未分类: 1,
};

export type EntryMeta = {
  title: string;
  description?: OutputData | null;
  cover?: string;
  video: string;
  /** 播放次数 */
  playCount?: number;
  /** 视频时长（秒） */
  durationSec?: number;
  createdAt: string;
  updatedAt: string;
};

/** 视频条目（含 meta.json 的目录） */
export type VideoEntry = {
  id: string;
  /** 相对 data/ 的条目目录，如 电影/动作/合集/uuid */
  dir: string;
  l1: string;
  l2: string;
  /** 无合集时为 null */
  collection: string | null;
  title: string;
  descriptionText: string;
  coverRel: string | null;
  videoRel: string;
  legacy: boolean;
  playCount: number;
  /** 时长秒；未知为 null */
  durationSec: number | null;
  /** ISO8601，上传/创建时间；legacy 为空串 */
  createdAt: string;
};

export type Library = {
  /** 一级 → 二级名列表 */
  l1ToL2: Record<string, string[]>;
  /** 一级/二级 → 合集名列表 */
  collections: Record<string, string[]>;
  entries: VideoEntry[];
};

export function emptyLibrary(): Library {
  return { l1ToL2: {}, collections: {}, entries: [] };
}

export function isVideoPath(rel: string): boolean {
  const name = rel.split('/').pop() || '';
  const i = name.lastIndexOf('.');
  if (i < 0) return false;
  return !!VIDEO_EXT[name.slice(i + 1).toLowerCase()];
}

export function baseName(rel: string): string {
  const n = rel.split('/').pop() || rel;
  const i = n.lastIndexOf('.');
  return i > 0 ? n.slice(0, i) : n;
}

export function normalizeCatName(raw: string): string {
  return String(raw || '')
    .trim()
    .replace(/[\\/]/g, '')
    .replace(/^\.+/, '');
}

export function isReservedName(name: string): boolean {
  return !!(RESERVED_NAMES[name] || RESERVED_NAMES[name.toLowerCase()]);
}

/** 从 Editor.js OutputData 抽纯文本供搜索 */
export function descriptionToPlainText(desc: OutputData | null | undefined): string {
  if (!desc || !Array.isArray(desc.blocks)) return '';
  const parts: string[] = [];
  for (const block of desc.blocks) {
    const data = block.data as Record<string, unknown> | undefined;
    if (!data) continue;
    if (typeof data.text === 'string') {
      parts.push(data.text.replace(/<[^>]+>/g, ' '));
    }
    if (Array.isArray(data.items)) {
      for (const item of data.items) {
        if (typeof item === 'string') parts.push(item.replace(/<[^>]+>/g, ' '));
        else if (item && typeof item === 'object' && typeof (item as { content?: string }).content === 'string') {
          parts.push(String((item as { content: string }).content).replace(/<[^>]+>/g, ' '));
        }
      }
    }
  }
  return parts.join(' ').replace(/\s+/g, ' ').trim();
}

function l2Key(l1: string, l2: string): string {
  return `${l1}/${l2}`;
}

function addUnique(map: Record<string, string[]>, key: string, name: string) {
  if (!isPublicCatName(key) || !isPublicCatName(name)) return;
  if (!map[key]) map[key] = [];
  if (!map[key].includes(name)) map[key].push(name);
}

/** 宿主暂存、隐藏目录等，不进入分类/列表 */
export function isInternalDataPath(rel: string): boolean {
  const n = String(rel || '').replace(/\\/g, '/').replace(/^\/+/, '');
  if (!n) return false;
  if (n === '.staging' || n.startsWith('.staging/')) return true;
  const top = n.split('/').filter(Boolean)[0];
  return !!top && top.startsWith('.');
}

function isPublicCatName(name: string): boolean {
  const n = String(name || '').trim();
  if (!n || n === KEEP_NAME) return false;
  if (n.startsWith('.')) return false;
  return true;
}

export async function scanLibrary(): Promise<Library> {
  const files = await listDir('');
  const l1ToL2: Record<string, string[]> = {};
  const collections: Record<string, string[]> = {};
  const entries: VideoEntry[] = [];
  const entryDirs = new Set<string>();

  // 发现分类：.keep 与路径前缀
  for (const rel of files) {
    if (!rel || rel.includes('..') || isInternalDataPath(rel)) continue;
    const parts = rel.split('/').filter(Boolean);
    if (parts.length >= 1 && isPublicCatName(parts[0])) {
      if (!l1ToL2[parts[0]]) l1ToL2[parts[0]] = [];
    }
    if (parts.length >= 2 && isPublicCatName(parts[0]) && isPublicCatName(parts[1])) {
      addUnique(l1ToL2, parts[0], parts[1]);
    }
  }

  // 正式条目：*/meta.json
  const metaPaths = files.filter(
    (f) => !isInternalDataPath(f) && (f.endsWith('/' + META_NAME) || f === META_NAME),
  );
  for (const metaPath of metaPaths) {
    const parts = metaPath.split('/').filter(Boolean);
    // 需要至少 L1/L2/entryId/meta.json
    if (parts.length < 4) continue;
    const metaName = parts[parts.length - 1];
    if (metaName !== META_NAME) continue;

    let l1: string;
    let l2: string;
    let collection: string | null;
    let entryId: string;
    if (parts.length === 4) {
      // L1/L2/entryId/meta.json
      [l1, l2, entryId] = parts;
      collection = null;
    } else if (parts.length === 5) {
      // L1/L2/collection/entryId/meta.json
      [l1, l2, collection, entryId] = parts;
    } else {
      // 更深：取最后为 entry，倒数第二为合集，前两为 L1/L2
      l1 = parts[0];
      l2 = parts[1];
      entryId = parts[parts.length - 2];
      collection = parts.slice(2, -2).join('/') || null;
    }

    const dir = parts.slice(0, -1).join('/');
    if (isInternalDataPath(dir) || !isPublicCatName(l1) || !isPublicCatName(l2)) continue;
    entryDirs.add(dir);
    addUnique(l1ToL2, l1, l2);
    if (collection && isPublicCatName(collection.split('/')[0])) {
      addUnique(collections, l2Key(l1, l2), collection.split('/')[0]);
    }

    try {
      const meta = await getDataJson<EntryMeta>(metaPath);
      if (!meta || !meta.video) continue;
      const title = (meta.title || entryId).trim() || entryId;
      const descriptionText = descriptionToPlainText(meta.description);
      const coverRel = meta.cover ? `${dir}/${meta.cover}` : null;
      const videoRel = `${dir}/${meta.video}`;
      entries.push({
        id: entryId,
        dir,
        l1,
        l2,
        collection: collection ? collection.split('/')[0] : null,
        title,
        descriptionText,
        coverRel,
        videoRel,
        legacy: false,
        playCount: typeof meta.playCount === 'number' ? meta.playCount : 0,
        durationSec:
          typeof meta.durationSec === 'number' &&
          Number.isFinite(meta.durationSec) &&
          meta.durationSec > 0
            ? meta.durationSec
            : null,
        createdAt: meta.createdAt || '',
      });
    } catch (e) {
      console.error('读取 meta 失败', metaPath, e);
    }
  }

  // 合集目录：L1/L2/name/.keep 或子路径，且 name 不是已登记 entry
  for (const rel of files) {
    if (isInternalDataPath(rel)) continue;
    const parts = rel.split('/').filter(Boolean);
    if (parts.length < 3) continue;
    const [l1, l2, third] = parts;
    if (!isPublicCatName(l1) || !isPublicCatName(l2) || !isPublicCatName(third)) continue;
    const maybeEntry = `${l1}/${l2}/${third}`;
    if (entryDirs.has(maybeEntry)) continue;
    // 若 third 下有 meta.json 则已是 entry；有更深路径则可能是合集
    const hasDeeper = files.some(
      (f) => f.startsWith(`${l1}/${l2}/${third}/`) && f !== `${l1}/${l2}/${third}/${KEEP_NAME}`,
    );
    const isKeep = rel === `${l1}/${l2}/${third}/${KEEP_NAME}`;
    if (hasDeeper || isKeep) {
      // 若 third 本身是 entry（有 meta）已跳过；否则记为合集
      if (!files.includes(`${l1}/${l2}/${third}/${META_NAME}`)) {
        addUnique(l1ToL2, l1, l2);
        addUnique(collections, l2Key(l1, l2), third);
      }
    }
  }

  // 旧式裸视频（不在任何 entry 目录内）
  for (const rel of files) {
    if (isInternalDataPath(rel)) continue;
    if (!isVideoPath(rel)) continue;
    if (/\.db$/i.test(rel)) continue;
    const inEntry = [...entryDirs].some((d) => rel === d || rel.startsWith(d + '/'));
    if (inEntry) continue;
    const parts = rel.split('/').filter(Boolean);
    if (parts.length === 1) {
      // data 根下：归入虚拟「未分类」
      entries.push({
        id: rel,
        dir: '',
        l1: '',
        l2: '',
        collection: null,
        title: baseName(rel),
        descriptionText: '',
        coverRel: null,
        videoRel: rel,
        legacy: true,
        playCount: 0,
        durationSec: null,
        createdAt: '',
      });
      continue;
    }
    if (parts.length >= 2) {
      const l1 = parts[0];
      const l2 = parts.length >= 3 ? parts[1] : '';
      addUnique(l1ToL2, l1, l2 || '未分类');
      entries.push({
        id: rel,
        dir: parts.slice(0, -1).join('/'),
        l1,
        l2: l2 || '未分类',
        collection: parts.length >= 4 ? parts[2] : null,
        title: baseName(rel),
        descriptionText: '',
        coverRel: null,
        videoRel: rel,
        legacy: true,
        playCount: 0,
        durationSec: null,
        createdAt: '',
      });
    }
  }

  for (const k of Object.keys(l1ToL2)) {
    l1ToL2[k].sort((a, b) => a.localeCompare(b, 'zh'));
  }
  for (const k of Object.keys(collections)) {
    collections[k].sort((a, b) => a.localeCompare(b, 'zh'));
  }
  entries.sort((a, b) => b.createdAt.localeCompare(a.createdAt) || a.title.localeCompare(b.title, 'zh'));

  return { l1ToL2, collections, entries };
}

export type EntrySort =
  | 'createdAt_desc'
  | 'createdAt_asc'
  | 'playCount_desc'
  | 'playCount_asc';

export function sortEntries(entries: VideoEntry[], sort: EntrySort): VideoEntry[] {
  const list = [...entries];
  const byPlay = sort.startsWith('playCount');
  const asc = sort.endsWith('_asc');
  const dir = asc ? 1 : -1;

  list.sort((a, b) => {
    if (byPlay) {
      const d = (a.playCount - b.playCount) * dir;
      if (d !== 0) return d;
    } else {
      const d = a.createdAt.localeCompare(b.createdAt) * dir;
      if (d !== 0) return d;
    }
    return a.title.localeCompare(b.title, 'zh');
  });
  return list;
}

/** 列表项：单集视频，或折叠后的剧集合集 */
export type SeriesGroup = {
  kind: 'series';
  key: string;
  l1: string;
  l2: string;
  name: string;
  episodes: VideoEntry[];
  coverRel: string | null;
  playCount: number;
  /** 代表时长（取分集中有值的最大值） */
  durationSec: number | null;
  createdAt: string;
};

export type LibraryItem = { kind: 'video'; entry: VideoEntry } | SeriesGroup;

function seriesKey(l1: string, l2: string, name: string): string {
  return `${l1}/${l2}/${name}`;
}

/** 将同合集多集收成一张卡；无合集的仍为单视频卡 */
export function collapseToLibraryItems(
  entries: VideoEntry[],
  sort: EntrySort,
): LibraryItem[] {
  const singles: VideoEntry[] = [];
  const groups = new Map<string, VideoEntry[]>();

  for (const e of entries) {
    if (!e.collection) {
      singles.push(e);
      continue;
    }
    const key = seriesKey(e.l1, e.l2, e.collection);
    const arr = groups.get(key);
    if (arr) arr.push(e);
    else groups.set(key, [e]);
  }

  const items: LibraryItem[] = [];
  for (const e of singles) {
    items.push({ kind: 'video', entry: e });
  }
  for (const [key, eps] of groups) {
    const sorted = sortEntries(eps, sort);
    const head = sorted[0];
    const coverRel = sorted.find((x) => x.coverRel)?.coverRel ?? null;
    const createdAt =
      [...sorted.map((x) => x.createdAt).filter(Boolean)].sort().reverse()[0] || '';
    items.push({
      kind: 'series',
      key,
      l1: head.l1,
      l2: head.l2,
      name: head.collection!,
      episodes: sorted,
      coverRel,
      playCount: sorted.reduce((s, x) => s + x.playCount, 0),
      durationSec: sorted.reduce<number | null>((max, x) => {
        if (x.durationSec == null) return max;
        if (max == null) return x.durationSec;
        return Math.max(max, x.durationSec);
      }, null),
      createdAt,
    });
  }

  const byPlay = sort.startsWith('playCount');
  const asc = sort.endsWith('_asc');
  const dir = asc ? 1 : -1;
  items.sort((a, b) => {
    const playA = a.kind === 'series' ? a.playCount : a.entry.playCount;
    const playB = b.kind === 'series' ? b.playCount : b.entry.playCount;
    const createdA = a.kind === 'series' ? a.createdAt : a.entry.createdAt;
    const createdB = b.kind === 'series' ? b.createdAt : b.entry.createdAt;
    const titleA = a.kind === 'series' ? a.name : a.entry.title;
    const titleB = b.kind === 'series' ? b.name : b.entry.title;
    if (byPlay) {
      const d = (playA - playB) * dir;
      if (d !== 0) return d;
    } else {
      const d = createdA.localeCompare(createdB) * dir;
      if (d !== 0) return d;
    }
    return titleA.localeCompare(titleB, 'zh');
  });
  return items;
}

export function l1Names(library: Library): string[] {
  return Object.keys(library.l1ToL2)
    .filter(isPublicCatName)
    .sort((a, b) => a.localeCompare(b, 'zh'));
}

export function l2Names(library: Library, l1: string): string[] {
  if (l1 === 'all' || !l1) {
    const set = new Set<string>();
    for (const arr of Object.values(library.l1ToL2)) {
      for (const n of arr) set.add(n);
    }
    return [...set].sort((a, b) => a.localeCompare(b, 'zh'));
  }
  return library.l1ToL2[l1] || [];
}

export function collectionNamesFor(library: Library, l1: string, l2: string): string[] {
  if (!l1 || l1 === 'all' || !l2 || l2 === 'all') return [];
  return library.collections[l2Key(l1, l2)] || [];
}

export function countEntriesInL1(library: Library, l1: string): number {
  if (l1 === 'all') return library.entries.length;
  return library.entries.filter((e) => e.l1 === l1 || (l1 === 'root' && !e.l1)).length;
}

export function filterEntries(
  library: Library,
  opts: {
    l1: string;
    l2: string;
    collection: string | null;
    query: string;
  },
): VideoEntry[] {
  const q = opts.query.trim().toLowerCase();
  return library.entries.filter((e) => {
    if (opts.l1 !== 'all') {
      if (opts.l1 === 'root') {
        if (e.l1) return false;
      } else if (e.l1 !== opts.l1) return false;
    }
    if (opts.l2 !== 'all' && e.l2 !== opts.l2) return false;
    if (opts.collection != null) {
      if (opts.collection === '') {
        if (e.collection) return false;
      } else if (e.collection !== opts.collection) return false;
    }
    if (!q) return true;
    return (
      e.title.toLowerCase().includes(q) || e.descriptionText.toLowerCase().includes(q)
    );
  });
}

export function newEntryId(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return `e-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export function videoExtFromName(name: string): string {
  const i = name.lastIndexOf('.');
  if (i < 0) return 'mp4';
  const ext = name.slice(i + 1).toLowerCase().replace(/[^a-z0-9]/g, '');
  return ext || 'mp4';
}

export function entryPath(l1: string, l2: string, collection: string | null, entryId: string): string {
  const parts = [l1, l2];
  if (collection) parts.push(collection);
  parts.push(entryId);
  return parts.join('/');
}
