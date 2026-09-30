export function uuid(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function todayIsoDate(): string {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** 本地时区短可读时间 */
export function formatCreatedAt(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    const now = new Date();
    const sameDay =
      d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() &&
      d.getDate() === now.getDate();
    if (sameDay) {
      return d.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
    }
    const sameYear = d.getFullYear() === now.getFullYear();
    if (sameYear) {
      return d.toLocaleString('zh-CN', {
        month: 'numeric',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });
    }
    return d.toLocaleString('zh-CN', {
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  } catch {
    return iso;
  }
}

export type ListRow = {
  id: string;
  title: string;
  sort_order: number;
  created_at: string;
  updated_at: string;
  deleted: number;
};

export type TaskRow = {
  id: string;
  list_id: string;
  title: string;
  note_json: string;
  done: number;
  due_at: string | null;
  remind_at: string | null;
  sort_order: number;
  created_at: string;
  updated_at: string;
  deleted: number;
};

export type StepRow = {
  id: string;
  task_id: string;
  title: string;
  done: number;
  sort_order: number;
  created_at: string;
  updated_at: string;
  deleted: number;
};

export type AttachmentRow = {
  id: string;
  task_id: string;
  name: string;
  rel_path: string;
  mime: string;
  size: number;
  created_at: string;
  updated_at: string;
  deleted: number;
};
