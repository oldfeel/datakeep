/** 列表展示偏好（localStorage） */

export type ListDensity = 'comfortable' | 'compact';
export type PosterRatio = '16/10' | '2/3' | '1/1';

const DENSITY_KEY = 'video-app.density';
const RATIO_KEY = 'video-app.posterRatio';
const AUTO_NEXT_KEY = 'video-app.autoNext';

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

export function densityMinWidth(d: ListDensity): string {
  return d === 'compact' ? '7.5rem' : '10rem';
}

export function posterAspect(r: PosterRatio): string {
  if (r === '2/3') return '2 / 3';
  if (r === '1/1') return '1 / 1';
  return '16 / 10';
}
