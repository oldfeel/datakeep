import type { Database, SqlJsStatic } from 'sql.js';
import sqlWasmUrl from 'sql.js/dist/sql-wasm-browser.wasm?url';
import { dataUrl, deleteDataFile, listDir } from '../datakeep';
import { DB_NAME, migrate } from './schema';

let SQL: SqlJsStatic | null = null;
let db: Database | null = null;
let saveTimer: number | null = null;
let onPersistError: ((e: Error) => void) | null = null;

export function setPersistErrorHandler(fn: ((e: Error) => void) | null): void {
  onPersistError = fn;
}

async function loadSql(): Promise<SqlJsStatic> {
  if (SQL) return SQL;
  // 必须用 browser 构建 + 对应 wasm；否则 CEF 里会白屏 / wasm 加载失败
  const mod = await import('sql.js/dist/sql-wasm-browser.js');
  const init = ((mod as unknown as { default?: unknown }).default ??
    mod) as (c?: {
    locateFile?: (f: string) => string;
  }) => Promise<SqlJsStatic>;
  SQL = await init({
    locateFile: () => sqlWasmUrl,
  });
  return SQL;
}

export function getDb(): Database {
  if (!db) throw new Error('数据库未打开');
  return db;
}

export async function openDatabase(): Promise<Database> {
  const sql = await loadSql();
  const res = await fetch(dataUrl(DB_NAME), { cache: 'no-store' });
  if (res.ok) {
    const buf = await res.arrayBuffer();
    db = new sql.Database(new Uint8Array(buf));
  } else if (res.status === 404) {
    db = new sql.Database();
  } else {
    throw new Error(`读取数据库失败: HTTP ${res.status}`);
  }
  migrate(db);
  // 若刚从 1.x 重建，尽快写回，避免下次仍读旧 schema
  schedulePersist(0);
  return db;
}

export async function openFromBytes(buf: ArrayBuffer): Promise<Database> {
  const sql = await loadSql();
  const temp = new sql.Database(new Uint8Array(buf));
  try {
    migrate(temp);
  } catch {
    /* 冲突库可能缺表，仍尝试读 */
  }
  return temp;
}

export async function persist(): Promise<void> {
  if (!db) return;
  if ((window as unknown as { __DATAKEEP_READONLY?: boolean }).__DATAKEEP_READONLY) {
    throw new Error('对端只读，无法保存');
  }
  const data = db.export();
  const res = await fetch(dataUrl(DB_NAME), {
    method: 'PUT',
    headers: { 'Content-Type': 'application/octet-stream' },
    body: new Uint8Array(data),
  });
  if (!res.ok) throw new Error(`保存失败: HTTP ${res.status}`);
}

export function schedulePersist(ms = 200): void {
  if ((window as unknown as { __DATAKEEP_READONLY?: boolean }).__DATAKEEP_READONLY) {
    onPersistError?.(new Error('对端只读，无法保存'));
    return;
  }
  if (saveTimer != null) window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(() => {
    saveTimer = null;
    persist().catch((e) => {
      console.error(e);
      onPersistError?.(e instanceof Error ? e : new Error(String(e)));
    });
  }, ms);
}

export function isConflictDbName(name: string): boolean {
  return (
    name.indexOf('todo') === 0 &&
    name.indexOf('.sync-conflict-') >= 0 &&
    /\.db$/i.test(name)
  );
}

export async function listConflictDbFiles(): Promise<string[]> {
  const files = await listDir('');
  return files.filter((f) => f.indexOf('/') < 0 && isConflictDbName(f));
}

export async function deleteConflictFile(name: string): Promise<void> {
  await deleteDataFile(name);
}
