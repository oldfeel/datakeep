import type { OutputData } from '@editorjs/editorjs';
import { dataUrl } from './datakeep';

export function isOutputEmpty(data: OutputData | null | undefined): boolean {
  if (!data?.blocks?.length) return true;
  return !data.blocks.some((b) => {
    const d = (b.data || {}) as Record<string, unknown>;
    if (b.type === 'image') return Boolean(d.url || d.rel);
    const raw = JSON.stringify(d);
    const plain = raw.replace(/<[^>]+>/g, '').replace(/[{}\[\]",:]/g, ' ').trim();
    return plain.length > 0;
  });
}

export function imageRelsFromOutput(data: OutputData): string[] {
  const out: string[] = [];
  for (const b of data.blocks || []) {
    if (b.type !== 'image') continue;
    const d = (b.data || {}) as { rel?: string; url?: string };
    if (d.rel) {
      out.push(d.rel);
      continue;
    }
    const url = String(d.url || '');
    const marker = '/__datakeep/data/';
    const i = url.indexOf(marker);
    if (i >= 0) {
      try {
        out.push(decodeURIComponent(url.slice(i + marker.length)));
      } catch {
        out.push(url.slice(i + marker.length));
      }
    }
  }
  return out;
}

export function commentToOutput(body: string, images: string[]): OutputData {
  try {
    const o = JSON.parse(body) as OutputData;
    if (o && Array.isArray(o.blocks)) return o;
  } catch {
    /* 旧评论纯文本 */
  }
  const blocks: OutputData['blocks'] = [];
  const text = body.trim();
  if (text) {
    blocks.push({
      type: 'paragraph',
      data: { text: text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/\n/g, '<br>') },
    });
  }
  for (const rel of images) {
    blocks.push({
      type: 'image',
      data: { url: dataUrl(rel), rel },
    });
  }
  return { time: Date.now(), blocks };
}
