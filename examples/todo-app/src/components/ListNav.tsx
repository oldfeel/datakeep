import {
  Box,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  IconButton,
  List,
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
import DragIndicatorIcon from '@mui/icons-material/DragIndicator';
import { useRef, useState } from 'react';
import type { ListRow } from '../db/types';
import {
  applyDropById,
  clearDropPaint,
  dropPlaceFromRect,
  paintDropTarget,
  setCefDragData,
  useCefDragAllow,
  type DropPlace,
  type GhostHandle,
} from '../dnd';
import DragGhost from './DragGhost';

type Props = {
  lists: ListRow[];
  selectedId: string | null;
  onSelect: (id: string) => void;
  onCreate: (title: string) => void;
  onRename: (id: string, title: string) => void;
  onDelete: (id: string) => void;
  onReorder: (ids: string[]) => void;
};

export default function ListNav({
  lists,
  selectedId,
  onSelect,
  onCreate,
  onRename,
  onDelete,
  onReorder,
}: Props) {
  const [menuAnchor, setMenuAnchor] = useState<null | HTMLElement>(null);
  const [menuList, setMenuList] = useState<ListRow | null>(null);
  const [renameOpen, setRenameOpen] = useState(false);
  const [renameValue, setRenameValue] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [addValue, setAddValue] = useState('');
  const dragIdRef = useRef<string | null>(null);
  const ghostRef = useRef<GhostHandle>(null);
  const dragElRef = useRef<HTMLElement | null>(null);
  const pendingRef = useRef<{ toId: string; place: DropPlace } | null>(null);
  const listsRef = useRef(lists);
  listsRef.current = lists;
  const onReorderRef = useRef(onReorder);
  onReorderRef.current = onReorder;

  const clearVisual = () => {
    if (dragElRef.current) dragElRef.current.style.opacity = '';
    dragElRef.current = null;
    ghostRef.current?.hide();
    clearDropPaint();
  };

  const cancelDrag = () => {
    pendingRef.current = null;
    dragIdRef.current = null;
    clearVisual();
  };

  const finishDrag = () => {
    const from = dragIdRef.current;
    const pending = pendingRef.current;
    if (from && pending && from !== pending.toId) {
      const cur = listsRef.current;
      const next = applyDropById(cur, from, pending.toId, pending.place);
      if (next !== cur) onReorderRef.current(next.map((x) => x.id));
    }
    pendingRef.current = null;
    dragIdRef.current = null;
    clearVisual();
  };
  useCefDragAllow(() => !!dragIdRef.current, finishDrag, cancelDrag);

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
          <ListItemButton
            key={l.id}
            selected={l.id === selectedId}
            onClick={() => onSelect(l.id)}
            onDragOver={(ev) => {
              ev.preventDefault();
              ev.dataTransfer.dropEffect = 'move';
              if (!dragIdRef.current || dragIdRef.current === l.id) {
                if (dragIdRef.current === l.id) {
                  pendingRef.current = null;
                  clearDropPaint();
                }
                return;
              }
              const place = dropPlaceFromRect(
                ev.currentTarget.getBoundingClientRect(),
                ev.clientX,
                ev.clientY,
              );
              pendingRef.current = { toId: l.id, place };
              paintDropTarget(ev.currentTarget, place);
            }}
            onDrop={(ev) => {
              ev.preventDefault();
              ev.stopPropagation();
              const place = dropPlaceFromRect(
                ev.currentTarget.getBoundingClientRect(),
                ev.clientX,
                ev.clientY,
              );
              pendingRef.current = { toId: l.id, place };
              finishDrag();
            }}
            sx={{
              pr: 0.5,
              mx: 0.5,
              borderRadius: 1,
              cursor: 'default',
              '&.Mui-selected': {
                bgcolor: 'rgba(37, 100, 207, 0.22)',
                boxShadow: 'inset 4px 0 0 #2564cf',
              },
              '&.Mui-selected:hover': {
                bgcolor: 'rgba(37, 100, 207, 0.32)',
              },
            }}
          >
            <Box
              draggable
              onClick={(e) => e.stopPropagation()}
              onDragStart={(ev) => {
                ev.stopPropagation();
                setCefDragData(ev, l.id);
                dragIdRef.current = l.id;
                pendingRef.current = null;
                const row = ev.currentTarget.parentElement;
                dragElRef.current = row;
                if (row) row.style.opacity = '0.45';
                ghostRef.current?.show(l.title, l.id === selectedId, ev.clientX, ev.clientY);
              }}
              onDrag={(ev) => {
                if (ev.clientX === 0 && ev.clientY === 0) return;
                ghostRef.current?.move(ev.clientX, ev.clientY);
              }}
              onDragEnd={finishDrag}
              sx={{
                display: 'flex',
                alignItems: 'center',
                cursor: 'grab',
                mr: 0.5,
                flexShrink: 0,
                '&:active': { cursor: 'grabbing' },
              }}
            >
              <DragIndicatorIcon fontSize="small" sx={{ opacity: 0.55 }} />
            </Box>
            <ListItemText primary={l.title} />
            <IconButton
              size="small"
              aria-label="列表菜单"
              onClick={(e) => openMenu(e, l)}
              sx={{ ml: 0.25, color: 'inherit', opacity: 0.85 }}
            >
              <MoreVertIcon fontSize="small" />
            </IconButton>
          </ListItemButton>
        ))}
      </List>
      <DragGhost handleRef={ghostRef} />

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
