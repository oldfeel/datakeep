import {
  Box,
  Button,
  Checkbox,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TableSortLabel,
  TextField,
  Typography,
} from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import DragIndicatorIcon from '@mui/icons-material/DragIndicator';
import { useMemo, useRef, useState } from 'react';
import { formatCreatedAt } from '../db/types';
import type { TaskRow } from '../db/types';
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
import {
  nextTaskSortMode,
  taskSortLabel,
  type TaskSortMode,
} from '../session';
import DragGhost from './DragGhost';

type Props = {
  listTitle: string;
  tasks: TaskRow[];
  selectedId: string | null;
  sortMode: TaskSortMode;
  onSortMode: (mode: TaskSortMode) => void;
  onReorder: (ids: string[]) => void;
  onSelect: (id: string) => void;
  onToggleDone: (id: string, done: boolean) => void;
  onAdd: (title: string) => void;
};

function sortTasks(tasks: TaskRow[], mode: TaskSortMode): TaskRow[] {
  const cmp = (a: TaskRow, b: TaskRow) => {
    if (mode === 'created_desc') {
      return String(b.created_at).localeCompare(String(a.created_at));
    }
    if (mode === 'created_asc') {
      return String(a.created_at).localeCompare(String(b.created_at));
    }
    return a.sort_order - b.sort_order || a.created_at.localeCompare(b.created_at);
  };
  const open = tasks.filter((t) => !t.done).sort(cmp);
  const done = tasks.filter((t) => !!t.done).sort(cmp);
  return [...open, ...done];
}

export default function TaskList({
  listTitle,
  tasks,
  selectedId,
  sortMode,
  onSortMode,
  onReorder,
  onSelect,
  onToggleDone,
  onAdd,
}: Props) {
  const [draft, setDraft] = useState('');
  const [showInput, setShowInput] = useState(false);
  const dragIdRef = useRef<string | null>(null);
  const ghostRef = useRef<GhostHandle>(null);
  const dragElRef = useRef<HTMLElement | null>(null);
  const skipClick = useRef(false);
  const pendingRef = useRef<{ toId: string; place: DropPlace } | null>(null);
  const rowsRef = useRef<TaskRow[]>([]);
  const onReorderRef = useRef(onReorder);
  const onSortModeRef = useRef(onSortMode);
  onReorderRef.current = onReorder;
  onSortModeRef.current = onSortMode;

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
      skipClick.current = true;
      const cur = rowsRef.current;
      const next = applyDropById(cur, from, pending.toId, pending.place);
      if (next !== cur) {
        onReorderRef.current(next.map((x) => x.id));
        onSortModeRef.current('manual');
      }
    }
    pendingRef.current = null;
    dragIdRef.current = null;
    clearVisual();
  };
  useCefDragAllow(() => !!dragIdRef.current, finishDrag, cancelDrag);

  const rows = useMemo(() => sortTasks(tasks, sortMode), [tasks, sortMode]);
  rowsRef.current = rows;

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
      <TableContainer sx={{ flex: 1, overflow: 'auto', px: 1, pb: 1 }}>
        <Table
          stickyHeader
          size="small"
          sx={{
            width: '100%',
            tableLayout: 'fixed',
            '& th, & td': { boxSizing: 'border-box', verticalAlign: 'middle' },
          }}
        >
          <colgroup>
            <col />
            <col style={{ width: 148 }} />
          </colgroup>
          <TableHead>
            <TableRow>
              <TableCell sx={{ fontWeight: 700, bgcolor: 'background.paper', pl: 1.5 }}>
                任务
              </TableCell>
              <TableCell
                sx={{
                  width: 148,
                  fontWeight: 700,
                  cursor: 'pointer',
                  userSelect: 'none',
                  bgcolor: 'background.paper',
                }}
                onClick={() => onSortMode(nextTaskSortMode(sortMode))}
                title="点击切换排序"
              >
                <TableSortLabel
                  active={sortMode !== 'manual'}
                  direction={sortMode === 'created_asc' ? 'asc' : 'desc'}
                  hideSortIcon={sortMode === 'manual'}
                  sx={{ pointerEvents: 'none' }}
                >
                  创建时间
                </TableSortLabel>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                  {taskSortLabel(sortMode)}
                </Typography>
              </TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {rows.map((task) => {
              const selected = task.id === selectedId;
              return (
                <TableRow
                  key={task.id}
                  hover
                  selected={selected}
                  onDragOver={(ev) => {
                    ev.preventDefault();
                    ev.dataTransfer.dropEffect = 'move';
                    if (!dragIdRef.current || dragIdRef.current === task.id) {
                      if (dragIdRef.current === task.id) {
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
                    pendingRef.current = { toId: task.id, place };
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
                    pendingRef.current = { toId: task.id, place };
                    finishDrag();
                  }}
                  onClick={() => {
                    if (skipClick.current) {
                      skipClick.current = false;
                      return;
                    }
                    onSelect(task.id);
                  }}
                  sx={{
                    cursor: 'default',
                    bgcolor: 'background.paper',
                    '&.Mui-selected': {
                      bgcolor: 'rgba(37, 100, 207, 0.22)',
                      boxShadow: 'inset 4px 0 0 #2564cf',
                    },
                    '&.Mui-selected:hover': {
                      bgcolor: 'rgba(37, 100, 207, 0.32)',
                    },
                  }}
                >
                  <TableCell sx={{ py: 0.5, pl: 1, pr: 1 }}>
                    <Box
                      sx={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: 0.75,
                        minWidth: 0,
                        width: '100%',
                      }}
                    >
                      <Box
                        draggable
                        onDragStart={(ev) => {
                          ev.stopPropagation();
                          setCefDragData(ev, task.id);
                          dragIdRef.current = task.id;
                          pendingRef.current = null;
                          const row = ev.currentTarget.closest('tr');
                          dragElRef.current = row;
                          if (row) row.style.opacity = '0.45';
                          ghostRef.current?.show(task.title, selected, ev.clientX, ev.clientY);
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
                          flexShrink: 0,
                          '&:active': { cursor: 'grabbing' },
                        }}
                      >
                        <DragIndicatorIcon fontSize="small" sx={{ opacity: 0.55 }} />
                      </Box>
                      <Checkbox
                        size="small"
                        checked={!!task.done}
                        onClick={(e) => e.stopPropagation()}
                        onChange={(_, c) => onToggleDone(task.id, c)}
                        sx={{ p: 0, flexShrink: 0 }}
                      />
                      <Typography
                        noWrap
                        sx={{
                          flex: 1,
                          minWidth: 0,
                          textDecoration: task.done ? 'line-through' : 'none',
                          color: task.done ? 'text.secondary' : 'text.primary',
                        }}
                      >
                        {task.title}
                      </Typography>
                    </Box>
                  </TableCell>
                  <TableCell sx={{ overflow: 'hidden', whiteSpace: 'nowrap' }}>
                    <Typography variant="body2" color="text.secondary" noWrap>
                      {formatCreatedAt(task.created_at)}
                    </Typography>
                  </TableCell>
                </TableRow>
              );
            })}
            {!rows.length && (
              <TableRow>
                <TableCell colSpan={2}>
                  <Typography
                    variant="body2"
                    color="text.secondary"
                    sx={{ py: 4, textAlign: 'center' }}
                  >
                    暂无任务，点击上方按钮添加
                  </Typography>
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </TableContainer>
      <DragGhost handleRef={ghostRef} />
    </Box>
  );
}
