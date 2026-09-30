import {
  Box,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  List,
  ListItem,
  ListItemButton,
  ListItemText,
  Menu,
  MenuItem,
  Stack,
  TextField,
  Button,
  Typography,
} from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import MoreVertIcon from '@mui/icons-material/MoreVert';
import { useState } from 'react';
import type { ListRow } from '../db/types';

type Props = {
  lists: ListRow[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onCreate: (title: string) => void;
  onRename: (id: string, title: string) => void;
  onDelete: (id: string) => void;
};

export default function ListNav({
  lists,
  selectedId,
  onSelect,
  onCreate,
  onRename,
  onDelete,
}: Props) {
  const [menuAnchor, setMenuAnchor] = useState<null | HTMLElement>(null);
  const [menuList, setMenuList] = useState<ListRow | null>(null);
  const [renameOpen, setRenameOpen] = useState(false);
  const [renameValue, setRenameValue] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [addValue, setAddValue] = useState('');

  const openMenu = (e: React.MouseEvent<HTMLElement>, list: ListRow) => {
    e.stopPropagation();
    setMenuAnchor(e.currentTarget);
    setMenuList(list);
  };

  const closeMenu = () => {
    setMenuAnchor(null);
  };

  const submitAdd = () => {
    const title = addValue;
    setAddOpen(false);
    setAddValue('');
    onCreate(title);
  };

  const submitRename = () => {
    if (!menuList) return;
    const id = menuList.id;
    const title = renameValue;
    setRenameOpen(false);
    setRenameValue('');
    setMenuList(null);
    onRename(id, title);
  };

  return (
    <Box
      sx={{
        width: 240,
        flexShrink: 0,
        borderRight: 1,
        borderColor: 'divider',
        bgcolor: 'background.paper',
        display: 'flex',
        flexDirection: 'column',
        height: '100%',
      }}
    >
      <Stack
        direction="row"
        spacing={1}
        sx={{ px: 2, py: 1.5, alignItems: 'center', justifyContent: 'space-between' }}
      >
        <Typography variant="subtitle1" sx={{ fontWeight: 600 }}>
          列表
        </Typography>
        <IconButton
          size="small"
          aria-label="新建列表"
          onClick={() => {
            setAddValue('');
            setAddOpen(true);
          }}
        >
          <AddIcon />
        </IconButton>
      </Stack>
      <List dense sx={{ flex: 1, overflow: 'auto', py: 0 }}>
        {lists.map((l) => (
          <ListItem
            key={l.id}
            disablePadding
            secondaryAction={
              <IconButton edge="end" size="small" onClick={(e) => openMenu(e, l)}>
                <MoreVertIcon fontSize="small" />
              </IconButton>
            }
          >
            <ListItemButton
              selected={l.id === selectedId}
              onClick={() => onSelect(l.id)}
              sx={{ pr: 6 }}
            >
              <ListItemText primary={l.title} />
            </ListItemButton>
          </ListItem>
        ))}
      </List>

      <Menu anchorEl={menuAnchor} open={!!menuAnchor} onClose={closeMenu}>
        <MenuItem
          onClick={() => {
            if (menuList) {
              setRenameValue(menuList.title);
              setRenameOpen(true);
            }
            closeMenu();
          }}
        >
          重命名
        </MenuItem>
        <MenuItem
          onClick={() => {
            if (menuList) onDelete(menuList.id);
            closeMenu();
          }}
        >
          删除
        </MenuItem>
      </Menu>

      <Dialog
        open={addOpen}
        onClose={() => {
          setAddOpen(false);
          setAddValue('');
        }}
        fullWidth
        maxWidth="xs"
      >
        <DialogTitle>新建列表</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="名称"
            value={addValue}
            onChange={(e) => setAddValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                submitAdd();
              }
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button
            type="button"
            onClick={() => {
              setAddOpen(false);
              setAddValue('');
            }}
          >
            取消
          </Button>
          <Button type="button" variant="contained" onClick={submitAdd}>
            创建
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog
        open={renameOpen}
        onClose={() => {
          setRenameOpen(false);
          setRenameValue('');
        }}
        fullWidth
        maxWidth="xs"
      >
        <DialogTitle>重命名列表</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            fullWidth
            margin="dense"
            label="名称"
            value={renameValue}
            onChange={(e) => setRenameValue(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                submitRename();
              }
            }}
          />
        </DialogContent>
        <DialogActions>
          <Button
            type="button"
            onClick={() => {
              setRenameOpen(false);
              setRenameValue('');
            }}
          >
            取消
          </Button>
          <Button type="button" variant="contained" onClick={submitRename}>
            保存
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
