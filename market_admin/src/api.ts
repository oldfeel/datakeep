const API_BASE = import.meta.env.VITE_API_BASE ?? '';

export type ApiResult<T> = { code: number; data: T };

export async function api<T>(
  path: string,
  options: RequestInit & { token?: string | null } = {},
): Promise<T> {
  const headers = new Headers(options.headers);
  if (!headers.has('Content-Type') && options.body && !(options.body instanceof FormData)) {
    headers.set('Content-Type', 'application/json');
  }
  if (options.token) {
    headers.set('Authorization', `Bearer ${options.token}`);
  }
  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });
  const json = (await res.json()) as ApiResult<T>;
  if (json.code !== 0) {
    throw new Error(typeof json.data === 'string' ? json.data : '请求失败');
  }
  return json.data;
}

/** 经 Go 代传到对象存储，避免浏览器直传 CORS */
export async function uploadZip(
  token: string,
  appId: number,
  version: string,
  file: File,
): Promise<{ objectKey: string; sha256: string; size: number }> {
  const fd = new FormData();
  fd.append('version', version);
  fd.append('file', file);
  const headers = new Headers();
  headers.set('Authorization', `Bearer ${token}`);
  const res = await fetch(`${API_BASE}/admin/apps/${appId}/upload`, {
    method: 'POST',
    headers,
    body: fd,
  });
  const json = (await res.json()) as ApiResult<{
    objectKey: string;
    sha256: string;
    size: number;
  }>;
  if (json.code !== 0) {
    throw new Error(typeof json.data === 'string' ? json.data : '上传失败');
  }
  return json.data;
}
