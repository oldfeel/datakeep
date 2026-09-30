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
import type { AttachmentRow, ListRow, StepRow, TaskRow } from './db/types';
import ListNav from './components/ListNav';
import TaskList from './components/TaskList';
import TaskDetail from './components/TaskDetail';

export default function App() {
  const narrow = useMediaQuery('(max-width:900px)');
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [snack, setSnack] = useState<string | null>(null);
  const [lists, setLists] = useState<ListRow[]>([]);
  const [listId, setListId] = useState<string | null>(null);
  const [tasks, setTasks] = useState<TaskRow[]>([]);
  const [taskId, setTaskId] = useState<string | null>(null);
  const [steps, setSteps] = useState<StepRow[]>([]);
  const [attachments, setAttachments] = useState<AttachmentRow[]>([]);

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
      setSteps([]);
      setAttachments([]);
      return;
    }
    setSteps(repo.listSteps(tid));
    setAttachments(repo.listAttachments(tid));
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

  // 提醒：简单检查
  useEffect(() => {
    if (!ready) return;
    const tick = () => {
      const now = Date.now();
      for (const t of tasks) {
        if (!t.remind_at || t.done) continue;
        const at = new Date(t.remind_at).getTime();
        if (Number.isNaN(at)) continue;
        if (at <= now && at > now - 60_000) {
          try {
            if (Notification.permission === 'granted') {
              new Notification('待办提醒', { body: t.title });
            } else if (Notification.permission !== 'denied') {
              void Notification.requestPermission();
            }
          } catch {
            /* WebView 可能不支持 */
          }
        }
      }
    };
    const id = window.setInterval(tick, 30_000);
    tick();
    return () => window.clearInterval(id);
  }, [ready, tasks]);

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
        steps={steps}
        attachments={attachments}
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
        onAddStep={(title) => {
          repo.createStep(selectedTask.id, title);
          refreshDetail(selectedTask.id);
        }}
        onToggleStep={(id, done) => {
          repo.updateStep(id, { done });
          refreshDetail(selectedTask.id);
        }}
        onRenameStep={(id, title) => {
          repo.updateStep(id, { title });
          refreshDetail(selectedTask.id);
        }}
        onDeleteStep={(id) => {
          repo.deleteStep(id);
          refreshDetail(selectedTask.id);
        }}
        onAddFiles={async (files) => {
          for (const f of Array.from(files)) {
            await repo.addAttachment(selectedTask.id, f);
          }
          refreshDetail(selectedTask.id);
        }}
        onRemoveAtt={async (att) => {
          await repo.removeAttachment(att);
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
        />
        <TaskList
          listTitle={selectedList?.title ?? ''}
          tasks={tasks}
          selectedId={taskId}
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
