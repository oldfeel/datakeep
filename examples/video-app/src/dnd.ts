import { useEffect, useRef } from 'react';

export type DropPlace = 'before' | 'after' | 'swap';
export type DropLayout = 'y' | 'x' | 'xy';

/** y 上下插入 / x 左右插入 / xy 四边；中部均为对调 */
export function dropPlaceFromRect(
  rect: DOMRect,
  clientX: number,
  clientY: number,
  layout: DropLayout = 'y',
): DropPlace {
  const band = 0.28;
  if (layout === 'y') {
    const r = (clientY - rect.top) / Math.max(rect.height, 1);
    if (r < band) return 'before';
    if (r > 1 - band) return 'after';
    return 'swap';
  }
  if (layout === 'x') {
    const r = (clientX - rect.left) / Math.max(rect.width, 1);
    if (r < band) return 'before';
    if (r > 1 - band) return 'after';
    return 'swap';
  }
  const rx = (clientX - rect.left) / Math.max(rect.width, 1);
  const ry = (clientY - rect.top) / Math.max(rect.height, 1);
  const onEdge = rx < band || rx > 1 - band || ry < band || ry > 1 - band;
  if (!onEdge) return 'swap';
  if (ry < band || (rx < band && ry <= 0.5)) return 'before';
  if (ry > 1 - band || (rx > 1 - band && ry >= 0.5)) return 'after';
  return rx + ry < 1 ? 'before' : 'after';
}

export function applyDropAt<T>(
  list: T[],
  fromIdx: number,
  toIdx: number,
  place: DropPlace,
): T[] {
  if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return list;
  if (place === 'swap') {
    const next = [...list];
    const tmp = next[fromIdx];
    next[fromIdx] = next[toIdx];
    next[toIdx] = tmp;
    return next;
  }
  const next = [...list];
  const [item] = next.splice(fromIdx, 1);
  let dest = toIdx;
  if (fromIdx < toIdx) dest = toIdx - 1;
  if (place === 'after') dest += 1;
  dest = Math.max(0, Math.min(next.length, dest));
  next.splice(dest, 0, item);
  return next;
}

export function dropHighlightSx(
  active: boolean,
  place: DropPlace | null,
): Record<string, unknown> {
  if (!active || !place) {
    return { outline: 'none' };
  }
  if (place === 'swap') {
    return {
      outline: '2px dashed',
      outlineColor: 'primary.main',
      outlineOffset: -2,
      bgcolor: 'rgba(37, 100, 207, 0.12)',
    };
  }
  return { outline: 'none' };
}

const LAYER =
  'position:fixed;pointer-events:none;z-index:1999;display:none;';

let dropBar: HTMLDivElement | null = null;
let dropFrame: HTMLDivElement | null = null;
let dropChip: HTMLDivElement | null = null;

function ensureDropLayer(): void {
  if (dropBar) return;
  dropBar = document.createElement('div');
  dropFrame = document.createElement('div');
  dropChip = document.createElement('div');
  dropBar.style.cssText =
    LAYER + 'background:#2564cf;border-radius:2px;box-shadow:0 0 0 1px #fff;';
  dropFrame.style.cssText =
    LAYER +
    'box-sizing:border-box;border:2px dashed #2564cf;background:rgba(37,100,207,.12);';
  dropChip.style.cssText =
    LAYER +
    'transform:translate(-50%,-50%);background:#2564cf;color:#fff;font:700 12px/1.4 sans-serif;padding:2px 8px;border-radius:4px;box-shadow:0 1px 4px rgba(0,0,0,.25);white-space:nowrap;';
  dropChip.textContent = '互换';
  document.body.append(dropBar, dropFrame, dropChip);
}

export function clearDropPaint(): void {
  if (dropBar) dropBar.style.display = 'none';
  if (dropFrame) dropFrame.style.display = 'none';
  if (dropChip) dropChip.style.display = 'none';
}

export function paintDropTarget(
  el: EventTarget | null | undefined,
  place: DropPlace,
  opts?: { layout?: DropLayout; x?: number; y?: number },
): void {
  if (!(el instanceof HTMLElement)) return;
  ensureDropLayer();
  const r = el.getBoundingClientRect();
  if (place === 'swap') {
    dropBar!.style.display = 'none';
    dropFrame!.style.display = 'block';
    dropFrame!.style.left = `${r.left}px`;
    dropFrame!.style.top = `${r.top}px`;
    dropFrame!.style.width = `${r.width}px`;
    dropFrame!.style.height = `${r.height}px`;
    dropChip!.style.display = 'block';
    dropChip!.style.left = `${r.left + r.width / 2}px`;
    dropChip!.style.top = `${r.top + r.height / 2}px`;
    return;
  }
  dropFrame!.style.display = 'none';
  dropChip!.style.display = 'none';
  dropBar!.style.display = 'block';
  let side: 'top' | 'bottom' | 'left' | 'right' =
    place === 'before' ? 'top' : 'bottom';
  if (opts?.layout === 'x') {
    side = place === 'before' ? 'left' : 'right';
  } else if (opts?.layout === 'xy' && opts.x != null && opts.y != null) {
    const dl = opts.x - r.left;
    const dr = r.right - opts.x;
    const dt = opts.y - r.top;
    const db = r.bottom - opts.y;
    side =
      place === 'before'
        ? dt <= dl
          ? 'top'
          : 'left'
        : db <= dr
          ? 'bottom'
          : 'right';
  }
  const thick = 3;
  const inset = 8;
  if (side === 'top' || side === 'bottom') {
    dropBar!.style.width = `${Math.max(0, r.width - inset * 2)}px`;
    dropBar!.style.height = `${thick}px`;
    dropBar!.style.left = `${r.left + inset}px`;
    dropBar!.style.top = `${side === 'top' ? r.top - 1 : r.bottom - 2}px`;
  } else {
    dropBar!.style.width = `${thick}px`;
    dropBar!.style.height = `${Math.max(0, r.height - inset * 2)}px`;
    dropBar!.style.left = `${side === 'left' ? r.left - 1 : r.right - 2}px`;
    dropBar!.style.top = `${r.top + inset}px`;
  }
}

export const dropPaintSx = {};

const EMPTY_DRAG_GIF =
  'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

export function setCefDragData(ev: { dataTransfer: DataTransfer }, id: string): void {
  ev.dataTransfer.setData('text/plain', id);
  ev.dataTransfer.effectAllowed = 'move';
  const img = new Image();
  img.src = EMPTY_DRAG_GIF;
  ev.dataTransfer.setDragImage(img, 0, 0);
}

/** CEF 常丢失 drop；松开时用最后一次落点提交排序 */
export function useCefDragAllow(
  isDragging: () => boolean,
  finish: () => void,
  cancel?: () => void,
): void {
  const isDraggingRef = useRef(isDragging);
  const finishRef = useRef(finish);
  const cancelRef = useRef(cancel ?? finish);
  isDraggingRef.current = isDragging;
  finishRef.current = finish;
  cancelRef.current = cancel ?? finish;
  useEffect(() => {
    const dragging = () => isDraggingRef.current();
    const doFinish = () => finishRef.current();
    const doCancel = () => cancelRef.current();
    const allowDrop = (e: DragEvent) => {
      if (!dragging()) return;
      e.preventDefault();
      if (e.dataTransfer) e.dataTransfer.dropEffect = 'move';
    };
    const onDropAnywhere = (e: DragEvent) => {
      if (!dragging()) return;
      e.preventDefault();
      doFinish();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && dragging()) doCancel();
    };
    const onPointerUp = () => {
      if (dragging()) doFinish();
    };
    window.addEventListener('dragend', doFinish, true);
    window.addEventListener('dragover', allowDrop, true);
    window.addEventListener('drop', onDropAnywhere);
    window.addEventListener('keydown', onKey);
    window.addEventListener('pointerup', onPointerUp, true);
    return () => {
      window.removeEventListener('dragend', doFinish, true);
      window.removeEventListener('dragover', allowDrop, true);
      window.removeEventListener('drop', onDropAnywhere);
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('pointerup', onPointerUp, true);
    };
  }, []);
}

