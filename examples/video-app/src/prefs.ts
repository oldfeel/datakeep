/** 列表展示偏好（localStorage） */

export type ListDensity = 'comfortable' | 'compact';
export type PosterRatio = '16/10' | '2/3' | '1/1';

const DENSITY_KEY = 'video-app.density';
const RATIO_KEY = 'video-app.posterRatio';
const AUTO_NEXT_KEY = 'video-app.autoNext';
const L1_ORDER_KEY = 'video-app.l1Order';
const L2_ORDER_KEY = 'video-app.l2Order';

export function loadDensity(): ListDensity {
  const v = localStorage.getItem(DENSITY_KEY);
  return v === 'compact' ? 'compact' : 'comfortable';
}

export function saveDensity(v: ListDensity): void {
  localStorage.setItem(DENSITY_KEY, v);
}

export function loadPosterRatio(): PosterRatio {
  const v = localStorage.getItem(RATIO_KEY);
  if (v === '2/3' || v === '1/1' || v === '16/10') return v;
  return '16/10';
}

export function savePosterRatio(v: PosterRatio): void {
  localStorage.setItem(RATIO_KEY, v);
}

export function loadAutoNext(): boolean {
  const v = localStorage.getItem(AUTO_NEXT_KEY);
  return v !== '0';
}

export function saveAutoNext(v: boolean): void {
  localStorage.setItem(AUTO_NEXT_KEY, v ? '1' : '0');
}

export function loadL1Order(): string[] {
  try {
    const raw = localStorage.getItem(L1_ORDER_KEY);
    if (!raw) return [];
    const j = JSON.parse(raw);
    return Array.isArray(j) ? j.map(String) : [];
  } catch {
    return [];
  }
}

export function saveL1Order(names: string[]): void {
  localStorage.setItem(L1_ORDER_KEY, JSON.stringify(names));
}

/** l1 → l2 名列表顺序 */
export function loadL2Order(): Record<string, string[]> {
  try {
    const raw = localStorage.getItem(L2_ORDER_KEY);
    if (!raw) return {};
    const j = JSON.parse(raw) as Record<string, unknown>;
    const out: Record<string, string[]> = {};
    for (const [k, v] of Object.entries(j)) {
      if (Array.isArray(v)) out[k] = v.map(String);
    }
    return out;
  } catch {
    return {};
  }
}

export function saveL2Order(map: Record<string, string[]>): void {
  localStorage.setItem(L2_ORDER_KEY, JSON.stringify(map));
}

const SERIES_ORDER_KEY = 'video-app.seriesOrder';
const LIBRARY_ORDER_KEY = 'video-app.libraryOrder';

/** scope → 库列表项 key 顺序（视频 + 合集混合） */
export function loadLibraryOrder(): Record<string, string[]> {
  try {
    const raw =
      localStorage.getItem(LIBRARY_ORDER_KEY) ||
      localStorage.getItem(SERIES_ORDER_KEY);
    if (!raw) return {};
    const j = JSON.parse(raw) as Record<string, unknown>;
    const out: Record<string, string[]> = {};
    for (const [k, v] of Object.entries(j)) {
      if (Array.isArray(v)) out[k] = v.map(String);
    }
    return out;
  } catch {
    return {};
  }
}

export function saveLibraryOrder(map: Record<string, string[]>): void {
  localStorage.setItem(LIBRARY_ORDER_KEY, JSON.stringify(map));
}

/** @deprecated 使用 loadLibraryOrder */
export function loadSeriesOrder(): Record<string, string[]> {
  return loadLibraryOrder();
}

/** @deprecated 使用 saveLibraryOrder */
export function saveSeriesOrder(map: Record<string, string[]>): void {
  saveLibraryOrder(map);
}

/** 把 known 按 order 排，未知追加到末尾 */
export function applyNameOrder(known: string[], order: string[]): string[] {
  const set = new Set(known);
  const out: string[] = [];
  for (const n of order) {
    if (set.has(n)) {
      out.push(n);
      set.delete(n);
    }
  }
  const rest = [...set].sort((a, b) => a.localeCompare(b, 'zh'));
  return [...out, ...rest];
}

export function densityMinWidth(d: ListDensity): string {
  return d === 'compact' ? '7.5rem' : '10rem';
}

export function posterAspect(r: PosterRatio): string {
  if (r === '2/3') return '2 / 3';
  if (r === '1/1') return '1 / 1';
  return '16 / 10';
}
