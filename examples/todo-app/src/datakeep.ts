/** DataKeep 宿主 API：相对安装目录 data/ 的文件读写与 revision 监听 */

export type PickedStagedFile = {
  rel: string;
  name: string;
  size?: number;
  mime?: string;
};

declare global {
  interface Window {
    __datakeepPickFile?: (accept?: string) => Promise<PickedStagedFile>;
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

function pickViaInput(accept: string, multiple: boolean): Promise<File[]> {
  return new Promise((resolve, reject) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.multiple = multiple;
    input.onchange = () => {
      const list = input.files ? Array.from(input.files) : [];
      if (list.length) resolve(list);
      else reject(new Error('cancelled'));
    };
    input.oncancel = () => reject(new Error('cancelled'));
    input.click();
  });
}

/** CEF 无系统文件框：优先宿主 FilePicker，无宿主时回退 input */
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
  const files = await pickViaInput(accept, false);
  return files[0];
}

export async function pickFiles(accept: string): Promise<Array<PickedStagedFile | File>> {
  if (typeof window.DataKeepHost === 'function') {
    const m = await callHost({ method: 'pickFiles', accept: accept || '' });
    const files = m.files;
    if (Array.isArray(files) && files.length) {
      return files.map((f) => {
        const o = f as Record<string, unknown>;
        return {
          rel: String(o.rel || ''),
          name: String(o.name || ''),
          size: typeof o.size === 'number' ? o.size : undefined,
          mime: typeof o.mime === 'string' ? o.mime : undefined,
        };
      });
    }
    throw new Error('cancelled');
  }
  return pickViaInput(accept, true);
}

export function isStagedPick(v: PickedStagedFile | File): v is PickedStagedFile {
  return !(v instanceof File) && typeof (v as PickedStagedFile).rel === 'string';
}

export function dataUrl(rel: string): string {
  const parts = String(rel || '')
    .split('/')
    .filter(Boolean)
    .map(encodeURIComponent);
  return '/__datakeep/data/' + parts.join('/');
}

export async function listDir(prefix = ''): Promise<string[]> {
  const base = String(prefix || '').replace(/^\/+|\/+$/g, '');
  const url = base ? dataUrl(base) + '/' : '/__datakeep/data/';
  const res = await fetch(url, { cache: 'no-store' });
  if (res.status === 404) return [];
  if (!res.ok) throw new Error(`列目录失败: HTTP ${res.status}`);
  const j = (await res.json()) as { files?: string[] };
  return j.files ?? [];
}

export async function putDataFile(
  rel: string,
  body: BodyInit = new Uint8Array(0),
): Promise<void> {
  const res = await fetch(dataUrl(rel), {
    method: 'PUT',
    cache: 'no-store',
    headers: { 'Content-Type': 'application/octet-stream' },
    body,
  });
  if (!res.ok) throw new Error(`写入失败: HTTP ${res.status}`);
}

export function putDataFileWithProgress(
  rel: string,
  body: Blob,
  onProgress?: (ratio: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', dataUrl(rel));
    xhr.setRequestHeader('Content-Type', 'application/octet-stream');
    xhr.upload.onprogress = (ev) => {
      if (!onProgress || !ev.lengthComputable || ev.total <= 0) return;
      onProgress(ev.loaded / ev.total);
    };
    xhr.onload = () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else reject(new Error(`写入失败: HTTP ${xhr.status}`));
    };
    xhr.onerror = () => reject(new Error('写入失败: 网络错误'));
    xhr.send(body);
  });
}

export async function getDataBlob(rel: string): Promise<Blob | null> {
  const res = await fetch(dataUrl(rel), { cache: 'no-store' });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`读取失败: HTTP ${res.status}`);
  return res.blob();
}

export async function deleteDataFile(rel: string): Promise<void> {
  const res = await fetch(dataUrl(rel), { method: 'DELETE', cache: 'no-store' });
  if (res.status === 404) return;
  if (!res.ok) throw new Error(`删除失败: HTTP ${res.status}`);
}

export type Revision = { dataRev: number; appRev: number };

let dataWatchPaused = false;

export function setDataWatchPaused(paused: boolean): void {
  dataWatchPaused = paused;
}

export async function fetchRevision(): Promise<Revision> {
  const res = await fetch('/__datakeep/revision', { cache: 'no-store' });
  if (!res.ok) throw new Error(`revision HTTP ${res.status}`);
  return res.json() as Promise<Revision>;
}

export function watchData(onDataChange: () => void): () => void {
  let lastDataRev: number | null = null;
  let lastAppRev: number | null = null;
  let busy = false;

  const onRev = (j: Revision | null) => {
    if (!j) return;
    if (dataWatchPaused) {
      lastDataRev = j.dataRev;
      lastAppRev = j.appRev;
      return;
    }
    if (lastAppRev == null) lastAppRev = j.appRev;
    else if (j.appRev !== lastAppRev) {
      lastAppRev = j.appRev;
      location.reload();
      return;
    }
    if (lastDataRev == null) {
      lastDataRev = j.dataRev;
      return;
    }
    if (j.dataRev === lastDataRev) return;
    lastDataRev = j.dataRev;
    onDataChange();
  };

  const tick = () => {
    if (busy) return;
    busy = true;
    fetchRevision()
      .then(onRev)
      .catch(() => {})
      .finally(() => {
        busy = false;
      });
  };

  const onCustom = () => tick();
  window.addEventListener('datakeep:data-changed', onCustom);
  const timer = window.setInterval(tick, 2000);
  tick();

  return () => {
    window.removeEventListener('datakeep:data-changed', onCustom);
    window.clearInterval(timer);
  };
}
