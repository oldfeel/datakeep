import {
  Box,
  Button,
  Divider,
  IconButton,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import CloseIcon from '@mui/icons-material/Close';
import DeleteIcon from '@mui/icons-material/DeleteOutlineOutlined';
import { useEffect, useRef, useState } from 'react';
import type { OutputData } from '@editorjs/editorjs';
import type { AttachmentRow, StepRow, TaskRow } from '../db/types';
import { formatCreatedAt } from '../db/types';
import NoteEditor from './NoteEditor';
import StepsEditor from './StepsEditor';
import AttachmentsPanel from './Attachments';

type Props = {
  task: TaskRow;
  steps: StepRow[];
  attachments: AttachmentRow[];
  onClose: () => void;
  onPatch: (patch: {
    title?: string;
    due_at?: string | null;
    remind_at?: string | null;
    note?: OutputData | null;
  }) => void | Promise<void>;
  onDelete: () => void;
  onAddStep: (title: string) => void;
  onToggleStep: (id: string, done: boolean) => void;
  onRenameStep: (id: string, title: string) => void;
  onDeleteStep: (id: string) => void;
  onAddFiles: (files: FileList) => Promise<void>;
  onRemoveAtt: (att: AttachmentRow) => Promise<void>;
};

function toDateInput(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso.slice(0, 10);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function toDateTimeLocal(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  const h = String(d.getHours()).padStart(2, '0');
  const min = String(d.getMinutes()).padStart(2, '0');
  return `${y}-${m}-${day}T${h}:${min}`;
}

function fromDateInput(v: string): string | null {
  if (!v) return null;
  return new Date(v + 'T00:00:00').toISOString();
}

function fromDateTimeLocal(v: string): string | null {
  if (!v) return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

export default function TaskDetail({
  task,
  steps,
  attachments,
  onClose,
  onPatch,
  onDelete,
  onAddStep,
  onToggleStep,
  onRenameStep,
  onDeleteStep,
  onAddFiles,
  onRemoveAtt,
}: Props) {
  const [title, setTitle] = useState(task.title);
  const saveNoteRef = useRef<(() => Promise<OutputData>) | null>(null);
  const noteKey = `${task.id}:${task.note_json.length}`;

  useEffect(() => {
    setTitle(task.title);
  }, [task.id, task.title]);

  const flushNote = async () => {
    if (!saveNoteRef.current) return;
    try {
      const data = await saveNoteRef.current();
      await onPatch({ note: data });
    } catch (e) {
      console.warn('保存备注失败', e);
    }
  };

  let initialNote: OutputData | null = null;
  try {
    if (task.note_json) {
      const o = JSON.parse(task.note_json) as OutputData;
      if (o && Array.isArray(o.blocks)) initialNote = o;
    }
  } catch {
    /* ignore */
  }

  return (
    <Box
      sx={{
        width: { xs: '100%', md: 360 },
        flexShrink: 0,
        borderLeft: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <Stack
        direction="row"
        sx={{ px: 1, py: 0.5, alignItems: 'center', justifyContent: 'space-between' }}
      >
        <Typography variant="caption" color="text.secondary" sx={{ pl: 1 }}>
          创建于 {formatCreatedAt(task.created_at)}
        </Typography>
        <IconButton aria-label="关闭" onClick={onClose}>
          <CloseIcon />
        </IconButton>
      </Stack>
      <Box sx={{ px: 2, pb: 2, flex: 1, overflow: 'auto' }}>
        <TextField
          fullWidth
          multiline
          variant="standard"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onBlur={() => {
            if (title.trim() && title.trim() !== task.title) {
              void onPatch({ title: title.trim() });
            } else {
              setTitle(task.title);
            }
          }}
          slotProps={{
            input: {
              disableUnderline: true,
              sx: { typography: 'h6', fontWeight: 600 },
            },
          }}
          sx={{ mb: 2 }}
        />

        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 0.5 }}>
          步骤
        </Typography>
        <StepsEditor
          steps={steps}
          onAdd={onAddStep}
          onToggle={onToggleStep}
          onRename={onRenameStep}
          onDelete={onDeleteStep}
        />

        <Divider sx={{ my: 2 }} />

        <Stack spacing={1.5}>
          <TextField
            label="截止日期"
            type="date"
            size="small"
            slotProps={{ inputLabel: { shrink: true } }}
            value={toDateInput(task.due_at)}
            onChange={(e) => void onPatch({ due_at: fromDateInput(e.target.value) })}
          />
          <TextField
            label="提醒"
            type="datetime-local"
            size="small"
            slotProps={{ inputLabel: { shrink: true } }}
            value={toDateTimeLocal(task.remind_at)}
            onChange={(e) =>
              void onPatch({ remind_at: fromDateTimeLocal(e.target.value) })
            }
          />
        </Stack>

        <Divider sx={{ my: 2 }} />

        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 0.5 }}>
          备注
        </Typography>
        <Box onBlur={() => void flushNote()}>
          <NoteEditor
            key={noteKey}
            initial={initialNote}
            onReady={(api) => {
              saveNoteRef.current = api.save;
            }}
          />
        </Box>

        <Divider sx={{ my: 2 }} />

        <AttachmentsPanel
          items={attachments}
          onAdd={onAddFiles}
          onRemove={onRemoveAtt}
        />

        <Button
          color="error"
          startIcon={<DeleteIcon />}
          sx={{ mt: 3 }}
          onClick={onDelete}
        >
          删除任务
        </Button>
      </Box>
    </Box>
  );
}
