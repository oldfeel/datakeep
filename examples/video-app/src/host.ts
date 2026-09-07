/** 宿主选文件 / 截封面（CEF 无系统文件框、且无法解码 mkv 等） */

export type PickedStagedFile = {
  rel: string;
  name: string;
  size?: number;
  mime?: string;
};

export type CoverFrameInfo = {
  /** data/ 相对路径；浏览器抽帧时为空，用 url */
  rel?: string;
  url: string;
  sec: number;
  luma: number;
  recommended?: boolean;
};

declare global {
  interface Window {
    __datakeepPickFile?: (accept?: string) => Promise<PickedStagedFile>;
    __datakeepGenerateCover?: (rel: string) => Promise<PickedStagedFile>;
    __datakeepListCoverFrames?: (rel: string) => Promise<{
      frames: Array<{
        rel: string;
        sec: number;
        luma: number;
        recommended?: boolean;
      }>;
    }>;
    __datakeepPrepareCoverFrames?: (rel: string) => Promise<{
      seeks: number[];
      coversRel?: string;
      duration?: number;
    }>;
    __datakeepExtractCoverFrame?: (
      rel: string,
      sec: number,
      index: number,
    ) => Promise<{ rel: string; sec: number; luma: number; index?: number }>;
    __datakeepPlayVideo?: (
      rel: string,
      title?: string,
    ) => Promise<{ ok?: boolean }>;
    __datakeepProbeDuration?: (rel: string) => Promise<{ duration?: number }>;
    /** CEF 注入：第一个参数会被再 JSON.stringify，应传对象而非已序列化字符串 */
    DataKeepHost?: (msg: object | string, cb: (res: unknown) => void) => void;
  }
}

function parseHostResult(res: unknown): Record<string, unknown> {
  let j: unknown = res;
  if (typeof res === 'string') {
    try {
      j = JSON.parse(res);
    } catch {
      /* keep */
    }
  }
  if (!j || typeof j !== 'object') {
    throw new Error('empty');
  }
  return j as Record<string, unknown>;
}

function callHost(payload: object): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    if (typeof window.DataKeepHost !== 'function') {
      reject(new Error('NO_HOST'));
      return;
    }
    try {
      window.DataKeepHost!(payload, (res) => {
        try {
          const m = parseHostResult(res);
          if (m.cancelled) {
            reject(new Error('cancelled'));
            return;
          }
          if (m.error) {
            reject(new Error(String(m.error)));
            return;
          }
          resolve(m);
        } catch (e) {
          reject(e);
        }
      });
    } catch (e) {
      reject(e);
    }
  });
}

/** 优先宿主 FilePicker；无宿主时回退浏览器 input */
export async function pickFile(accept: string): Promise<PickedStagedFile | File> {
  if (typeof window.__datakeepPickFile === 'function') {
    return window.__datakeepPickFile(accept);
  }
  if (typeof window.DataKeepHost === 'function') {
    const m = await callHost({ method: 'pickFile', accept: accept || '' });
    return {
      rel: String(m.rel || ''),
      name: String(m.name || ''),
      size: typeof m.size === 'number' ? m.size : undefined,
      mime: typeof m.mime === 'string' ? m.mime : undefined,
    };
  }

  return new Promise((resolve, reject) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.onchange = () => {
      const f = input.files?.[0];
      if (f) resolve(f);
      else reject(new Error('cancelled'));
    };
    input.oncancel = () => reject(new Error('cancelled'));
    input.click();
  });
}

/** 宿主从已暂存视频截帧（mkv 等 CEF 播不了的格式） */
export async function generateCoverFromRel(rel: string): Promise<PickedStagedFile> {
  if (typeof window.__datakeepGenerateCover === 'function') {
    return window.__datakeepGenerateCover(rel);
  }
  const m = await callHost({ method: 'generateCover', rel });
  return {
    rel: String(m.rel || ''),
    name: String(m.name || 'cover_gen.jpg'),
    size: typeof m.size === 'number' ? m.size : undefined,
    mime: typeof m.mime === 'string' ? m.mime : 'image/jpeg',
  };
}

/** 准备画廊：返回取样时间点（不截帧） */
export async function prepareCoverFramesFromRel(
  rel: string,
): Promise<{ seeks: number[]; coversRel?: string; duration?: number }> {
  let m: Record<string, unknown>;
  if (typeof window.__datakeepPrepareCoverFrames === 'function') {
    m = (await window.__datakeepPrepareCoverFrames(rel)) as Record<string, unknown>;
  } else {
    m = await callHost({ method: 'prepareCoverFrames', rel });
  }
  const seeksRaw = m.seeks;
  if (!Array.isArray(seeksRaw) || seeksRaw.length === 0) {
    throw new Error('无法准备封面取样点');
  }
  const seeks = seeksRaw.map((s) => (typeof s === 'number' ? s : Number(s) || 0));
  return {
    seeks,
    coversRel: typeof m.coversRel === 'string' ? m.coversRel : undefined,
    duration: typeof m.duration === 'number' ? m.duration : undefined,
  };
}

/** 截取单帧 */
export async function extractCoverFrameFromRel(
  rel: string,
  sec: number,
  index: number,
): Promise<{ rel: string; sec: number; luma: number }> {
  let m: Record<string, unknown>;
  if (typeof window.__datakeepExtractCoverFrame === 'function') {
    m = (await window.__datakeepExtractCoverFrame(rel, sec, index)) as Record<
      string,
      unknown
    >;
  } else {
    m = await callHost({ method: 'extractCoverFrame', rel, sec, index });
  }
  return {
    rel: String(m.rel || ''),
    sec: typeof m.sec === 'number' ? m.sec : Number(m.sec) || sec,
    luma: typeof m.luma === 'number' ? m.luma : Number(m.luma) || 0,
  };
}

export function isStagedPick(v: PickedStagedFile | File): v is PickedStagedFile {
  return !(v instanceof File) && typeof (v as PickedStagedFile).rel === 'string';
}

/** CEF/Chromium 通常无法在 <video> 中解码的容器 */
export function needsHostCover(fileName: string): boolean {
  return /\.(mkv|avi|mpeg|mpg|flv|wmv|ts|m2ts)$/i.test(fileName);
}

export function hasCoverHost(): boolean {
  return (
    typeof window.__datakeepPrepareCoverFrames === 'function' ||
    typeof window.__datakeepListCoverFrames === 'function' ||
    typeof window.DataKeepHost === 'function'
  );
}

export function hasPlayVideoHost(): boolean {
  return (
    typeof window.__datakeepPlayVideo === 'function' ||
    typeof window.DataKeepHost === 'function'
  );
}

/** 用 DataKeep 内置 media_kit 播放（与文件浏览相同，可播 mkv 等） */
export async function playVideoFromRel(
  rel: string,
  title?: string,
): Promise<void> {
  if (typeof window.__datakeepPlayVideo === 'function') {
    await window.__datakeepPlayVideo(rel, title);
    return;
  }
  await callHost({ method: 'playVideo', rel, title: title || '' });
}

export function hasProbeDurationHost(): boolean {
  return (
    typeof window.__datakeepProbeDuration === 'function' ||
    typeof window.DataKeepHost === 'function'
  );
}

/** 探测视频时长（秒） */
export async function probeDurationFromRel(rel: string): Promise<number | null> {
  let m: Record<string, unknown>;
  if (typeof window.__datakeepProbeDuration === 'function') {
    m = (await window.__datakeepProbeDuration(rel)) as Record<string, unknown>;
  } else {
    m = await callHost({ method: 'probeDuration', rel });
  }
  const d = m.duration;
  if (typeof d === 'number' && Number.isFinite(d) && d > 0) return d;
  return null;
}

/** 格式化为 mm:ss 或 h:mm:ss */
export function formatDuration(sec: number | null | undefined): string {
  if (sec == null || !Number.isFinite(sec) || sec < 0) return '';
  const s = Math.round(sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  if (h > 0) {
    return `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
  }
  return `${m}:${String(r).padStart(2, '0')}`;
}
