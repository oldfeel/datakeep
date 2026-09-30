import {
  Box,
  Button,
  Checkbox,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Stack,
  TextField,
  Typography,
} from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import { useState } from 'react';
import { formatCreatedAt } from '../db/types';
import type { TaskRow } from '../db/types';

type Props = {
  listTitle: string;
  tasks: TaskRow[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onToggleDone: (id: string, done: boolean) => void;
  onAdd: (title: string) => void;
};

export default function TaskList({
  listTitle,
  tasks,
  selectedId,
  onSelect,
  onToggleDone,
  onAdd,
}: Props) {
  const [draft, setDraft] = useState('');
  const [showInput, setShowInput] = useState(false);

  const submit = () => {
    const t = draft.trim();
    if (!t) return;
    onAdd(t);
    setDraft('');
    setShowInput(false);
  };

  return (
    <Box
      sx={{
        flex: 1,
        minWidth: 0,
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
        bgcolor: 'background.default',
      }}
    >
      <Box sx={{ px: 3, pt: 2.5, pb: 1.5 }}>
        <Typography variant="h5" sx={{ mb: 1.5, fontWeight: 700 }}>
          {listTitle || '列表'}
        </Typography>
        {!showInput ? (
          <Button
            startIcon={<AddIcon />}
            variant="outlined"
            onClick={() => setShowInput(true)}
          >
            添加任务
          </Button>
        ) : (
          <Stack direction="row" spacing={1}>
            <TextField
              autoFocus
              size="small"
              fullWidth
              placeholder="任务标题"
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  submit();
                } else if (e.key === 'Escape') {
                  setShowInput(false);
                  setDraft('');
                }
              }}
            />
            <Button variant="contained" onClick={submit}>
              添加
            </Button>
            <Button
              onClick={() => {
                setShowInput(false);
                setDraft('');
              }}
            >
              取消
            </Button>
          </Stack>
        )}
      </Box>
      <List sx={{ flex: 1, overflow: 'auto', px: 1 }}>
        {tasks.map((task) => (
          <ListItemButton
            key={task.id}
            selected={task.id === selectedId}
            onClick={() => onSelect(task.id)}
            sx={{
              borderRadius: 1,
              mb: 0.5,
              bgcolor: 'background.paper',
              alignItems: 'flex-start',
            }}
          >
            <ListItemIcon sx={{ minWidth: 40, pt: 0.5 }}>
              <Checkbox
                edge="start"
                checked={!!task.done}
                onClick={(e) => e.stopPropagation()}
                onChange={(_, c) => onToggleDone(task.id, c)}
              />
            </ListItemIcon>
            <ListItemText
              primary={
                <Typography
                  sx={{
                    textDecoration: task.done ? 'line-through' : 'none',
                    color: task.done ? 'text.secondary' : 'text.primary',
                  }}
                >
                  {task.title}
                </Typography>
              }
              secondary={
                <Typography variant="caption" color="text.secondary">
                  创建于 {formatCreatedAt(task.created_at)}
                </Typography>
              }
            />
          </ListItemButton>
        ))}
        {!tasks.length && (
          <Typography
            variant="body2"
            color="text.secondary"
            sx={{ px: 2, py: 4, textAlign: 'center' }}
          >
            暂无任务，点击上方按钮添加
          </Typography>
        )}
      </List>
    </Box>
  );
}
