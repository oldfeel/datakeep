import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert,
  Box,
  CircularProgress,
  Drawer,
  Snackbar,
  ThemeProvider,
  CssBaseline,
  useMediaQuery,
} from '@mui/material';
import { theme } from './theme';
import { watchData } from './datakeep';
import { openDatabase, setPersistErrorHandler } from './db/sql';
import { mergeConflictDatabases } from './db/merge';
import * as repo from './db/repo';
import type { CommentRow, ListRow, TaskRow } from './db/types';
import ListNav from './components/ListNav';
import TaskList from './components/TaskList';
import TaskDetail from './components/TaskDetail';
import { loadSession, saveSession, type TaskSortMode } from './session';

export default function App() {
  const narrow = useMediaQuery('(max-width:900px)');
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [snack, setSnack] = useState<string | null>(null);
  const [lists, setLists] = useState<ListRow[]>([]);
  const [listId, setListId] = useState<string | null>(null);
  const [tasks, setTasks] = useState<TaskRow[]>([]);
  const [taskId, setTaskId] = useState<string | null>(null);
  const [comments, setComments] = useState<CommentRow[]>([]);
  const [taskSort, setTaskSort] = useState<Record<string, TaskSortMode>>({});

  const refreshLists = useCallback(() => {
    const ls = repo.listLists();
    setLists(ls);
    return ls;
  }, []);

  const refreshTasks = useCallback((lid: string | null) => {
    if (!lid) {
      setTasks([]);
      return;
    }
    setTasks(repo.listTasks(lid));
  }, []);

  const refreshDetail = useCallback((tid: string | null) => {
    if (!tid) {
      setComments([]);
      return;
    }
    setComments(repo.listComments(tid));
  }, []);

  const reloadAll = useCallback(async () => {
    try {
      await mergeConflictDatabases();
    } catch (e) {
      console.warn(e);
    }
    const ls = refreshLists();
    setListId((prev) => {
      if (prev && ls.some((l) => l.id === prev)) return prev;
      return ls[0]?.id ?? null;
    });
  }, [refreshLists]);

  useEffect(() => {
    let cancelled = false;
    setPersistErrorHandler((e) => setSnack(e.message));
    (async () => {
      try {
        await openDatabase();
        if (cancelled) return;
        await reloadAll();
        if (cancelled) return;
        const ls = repo.listLists();
        const saved = await loadSession();
        if (cancelled) return;
        let lid = saved.listId;
        let tid = saved.taskId;
        if (tid) {
          const t = repo.getTask(tid);
          if (t) lid = t.list_id;
          else tid = null;
        }
        if (!lid || !ls.some((l) => l.id === lid)) {
          lid = ls[0]?.id ?? null;
        }
        if (tid) {
          const t = repo.getTask(tid);
          if (!t || t.list_id !== lid) tid = null;
        }
        setListId(lid);
        setTaskId(tid);
        setTaskSort(saved.taskSort || {});
        setReady(true);
      } catch (e) {
        console.error(e);
        if (!cancelled) {
          setError(e instanceof Error ? e.message : String(e));
        }
      }
    })();
    return () => {
      cancelled = true;
      setPersistErrorHandler(null);
    };
  }, [reloadAll]);

  useEffect(() => {
    if (!ready) return;
    return watchData(() => {
      void reloadAll().then(() => {
        setListId((lid) => {
          refreshTasks(lid);
          return lid;
        });
        setTaskId((tid) => {
          if (tid && !repo.getTask(tid)) {
            refreshDetail(null);
            return null;
          }
          refreshDetail(tid);
          return tid;
        });
      });
    });
  }, [ready, reloadAll, refreshTasks, refreshDetail]);

  useEffect(() => {
    refreshTasks(listId);
  }, [listId, refreshTasks]);

  useEffect(() => {
    refreshDetail(taskId);
  }, [taskId, refreshDetail]);

  useEffect(() => {
    if (!ready) return;
    saveSession({ listId, taskId, taskSort });
  }, [ready, listId, taskId, taskSort]);

  const selectedList = useMemo(
    () => lists.find((l) => l.id === listId) ?? null,
    [lists, listId],
  );
  const selectedTask = useMemo(() => {
    if (!taskId) return null;
    return tasks.find((t) => t.id === taskId) ?? repo.getTask(taskId);
  }, [tasks, taskId]);

  if (error) {
    return (
      <ThemeProvider theme={theme}>
        <CssBaseline />
        <Box sx={{ p: 3 }}>
          <Alert severity="error">{error}</Alert>
        </Box>
      </ThemeProvider>
    );
  }

  if (!ready) {
    return (
      <ThemeProvider theme={theme}>
        <CssBaseline />
        <Box
          sx={{
            height: '100vh',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <CircularProgress />
        </Box>
      </ThemeProvider>
    );
  }

  const detailPanel =
    selectedTask != null ? (
      <TaskDetail
        task={selectedTask}
        comments={comments}
        onClose={() => setTaskId(null)}
        onPatch={async (patch) => {
          repo.updateTask(selectedTask.id, patch);
          refreshTasks(listId);
          refreshDetail(selectedTask.id);
        }}
        onDelete={() => {
          repo.deleteTask(selectedTask.id);
          setTaskId(null);
          refreshTasks(listId);
        }}
        onAddComment={(data) => {
          repo.createComment(selectedTask.id, data);
          refreshDetail(selectedTask.id);
        }}
        onDeleteComment={(id) => {
          repo.deleteComment(id);
          refreshDetail(selectedTask.id);
        }}
      />
    ) : null;

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Box sx={{ display: 'flex', height: '100vh', overflow: 'hidden' }}>
        <ListNav
          lists={lists}
          selectedId={listId}
          onSelect={(id) => {
            setListId(id);
            setTaskId(null);
          }}
          onCreate={(title) => {
            const row = repo.createList(title);
            refreshLists();
            setListId(row.id);
            setTaskId(null);
          }}
          onRename={(id, title) => {
            repo.renameList(id, title);
            refreshLists();
          }}
          onDelete={(id) => {
            const next = repo.deleteList(id);
            const ls = refreshLists();
            setListId(next || ls[0]?.id || null);
            setTaskId(null);
          }}
          onReorder={(ids) => {
            repo.reorderLists(ids);
            refreshLists();
          }}
        />
        <TaskList
          listTitle={selectedList?.title ?? ''}
          tasks={tasks}
          selectedId={taskId}
          sortMode={
            listId && taskSort[listId] ? taskSort[listId] : 'created_desc'
          }
          onSortMode={(mode) => {
            if (!listId) return;
            setTaskSort((prev) => ({ ...prev, [listId]: mode }));
          }}
          onReorder={(ids) => {
            if (!listId) return;
            repo.reorderTasks(listId, ids);
            setTaskSort((prev) => ({ ...prev, [listId]: 'manual' }));
            refreshTasks(listId);
          }}
          onSelect={setTaskId}
          onToggleDone={(id, done) => {
            repo.updateTask(id, { done });
            refreshTasks(listId);
            if (taskId === id) refreshDetail(id);
          }}
          onAdd={(title) => {
            if (!listId) return;
            const row = repo.createTask(listId, title);
            refreshTasks(listId);
            setTaskId(row.id);
          }}
        />
        {!narrow && detailPanel}
        {narrow && (
          <Drawer
            anchor="right"
            open={!!selectedTask}
            onClose={() => setTaskId(null)}
            slotProps={{ paper: { sx: { width: '100%', maxWidth: 420 } } }}
          >
            {detailPanel}
          </Drawer>
        )}
      </Box>
      <Snackbar
        open={!!snack}
        autoHideDuration={4000}
        onClose={() => setSnack(null)}
        message={snack}
      />
    </ThemeProvider>
  );
}
