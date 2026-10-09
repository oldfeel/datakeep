import type { Database } from 'sql.js';
import {
  deleteConflictFile,
  getDb,
  listConflictDbFiles,
  openFromBytes,
  persist,
} from './sql';
import { dataUrl } from '../datakeep';
import { migrate } from './schema';

type RowMap = Record<string, Record<string, unknown>>;

function pickNewer(
  a: Record<string, unknown> | undefined,
  b: Record<string, unknown> | undefined,
): Record<string, unknown> | undefined {
  if (!a) return b;
  if (!b) return a;
  const au = String(a.updated_at || '');
  const bu = String(b.updated_at || '');
  if (au > bu) return a;
  if (bu > au) return b;
  const ad = a.deleted ? 1 : 0;
  const bd = b.deleted ? 1 : 0;
  if (ad !== bd) return ad ? a : b;
  return a;
}

function readTable(sqlite: Database, table: string, cols: string[]): RowMap {
  const map: RowMap = {};
  try {
    const stmt = sqlite.prepare(`SELECT ${cols.join(',')} FROM ${table}`);
    while (stmt.step()) {
      const r = stmt.getAsObject() as Record<string, unknown>;
      const id = String(r.id || '');
      if (!id) continue;
      r.updated_at = r.updated_at || r.created_at || '';
      r.deleted = r.deleted ? 1 : 0;
      map[id] = pickNewer(map[id], r) as Record<string, unknown>;
    }
    stmt.free();
  } catch (e) {
    console.warn(`读取 ${table} 失败`, e);
  }
  return map;
}

const TABLES: { name: string; cols: string[] }[] = [
  {
    name: 'lists',
    cols: ['id', 'title', 'sort_order', 'created_at', 'updated_at', 'deleted'],
  },
  {
    name: 'tasks',
    cols: [
      'id',
      'list_id',
      'title',
      'note_json',
      'done',
      'due_at',
      'remind_at',
      'sort_order',
      'created_at',
      'updated_at',
      'deleted',
    ],
  },
  {
    name: 'steps',
    cols: [
      'id',
      'task_id',
      'title',
      'done',
      'sort_order',
      'created_at',
      'updated_at',
      'deleted',
    ],
  },
  {
    name: 'attachments',
    cols: [
      'id',
      'task_id',
      'name',
      'rel_path',
      'mime',
      'size',
      'created_at',
      'updated_at',
      'deleted',
    ],
  },
  {
    name: 'comments',
    cols: ['id', 'task_id', 'body', 'images_json', 'created_at', 'updated_at', 'deleted'],
  },
];

function mergeMaps(into: RowMap, from: RowMap): void {
  for (const [id, row] of Object.entries(from)) {
    into[id] = pickNewer(into[id], row) as Record<string, unknown>;
  }
}

function writeTable(db: Database, table: string, cols: string[], map: RowMap): void {
  db.run(`DELETE FROM ${table}`);
  const placeholders = cols.map(() => '?').join(',');
  const sql = `INSERT INTO ${table} (${cols.join(',')}) VALUES (${placeholders})`;
  for (const row of Object.values(map)) {
    const vals = cols.map((c) => {
      const v = row[c];
      if (c === 'images_json' && (v == null || v === '')) return '[]';
      if (v == null) return null;
      return v as string | number;
    });
    db.run(sql, vals);
  }
}

/** 合并主库 + 冲突副本，写回并删除冲突文件 */
export async function mergeConflictDatabases(): Promise<{
  merged: number;
  conflicts: number;
}> {
  const conflicts = await listConflictDbFiles();
  if (!conflicts.length) return { merged: 0, conflicts: 0 };

  const main = getDb();
  migrate(main);

  const maps: Record<string, RowMap> = {};
  for (const t of TABLES) {
    maps[t.name] = readTable(main, t.name, t.cols);
  }

  for (const name of conflicts) {
    try {
      const res = await fetch(dataUrl(name), { cache: 'no-store' });
      if (!res.ok) continue;
      const buf = await res.arrayBuffer();
      const temp = await openFromBytes(buf);
      for (const t of TABLES) {
        mergeMaps(maps[t.name], readTable(temp, t.name, t.cols));
      }
      temp.close();
    } catch (e) {
      console.warn('合并冲突库失败', name, e);
    }
  }

  for (const t of TABLES) {
    writeTable(main, t.name, t.cols, maps[t.name]);
  }

  await persist();

  for (const name of conflicts) {
    try {
      await deleteConflictFile(name);
    } catch (e) {
      console.warn('删除冲突文件失败', name, e);
    }
  }

  return { merged: 1, conflicts: conflicts.length };
}
