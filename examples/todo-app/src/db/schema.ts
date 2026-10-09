import type { Database } from 'sql.js';
import { nowIso, uuid } from './types';

export const DB_NAME = 'todo.db';
export const DEFAULT_LIST_TITLE = '任务';

function tableExists(db: Database, name: string): boolean {
  const stmt = db.prepare(
    "SELECT 1 AS o FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
  );
  stmt.bind([name]);
  const ok = stmt.step();
  stmt.free();
  return ok;
}

function columnNames(db: Database, table: string): string[] {
  const cols: string[] = [];
  try {
    const stmt = db.prepare(`PRAGMA table_info(${table})`);
    while (stmt.step()) {
      const r = stmt.getAsObject() as { name?: string };
      if (r.name) cols.push(String(r.name));
    }
    stmt.free();
  } catch {
    /* ignore */
  }
  return cols;
}

/** 1.x 或残缺库：无 lists / tasks 无 list_id → 整库重建（不兼容旧数据） */
function needsV2Reset(db: Database): boolean {
  if (!tableExists(db, 'lists')) {
    // 仅有旧 tasks（无 lists）也算 1.x
    if (tableExists(db, 'tasks')) {
      const cols = columnNames(db, 'tasks');
      if (!cols.includes('list_id')) return true;
    }
    return false; // 全新空库，下面 CREATE 即可
  }
  if (tableExists(db, 'tasks')) {
    const cols = columnNames(db, 'tasks');
    if (!cols.includes('list_id') || !cols.includes('note_json')) return true;
  }
  return false;
}

function dropAllAppTables(db: Database): void {
  db.run('DROP TABLE IF EXISTS comments');
  db.run('DROP TABLE IF EXISTS attachments');
  db.run('DROP TABLE IF EXISTS steps');
  db.run('DROP TABLE IF EXISTS tasks');
  db.run('DROP TABLE IF EXISTS lists');
}

export function migrate(db: Database): void {
  if (needsV2Reset(db)) {
    console.warn('[todo] 检测到 1.x / 旧 schema，重建 todo.db（不迁移旧任务）');
    dropAllAppTables(db);
  }

  db.run(`
    CREATE TABLE IF NOT EXISTS lists (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0
    )
  `);
  db.run(`
    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      list_id TEXT NOT NULL,
      title TEXT NOT NULL,
      note_json TEXT NOT NULL DEFAULT '',
      done INTEGER NOT NULL DEFAULT 0,
      due_at TEXT,
      remind_at TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0
    )
  `);
  db.run(`
    CREATE TABLE IF NOT EXISTS steps (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      title TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0
    )
  `);
  db.run(`
    CREATE TABLE IF NOT EXISTS attachments (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      name TEXT NOT NULL,
      rel_path TEXT NOT NULL,
      mime TEXT NOT NULL DEFAULT '',
      size INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0
    )
  `);
  db.run(`
    CREATE TABLE IF NOT EXISTS comments (
      id TEXT PRIMARY KEY,
      task_id TEXT NOT NULL,
      body TEXT NOT NULL,
      images_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0
    )
  `);

  if (tableExists(db, 'comments')) {
    const cols = columnNames(db, 'comments');
    if (!cols.includes('images_json')) {
      db.run(`ALTER TABLE comments ADD COLUMN images_json TEXT NOT NULL DEFAULT '[]'`);
    }
  }

  ensureDefaultList(db);
}

/** 若无未删除列表，插入一条默认列表 */
export function ensureDefaultList(db: Database): string {
  const stmt = db.prepare(
    'SELECT id FROM lists WHERE deleted = 0 ORDER BY sort_order ASC, created_at ASC LIMIT 1',
  );
  if (stmt.step()) {
    const row = stmt.getAsObject() as { id: string };
    stmt.free();
    return row.id;
  }
  stmt.free();
  const id = uuid();
  const t = nowIso();
  db.run(
    'INSERT INTO lists (id, title, sort_order, created_at, updated_at, deleted) VALUES (?,?,?,?,?,0)',
    [id, DEFAULT_LIST_TITLE, 0, t, t],
  );
  return id;
}
