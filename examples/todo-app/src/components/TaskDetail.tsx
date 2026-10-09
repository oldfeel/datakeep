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
import type { CommentRow, TaskRow } from '../db/types';
import { formatCreatedAt } from '../db/types';
import NoteEditor from './NoteEditor';
import CommentsPanel from './Comments';

type Props = {
  task: TaskRow;
  comments: CommentRow[];
  onClose: () => void;
  onPatch: (patch: { title?: string; note?: OutputData | null }) => void | Promise<void>;
  onDelete: () => void;
  onAddComment: (data: OutputData) => void;
  onDeleteComment: (id: string) => void;
};

export default function TaskDetail({
  task,
  comments,
  onClose,
  onPatch,
  onDelete,
  onAddComment,
  onDeleteComment,
}: Props) {
  const [title, setTitle] = useState(task.title);
  const saveNoteRef = useRef<(() => Promise<OutputData>) | null>(null);
  const noteBusyRef = useRef(false);
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
              sx: {
                typography: 'h6',
                fontWeight: 600,
                '&:before': { borderBottom: '1.5px solid rgba(0,0,0,0.42)' },
                '&:hover:not(.Mui-disabled):before': {
                  borderBottom: '2px solid #2564cf',
                },
              },
            },
          }}
          sx={{ mb: 2 }}
        />

        <Typography variant="subtitle2" color="text.secondary" sx={{ mb: 0.5 }}>
          备注
        </Typography>
        <Box
          onBlur={() => {
            if (noteBusyRef.current) return;
            void flushNote();
          }}
        >
          <NoteEditor
            key={noteKey}
            taskId={task.id}
            initial={initialNote}
            onBusy={(busy) => {
              noteBusyRef.current = busy;
            }}
            onImageUploaded={() => void flushNote()}
            onReady={(api) => {
              saveNoteRef.current = api.save;
            }}
          />
        </Box>

        <Divider sx={{ my: 2 }} />

        <CommentsPanel
          taskId={task.id}
          comments={comments}
          onAdd={onAddComment}
          onDelete={onDeleteComment}
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
