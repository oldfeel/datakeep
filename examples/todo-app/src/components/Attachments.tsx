import {
  Box,
  Button,
  IconButton,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  Stack,
  Typography,
} from '@mui/material';
import DeleteIcon from '@mui/icons-material/DeleteOutlineOutlined';
import AttachFileIcon from '@mui/icons-material/AttachFile';
import ImageIcon from '@mui/icons-material/Image';
import { useRef, useState } from 'react';
import { dataUrl } from '../datakeep';
import type { AttachmentRow } from '../db/types';

type Props = {
  items: AttachmentRow[];
  onAdd: (files: FileList) => Promise<void>;
  onRemove: (att: AttachmentRow) => Promise<void>;
};

function isImage(mime: string, name: string): boolean {
  if (mime.startsWith('image/')) return true;
  return /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(name);
}

export default function AttachmentsPanel({ items, onAdd, onRemove }: Props) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<string>('');

  const pick = () => inputRef.current?.click();

  const onChange = async (ev: React.ChangeEvent<HTMLInputElement>) => {
    const files = ev.target.files;
    ev.target.value = '';
    if (!files?.length) return;
    setBusy(true);
    setProgress('上传中…');
    try {
      await onAdd(files);
    } finally {
      setBusy(false);
      setProgress('');
    }
  };

  return (
    <Box>
      <Stack direction="row" spacing={1} sx={{ mb: 1, alignItems: 'center' }}>
        <Typography variant="subtitle2" color="text.secondary">
          附件
        </Typography>
        <Button
          size="small"
          startIcon={<AttachFileIcon />}
          onClick={pick}
          disabled={busy}
        >
          添加
        </Button>
        {progress && (
          <Typography variant="caption" color="text.secondary">
            {progress}
          </Typography>
        )}
        <input
          ref={inputRef}
          type="file"
          multiple
          hidden
          onChange={onChange}
        />
      </Stack>
      <List dense disablePadding>
        {items.map((a) => (
          <ListItem
            key={a.id}
            secondaryAction={
              <IconButton edge="end" aria-label="删除" onClick={() => void onRemove(a)}>
                <DeleteIcon fontSize="small" />
              </IconButton>
            }
            sx={{ pr: 6 }}
          >
            <ListItemIcon sx={{ minWidth: 40 }}>
              {isImage(a.mime, a.name) ? (
                <Box
                  component="img"
                  src={dataUrl(a.rel_path)}
                  alt=""
                  sx={{ width: 32, height: 32, objectFit: 'cover', borderRadius: 0.5 }}
                />
              ) : a.mime.startsWith('image/') ? (
                <ImageIcon fontSize="small" />
              ) : (
                <AttachFileIcon fontSize="small" />
              )}
            </ListItemIcon>
            <ListItemText
              primary={
                <Typography
                  component="a"
                  href={dataUrl(a.rel_path)}
                  target="_blank"
                  rel="noreferrer"
                  variant="body2"
                  sx={{ color: 'primary.main', textDecoration: 'none' }}
                >
                  {a.name}
                </Typography>
              }
              secondary={a.size > 0 ? `${Math.round(a.size / 1024)} KB` : undefined}
            />
          </ListItem>
        ))}
      </List>
    </Box>
  );
}
