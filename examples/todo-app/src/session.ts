import {
  getDataBlob,
  putDataFile,
  setDataWatchPaused,
} from './datakeep';

const LIST_KEY = 'site.datakeep.todo.lastListId';
const TASK_KEY = 'site.datakeep.todo.lastTaskId';
const REL = 'ui-session.json';

export type TaskSortMode = 'created_desc' | 'created_asc' | 'manual';

export type Session = {
  listId: string | null;
  taskId: string | null;
  taskSort?: Record<string, TaskSortMode>;
};

const SORT_MODES: TaskSortMode[] = ['created_desc', 'created_asc', 'manual'];

export function isTaskSortMode(v: unknown): v is TaskSortMode {
  return v === 'created_desc' || v === 'created_asc' || v === 'manual';
}

export function nextTaskSortMode(cur: TaskSortMode): TaskSortMode {
  const i = SORT_MODES.indexOf(cur);
  return SORT_MODES[(i + 1) % SORT_MODES.length];
}

export function taskSortLabel(mode: TaskSortMode): string {
  if (mode === 'created_desc') return '按时间倒序';
  if (mode === 'created_asc') return '按时间正序';
  return '按拖拽排序';
}

export function loadSessionMemory(): Session {
  try {
    return {
      listId: localStorage.getItem(LIST_KEY),
      taskId: localStorage.getItem(TASK_KEY),
    };
  } catch {
    return { listId: null, taskId: null };
  }
}

function writeMemory(s: Session): void {
  try {
    if (s.listId) localStorage.setItem(LIST_KEY, s.listId);
    else localStorage.removeItem(LIST_KEY);
    if (s.taskId) localStorage.setItem(TASK_KEY, s.taskId);
    else localStorage.removeItem(TASK_KEY);
  } catch {
    /* ignore */
  }
}

function parseTaskSort(raw: unknown): Record<string, TaskSortMode> {
  if (!raw || typeof raw !== 'object') return {};
  const out: Record<string, TaskSortMode> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    if (isTaskSortMode(v)) out[k] = v;
  }
  return out;
}

export async function loadSession(): Promise<Session> {
  const mem = loadSessionMemory();
  try {
    const blob = await getDataBlob(REL);
    if (!blob) return mem;
    const j = JSON.parse(await blob.text()) as {
      listId?: unknown;
      taskId?: unknown;
      taskSort?: unknown;
    };
    const fileList = typeof j.listId === 'string' && j.listId ? j.listId : null;
    const fileTask = typeof j.taskId === 'string' && j.taskId ? j.taskId : null;
    return {
      listId: fileList ?? mem.listId,
      taskId: fileTask ?? mem.taskId,
      taskSort: parseTaskSort(j.taskSort),
    };
  } catch {
    return mem;
  }
}

let saveTimer: number | null = null;

export function saveSession(s: Session): void {
  writeMemory(s);
  if (saveTimer != null) window.clearTimeout(saveTimer);
  saveTimer = window.setTimeout(() => {
    saveTimer = null;
    void persistFile(s);
  }, 250);
}

async function persistFile(s: Session): Promise<void> {
  setDataWatchPaused(true);
  try {
    await putDataFile(REL, JSON.stringify(s));
  } catch (e) {
    console.warn('保存上次打开位置失败', e);
  } finally {
    setDataWatchPaused(false);
  }
}
