import { Box, Button, IconButton, Stack, Typography } from '@mui/material';
import DeleteIcon from '@mui/icons-material/DeleteOutlineOutlined';
import { useRef, useState } from 'react';
import type { OutputData } from '@editorjs/editorjs';
import { formatCreatedAt, type CommentRow } from '../db/types';
import { commentToOutput, isOutputEmpty } from '../editorData';
import EditorBlocks from './EditorBlocks';
import NoteEditor from './NoteEditor';

type Props = {
  taskId: string;
  comments: CommentRow[];
  onAdd: (data: OutputData) => void;
  onDelete: (id: string) => void;
};

export default function CommentsPanel({ taskId, comments, onAdd, onDelete }: Props) {
  const [composerKey, setComposerKey] = useState(0);
  const saveRef = useRef<(() => Promise<OutputData>) | null>(null);
  const busyRef = useRef(false);
  const [posting, setPosting] = useState(false);

  const submit = async () => {
    if (!saveRef.current || busyRef.current) return;
    setPosting(true);
    try {
      const data = await saveRef.current();
      if (isOutputEmpty(data)) return;
      onAdd(data);
      saveRef.current = null;
      setComposerKey((k) => k + 1);
    } catch (e) {
      console.error(e);
      window.alert(e instanceof Error ? e.message : '发表评论失败');
    } finally {
      setPosting(false);
    }
  };

  return (
    <Stack spacing={1.5}>
      <Typography variant="subtitle2" color="text.secondary">
        评论
      </Typography>
      {comments.map((c) => (
        <Box
          key={c.id}
          sx={{
            bgcolor: 'action.hover',
            borderRadius: 1,
            px: 1.5,
            py: 1,
          }}
        >
          <Stack direction="row" sx={{ alignItems: 'flex-start' }}>
            <Box sx={{ flex: 1, minWidth: 0 }}>
              <EditorBlocks data={commentToOutput(c.body, c.images)} />
              <Typography variant="caption" color="text.secondary">
                {formatCreatedAt(c.created_at)}
              </Typography>
            </Box>
            <IconButton size="small" aria-label="删除评论" onClick={() => onDelete(c.id)}>
              <DeleteIcon fontSize="small" />
            </IconButton>
          </Stack>
        </Box>
      ))}
      <NoteEditor
        key={`${taskId}:${composerKey}`}
        taskId={taskId}
        imageKind="comment"
        placeholder="写下评论…可插入图片"
        minHeight={100}
        onBusy={(busy) => {
          busyRef.current = busy;
        }}
        onReady={(api) => {
          saveRef.current = api.save;
        }}
      />
      <Button
        variant="outlined"
        size="small"
        disabled={posting}
        onClick={() => void submit()}
        sx={{ alignSelf: 'flex-end' }}
      >
        发表评论
      </Button>
    </Stack>
  );
}
