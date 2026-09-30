import {
  Checkbox,
  IconButton,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Stack,
  TextField,
} from '@mui/material';
import DeleteIcon from '@mui/icons-material/DeleteOutlineOutlined';
import { useState } from 'react';
import type { StepRow } from '../db/types';

type Props = {
  steps: StepRow[];
  onAdd: (title: string) => void;
  onToggle: (id: string, done: boolean) => void;
  onRename: (id: string, title: string) => void;
  onDelete: (id: string) => void;
};

export default function StepsEditor({
  steps,
  onAdd,
  onToggle,
  onRename,
  onDelete,
}: Props) {
  const [draft, setDraft] = useState('');

  const submit = () => {
    const t = draft.trim();
    if (!t) return;
    onAdd(t);
    setDraft('');
  };

  return (
    <Stack spacing={1}>
      <List dense disablePadding>
        {steps.map((s) => (
          <ListItem
            key={s.id}
            disablePadding
            secondaryAction={
              <IconButton edge="end" size="small" onClick={() => onDelete(s.id)}>
                <DeleteIcon fontSize="small" />
              </IconButton>
            }
            sx={{ pr: 5 }}
          >
            <ListItemIcon sx={{ minWidth: 36 }}>
              <Checkbox
                edge="start"
                size="small"
                checked={!!s.done}
                onChange={(_, c) => onToggle(s.id, c)}
              />
            </ListItemIcon>
            <ListItemText
              primary={
                <TextField
                  variant="standard"
                  fullWidth
                  size="small"
                  defaultValue={s.title}
                  onBlur={(e) => {
                    if (e.target.value.trim() !== s.title) {
                      onRename(s.id, e.target.value);
                    }
                  }}
                  slotProps={{
                    input: {
                      disableUnderline: true,
                      sx: {
                        textDecoration: s.done ? 'line-through' : 'none',
                        color: s.done ? 'text.secondary' : 'text.primary',
                      },
                    },
                  }}
                />
              }
            />
          </ListItem>
        ))}
      </List>
      <TextField
        size="small"
        placeholder="添加步骤"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            submit();
          }
        }}
      />
    </Stack>
  );
}
