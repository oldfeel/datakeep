import {
  dataUrl,
  deleteDataFile,
  getDataBlob,
  isStagedPick,
  pickFile,
  pickFiles,
  putDataFileWithProgress,
  setDataWatchPaused,
  type PickedStagedFile,
} from './datakeep';
import { uuid } from './db/types';

const IMAGE_MIME = /^(image\/(jpeg|png|gif|webp|bmp|svg\+xml))$/i;

export function isImageFile(file: File): boolean {
  if (file.type && IMAGE_MIME.test(file.type)) return true;
  return /\.(jpe?g|png|gif|webp|bmp|svg)$/i.test(file.name);
}

function isImageName(name: string, mime?: string): boolean {
  if (mime && IMAGE_MIME.test(mime)) return true;
  return /\.(jpe?g|png|gif|webp|bmp|svg)$/i.test(name);
}

function safeFileName(name: string): string {
  const base = name.split(/[/\\]/).pop() || 'image';
  return base.replace(/[^\w.\u4e00-\u9fff-]+/g, '_').slice(0, 80) || 'image';
}

export type UploadedImage = {
  rel: string;
  url: string;
  name: string;
};

async function writeImage(
  kind: 'note' | 'comment',
  taskId: string,
  name: string,
  body: Blob,
): Promise<UploadedImage> {
  const rel = `images/${kind}/${taskId}/${uuid()}_${safeFileName(name)}`;
  await putDataFileWithProgress(rel, body);
  return { rel, url: dataUrl(rel), name };
}

/** 写入 data/images/{kind}/{taskId}/ ，暂停 revision 监听以免上传中途 reload */
export async function uploadTaskImage(
  kind: 'note' | 'comment',
  taskId: string,
  file: File,
): Promise<UploadedImage> {
  if (!isImageFile(file)) {
    throw new Error('请选择图片文件');
  }
  setDataWatchPaused(true);
  try {
    return await writeImage(kind, taskId, file.name, file);
  } finally {
    setDataWatchPaused(false);
  }
}

export async function uploadPickedImage(
  kind: 'note' | 'comment',
  taskId: string,
  picked: PickedStagedFile | File,
): Promise<UploadedImage> {
  if (picked instanceof File) {
    return uploadTaskImage(kind, taskId, picked);
  }
  if (!isImageName(picked.name, picked.mime)) {
    throw new Error('请选择图片文件');
  }
  setDataWatchPaused(true);
  try {
    const blob = await getDataBlob(picked.rel);
    if (!blob) throw new Error('读取所选图片失败');
    const up = await writeImage(kind, taskId, picked.name, blob);
    try {
      await deleteDataFile(picked.rel);
    } catch {
      /* staging 清理失败可忽略 */
    }
    return up;
  } finally {
    setDataWatchPaused(false);
  }
}

export async function pickAndUploadImages(
  kind: 'note' | 'comment',
  taskId: string,
  multiple: boolean,
): Promise<UploadedImage[]> {
  const picked = multiple
    ? await pickFiles('image/*')
    : [await pickFile('image/*')];
  const out: UploadedImage[] = [];
  for (const p of picked) {
    if (isStagedPick(p) && !p.rel) continue;
    out.push(await uploadPickedImage(kind, taskId, p));
  }
  return out;
}

export function isPickCancelled(e: unknown): boolean {
  return e instanceof Error && e.message === 'cancelled';
}
