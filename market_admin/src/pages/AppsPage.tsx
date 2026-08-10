import { useCallback, useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
  TextField,
  Typography,
} from '@mui/material';
import AddIcon from '@mui/icons-material/Add';
import UploadFileIcon from '@mui/icons-material/UploadFile';
import { api, uploadZip } from '../api';
import { useAuth } from '../auth';

type AppRow = {
  id: number;
  appKey: string;
  name: string;
  description: string;
  iconUrl: string;
  currentVersion?: { version: string; sha256: string; size: number } | null;
};

export default function AppsPage() {
  const { token } = useAuth();
  const [apps, setApps] = useState<AppRow[]>([]);
  const [error, setError] = useState('');
  const [msg, setMsg] = useState('');
  const [createOpen, setCreateOpen] = useState(false);
  const [uploadApp, setUploadApp] = useState<AppRow | null>(null);
  const [form, setForm] = useState({ appKey: '', name: '', description: '' });
  const [version, setVersion] = useState('1.0.0');
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setError('');
    try {
      const data = await api<AppRow[]>('/admin/apps', { token });
      setApps(data);
    } catch (e) {
      setError(e instanceof Error ? e.message : '加载失败');
    }
  }, [token]);

  useEffect(() => {
    void load();
  }, [load]);

  async function createApp() {
    setBusy(true);
    setError('');
    try {
      await api('/admin/apps', {
        method: 'POST',
        token,
        body: JSON.stringify(form),
      });
      setCreateOpen(false);
      setForm({ appKey: '', name: '', description: '' });
      setMsg('应用已创建');
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : '创建失败');
    } finally {
      setBusy(false);
    }
  }

  async function doUpload() {
    if (!uploadApp || !file || !token) return;
    setBusy(true);
    setError('');
    setMsg('');
    try {
      const up = await uploadZip(token, uploadApp.id, version, file);
      await api(`/admin/apps/${uploadApp.id}/versions`, {
        method: 'POST',
        token,
        body: JSON.stringify({
          version,
          objectKey: up.objectKey,
          sha256: up.sha256,
          size: up.size,
          skipCheck: false,
        }),
      });
      setUploadApp(null);
      setFile(null);
      setMsg(`已上传并设为当前版本 ${version}`);
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : '上传失败');
    } finally {
      setBusy(false);
    }
  }

  async function removeApp(id: number) {
    if (!confirm('确定删除该应用及版本记录？')) return;
    try {
      await api(`/admin/apps/${id}`, { method: 'DELETE', token });
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : '删除失败');
    }
  }

  return (
    <Box>
      <Stack direction="row" justifyContent="space-between" alignItems="center" mb={2}>
        <Typography variant="h5">应用列表</Typography>
        <Button startIcon={<AddIcon />} variant="contained" onClick={() => setCreateOpen(true)}>
          新建应用
        </Button>
      </Stack>
      {error && (
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}
      {msg && (
        <Alert severity="success" sx={{ mb: 2 }} onClose={() => setMsg('')}>
          {msg}
        </Alert>
      )}
      <Table size="small">
        <TableHead>
          <TableRow>
            <TableCell>ID</TableCell>
            <TableCell>appKey</TableCell>
            <TableCell>名称</TableCell>
            <TableCell>当前版本</TableCell>
            <TableCell align="right">操作</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {apps.map((a) => (
            <TableRow key={a.id}>
              <TableCell>{a.id}</TableCell>
              <TableCell>{a.appKey}</TableCell>
              <TableCell>{a.name}</TableCell>
              <TableCell>{a.currentVersion?.version ?? '—'}</TableCell>
              <TableCell align="right">
                <Button
                  size="small"
                  startIcon={<UploadFileIcon />}
                  onClick={() => {
                    setUploadApp(a);
                    setVersion(a.currentVersion?.version ?? '1.0.0');
                  }}
                >
                  上传包
                </Button>
                <Button size="small" color="error" onClick={() => void removeApp(a.id)}>
                  删除
                </Button>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>

      <Dialog open={createOpen} onClose={() => setCreateOpen(false)} fullWidth maxWidth="sm">
        <DialogTitle>新建应用</DialogTitle>
        <DialogContent>
          <TextField
            fullWidth
            margin="dense"
            label="appKey（与 app.json id 一致）"
            value={form.appKey}
            onChange={(e) => setForm({ ...form, appKey: e.target.value })}
          />
          <TextField
            fullWidth
            margin="dense"
            label="名称"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />
          <TextField
            fullWidth
            margin="dense"
            label="简介"
            multiline
            minRows={2}
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCreateOpen(false)}>取消</Button>
          <Button variant="contained" disabled={busy} onClick={() => void createApp()}>
            创建
          </Button>
        </DialogActions>
      </Dialog>

      <Dialog open={!!uploadApp} onClose={() => setUploadApp(null)} fullWidth maxWidth="sm">
        <DialogTitle>上传版本 — {uploadApp?.name}</DialogTitle>
        <DialogContent>
          <TextField
            fullWidth
            margin="dense"
            label="版本号"
            value={version}
            onChange={(e) => setVersion(e.target.value)}
          />
          <Button variant="outlined" component="label" sx={{ mt: 2 }}>
            选择 zip
            <input
              hidden
              type="file"
              accept=".zip,application/zip"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </Button>
          {file && (
            <Typography variant="body2" sx={{ mt: 1 }}>
              {file.name}（{(file.size / 1024).toFixed(1)} KB）
            </Typography>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setUploadApp(null)}>取消</Button>
          <Button variant="contained" disabled={busy || !file} onClick={() => void doUpload()}>
            {busy ? '上传中…' : '上传并设为当前'}
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
