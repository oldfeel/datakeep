import type { OutputData } from '@editorjs/editorjs';
import {
  deleteDataFile,
  putDataFileWithProgress,
  setDataWatchPaused,
} from '../datakeep';
import { ensureDefaultList } from './schema';
import { getDb, schedulePersist } from './sql';
import {
  type AttachmentRow,
  type ListRow,
  type StepRow,
  type TaskRow,
  nowIso,
  uuid,
} from './types';

function asList(r: Record<string, unknown>): ListRow {
  return {
    id: String(r.id),
    title: String(r.title || ''),
    sort_order: Number(r.sort_order) || 0,
    created_at: String(r.created_at || ''),
    updated_at: String(r.updated_at || ''),
    deleted: r.deleted ? 1 : 0,
  };
}

function asTask(r: Record<string, unknown>): TaskRow {
  return {
    id: String(r.id),
    list_id: String(r.list_id),
    title: String(r.title || ''),
    note_json: String(r.note_json || ''),
    done: r.done ? 1 : 0,
    due_at: r.due_at != null && r.due_at !== '' ? String(r.due_at) : null,
    remind_at: r.remind_at != null && r.remind_at !== '' ? String(r.remind_at) : null,
    sort_order: Number(r.sort_order) || 0,
    created_at: String(r.created_at || ''),
    updated_at: String(r.updated_at || ''),
    deleted: r.deleted ? 1 : 0,
  };
}

function asStep(r: Record<string, unknown>): StepRow {
  return {
    id: String(r.id),
    task_id: String(r.task_id),
    title: String(r.title || ''),
    done: r.done ? 1 : 0,
    sort_order: Number(r.sort_order) || 0,
    created_at: String(r.created_at || ''),
    updated_at: String(r.updated_at || ''),
    deleted: r.deleted ? 1 : 0,
  };
}

function asAtt(r: Record<string, unknown>): AttachmentRow {
  return {
    id: String(r.id),
    task_id: String(r.task_id),
    name: String(r.name || ''),
    rel_path: String(r.rel_path || ''),
    mime: String(r.mime || ''),
    size: Number(r.size) || 0,
    created_at: String(r.created_at || ''),
    updated_at: String(r.updated_at || ''),
    deleted: r.deleted ? 1 : 0,
  };
}

export function listLists(): ListRow[] {
  const db = getDb();
  const out: ListRow[] = [];
  const stmt = db.prepare(
    'SELECT * FROM lists WHERE deleted = 0 ORDER BY sort_order ASC, created_at ASC',
  );
  while (stmt.step()) out.push(asList(stmt.getAsObject() as Record<string, unknown>));
  stmt.free();
  return out;
}

export function createList(title: string): ListRow {
  const db = getDb();
  const id = uuid();
  const t = nowIso();
  const maxStmt = db.prepare(
    'SELECT COALESCE(MAX(sort_order), -1) AS m FROM lists WHERE deleted = 0',
  );
  maxStmt.step();
  const m = Number((maxStmt.getAsObject() as { m: number }).m) + 1;
  maxStmt.free();
  db.run(
    'INSERT INTO lists (id, title, sort_order, created_at, updated_at, deleted) VALUES (?,?,?,?,?,0)',
    [id, title.trim() || '新列表', m, t, t],
  );
  schedulePersist();
  return {
    id,
    title: title.trim() || '新列表',
    sort_order: m,
    created_at: t,
    updated_at: t,
    deleted: 0,
  };
}

export function renameList(id: string, title: string): void {
  const db = getDb();
  const t = nowIso();
  db.run('UPDATE lists SET title = ?, updated_at = ? WHERE id = ?', [
    title.trim() || '未命名',
    t,
    id,
  ]);
  schedulePersist();
}

export function deleteList(id: string): string {
  const db = getDb();
  const t = nowIso();
  db.run('UPDATE lists SET deleted = 1, updated_at = ? WHERE id = ?', [t, id]);
  db.run('UPDATE tasks SET deleted = 1, updated_at = ? WHERE list_id = ? AND deleted = 0', [
    t,
    id,
  ]);
  schedulePersist();
  return ensureDefaultList(db);
}

export function listTasks(listId: string): TaskRow[] {
  const db = getDb();
  const out: TaskRow[] = [];
  const stmt = db.prepare(
    'SELECT * FROM tasks WHERE list_id = ? AND deleted = 0 ORDER BY done ASC, sort_order ASC, created_at DESC',
  );
  stmt.bind([listId]);
  while (stmt.step()) out.push(asTask(stmt.getAsObject() as Record<string, unknown>));
  stmt.free();
  return out;
}

export function getTask(id: string): TaskRow | null {
  const db = getDb();
  const stmt = db.prepare('SELECT * FROM tasks WHERE id = ? AND deleted = 0');
  stmt.bind([id]);
  if (!stmt.step()) {
    stmt.free();
    return null;
  }
  const row = asTask(stmt.getAsObject() as Record<string, unknown>);
  stmt.free();
  return row;
}

export function createTask(listId: string, title: string): TaskRow {
  const db = getDb();
  const id = uuid();
  const t = nowIso();
  const maxStmt = db.prepare(
    'SELECT COALESCE(MAX(sort_order), -1) AS m FROM tasks WHERE list_id = ? AND deleted = 0',
  );
  maxStmt.bind([listId]);
  maxStmt.step();
  const m = Number((maxStmt.getAsObject() as { m: number }).m) + 1;
  maxStmt.free();
  const titleTrim = title.trim() || '新任务';
  db.run(
    `INSERT INTO tasks (id, list_id, title, note_json, done, due_at, remind_at, sort_order, created_at, updated_at, deleted)
     VALUES (?,?,?,'',0,NULL,NULL,?,?,?,0)`,
    [id, listId, titleTrim, m, t, t],
  );
  schedulePersist();
  return {
    id,
    list_id: listId,
    title: titleTrim,
    note_json: '',
    done: 0,
    due_at: null,
    remind_at: null,
    sort_order: m,
    created_at: t,
    updated_at: t,
    deleted: 0,
  };
}

export function updateTask(
  id: string,
  patch: Partial<{
    title: string;
    done: boolean;
    due_at: string | null;
    remind_at: string | null;
    note: OutputData | null;
  }>,
): void {
  const cur = getTask(id);
  if (!cur) return;
  const t = nowIso();
  const title = patch.title != null ? patch.title.trim() || cur.title : cur.title;
  const done = patch.done != null ? (patch.done ? 1 : 0) : cur.done;
  const due_at = patch.due_at !== undefined ? patch.due_at : cur.due_at;
  const remind_at = patch.remind_at !== undefined ? patch.remind_at : cur.remind_at;
  let note_json = cur.note_json;
  if (patch.note !== undefined) {
    note_json = patch.note ? JSON.stringify(patch.note) : '';
  }
  getDb().run(
    `UPDATE tasks SET title=?, done=?, due_at=?, remind_at=?, note_json=?, updated_at=? WHERE id=?`,
    [title, done, due_at, remind_at, note_json, t, id],
  );
  schedulePersist();
}

export function deleteTask(id: string): void {
  const t = nowIso();
  getDb().run('UPDATE tasks SET deleted = 1, updated_at = ? WHERE id = ?', [t, id]);
  getDb().run('UPDATE steps SET deleted = 1, updated_at = ? WHERE task_id = ?', [t, id]);
  getDb().run('UPDATE attachments SET deleted = 1, updated_at = ? WHERE task_id = ?', [
    t,
    id,
  ]);
  schedulePersist();
}

export function listSteps(taskId: string): StepRow[] {
  const out: StepRow[] = [];
  const stmt = getDb().prepare(
    'SELECT * FROM steps WHERE task_id = ? AND deleted = 0 ORDER BY sort_order ASC, created_at ASC',
  );
  stmt.bind([taskId]);
  while (stmt.step()) out.push(asStep(stmt.getAsObject() as Record<string, unknown>));
  stmt.free();
  return out;
}

export function createStep(taskId: string, title: string): StepRow {
  const db = getDb();
  const id = uuid();
  const t = nowIso();
  const maxStmt = db.prepare(
    'SELECT COALESCE(MAX(sort_order), -1) AS m FROM steps WHERE task_id = ? AND deleted = 0',
  );
  maxStmt.bind([taskId]);
  maxStmt.step();
  const m = Number((maxStmt.getAsObject() as { m: number }).m) + 1;
  maxStmt.free();
  const titleTrim = title.trim() || '步骤';
  db.run(
    'INSERT INTO steps (id, task_id, title, done, sort_order, created_at, updated_at, deleted) VALUES (?,?,?,?,?,?,?,0)',
    [id, taskId, titleTrim, 0, m, t, t],
  );
  schedulePersist();
  return {
    id,
    task_id: taskId,
    title: titleTrim,
    done: 0,
    sort_order: m,
    created_at: t,
    updated_at: t,
    deleted: 0,
  };
}

export function updateStep(
  id: string,
  patch: Partial<{ title: string; done: boolean }>,
): void {
  const db = getDb();
  const stmt = db.prepare('SELECT * FROM steps WHERE id = ? AND deleted = 0');
  stmt.bind([id]);
  if (!stmt.step()) {
    stmt.free();
    return;
  }
  const cur = asStep(stmt.getAsObject() as Record<string, unknown>);
  stmt.free();
  const t = nowIso();
  db.run('UPDATE steps SET title=?, done=?, updated_at=? WHERE id=?', [
    patch.title != null ? patch.title.trim() || cur.title : cur.title,
    patch.done != null ? (patch.done ? 1 : 0) : cur.done,
    t,
    id,
  ]);
  schedulePersist();
}

export function deleteStep(id: string): void {
  getDb().run('UPDATE steps SET deleted = 1, updated_at = ? WHERE id = ?', [
    nowIso(),
    id,
  ]);
  schedulePersist();
}

export function listAttachments(taskId: string): AttachmentRow[] {
  const out: AttachmentRow[] = [];
  const stmt = getDb().prepare(
    'SELECT * FROM attachments WHERE task_id = ? AND deleted = 0 ORDER BY created_at ASC',
  );
  stmt.bind([taskId]);
  while (stmt.step()) out.push(asAtt(stmt.getAsObject() as Record<string, unknown>));
  stmt.free();
  return out;
}

function safeFileName(name: string): string {
  return name.replace(/[/\\?%*:|"<>]/g, '_').slice(0, 120) || 'file';
}

export async function addAttachment(
  taskId: string,
  file: File,
  onProgress?: (r: number) => void,
): Promise<AttachmentRow> {
  const id = uuid();
  const t = nowIso();
  const fname = safeFileName(file.name);
  const rel = `attachments/${taskId}/${id}_${fname}`;
  setDataWatchPaused(true);
  try {
    await putDataFileWithProgress(rel, file, onProgress);
  } finally {
    setDataWatchPaused(false);
  }
  getDb().run(
    `INSERT INTO attachments (id, task_id, name, rel_path, mime, size, created_at, updated_at, deleted)
     VALUES (?,?,?,?,?,?,?,?,0)`,
    [id, taskId, file.name, rel, file.type || '', file.size, t, t],
  );
  schedulePersist();
  return {
    id,
    task_id: taskId,
    name: file.name,
    rel_path: rel,
    mime: file.type || '',
    size: file.size,
    created_at: t,
    updated_at: t,
    deleted: 0,
  };
}

export async function removeAttachment(att: AttachmentRow): Promise<void> {
  getDb().run('UPDATE attachments SET deleted = 1, updated_at = ? WHERE id = ?', [
    nowIso(),
    att.id,
  ]);
  schedulePersist();
  try {
    await deleteDataFile(att.rel_path);
  } catch (e) {
    console.warn('删除附件文件失败', e);
  }
}
