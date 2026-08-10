import { FormEvent, useEffect, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  FormControl,
  FormControlLabel,
  InputLabel,
  MenuItem,
  Select,
  Stack,
  Switch,
  TextField,
  Typography,
} from '@mui/material';
import { api } from '../api';
import { useAuth } from '../auth';

type StorageForm = {
  provider: 'qiniu' | 's3';
  qiniuAccessKey: string;
  qiniuSecretKey: string;
  qiniuSecretKeySet: boolean;
  qiniuBucket: string;
  qiniuUploadUrl: string;
  qiniuDomain: string;
  s3Endpoint: string;
  s3Region: string;
  s3Bucket: string;
  s3AccessKey: string;
  s3SecretKey: string;
  s3SecretKeySet: boolean;
  s3PublicBaseUrl: string;
  s3ForcePathStyle: boolean;
};

const empty: StorageForm = {
  provider: 's3',
  qiniuAccessKey: '',
  qiniuSecretKey: '',
  qiniuSecretKeySet: false,
  qiniuBucket: '',
  qiniuUploadUrl: 'https://upload.qiniup.com',
  qiniuDomain: '',
  s3Endpoint: '',
  s3Region: 'cn-east-1',
  s3Bucket: '',
  s3AccessKey: '',
  s3SecretKey: '',
  s3SecretKeySet: false,
  s3PublicBaseUrl: '',
  s3ForcePathStyle: true,
};

export default function SettingsPage() {
  const { token } = useAuth();
  const [form, setForm] = useState<StorageForm>(empty);
  const [error, setError] = useState('');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    void (async () => {
      try {
        const data = await api<StorageForm>('/admin/settings/storage', { token });
        setForm({
          ...empty,
          ...data,
          qiniuSecretKey: '',
          s3SecretKey: '',
          provider: data.provider === 'qiniu' ? 'qiniu' : 's3',
        });
      } catch (e) {
        setError(e instanceof Error ? e.message : '加载失败');
      }
    })();
  }, [token]);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError('');
    setMsg('');
    try {
      const payload: Record<string, unknown> = {
        provider: form.provider,
        qiniuAccessKey: form.qiniuAccessKey,
        qiniuBucket: form.qiniuBucket,
        qiniuUploadUrl: form.qiniuUploadUrl,
        qiniuDomain: form.qiniuDomain,
        s3Endpoint: form.s3Endpoint,
        s3Region: form.s3Region,
        s3Bucket: form.s3Bucket,
        s3AccessKey: form.s3AccessKey,
        s3PublicBaseUrl: form.s3PublicBaseUrl,
        s3ForcePathStyle: form.s3ForcePathStyle,
      };
      if (form.qiniuSecretKey) payload.qiniuSecretKey = form.qiniuSecretKey;
      if (form.s3SecretKey) payload.s3SecretKey = form.s3SecretKey;

      const data = await api<StorageForm>('/admin/settings/storage', {
        method: 'PUT',
        token,
        body: JSON.stringify(payload),
      });
      setForm({
        ...empty,
        ...data,
        qiniuSecretKey: '',
        s3SecretKey: '',
        provider: data.provider === 'qiniu' ? 'qiniu' : 's3',
      });
      setMsg('存储配置已保存');
    } catch (err) {
      setError(err instanceof Error ? err.message : '保存失败');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box component="form" onSubmit={onSubmit} maxWidth={640}>
      <Typography variant="h5" gutterBottom>
        对象存储设置
      </Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        应用市场上传包使用的管理员桶（与用户「分享到云」的客户端配置无关）。Secret
        留空表示不修改已保存的密钥。
      </Typography>
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

      <FormControl fullWidth margin="normal">
        <InputLabel id="provider-label">存储类型</InputLabel>
        <Select
          labelId="provider-label"
          label="存储类型"
          value={form.provider}
          onChange={(e) =>
            setForm({ ...form, provider: e.target.value as 'qiniu' | 's3' })
          }
        >
          <MenuItem value="s3">S3 兼容（七牛 S3 / 阿里云 / MinIO 等）</MenuItem>
          <MenuItem value="qiniu">七牛原生上传</MenuItem>
        </Select>
      </FormControl>

      {form.provider === 'qiniu' ? (
        <Stack spacing={1} sx={{ mt: 1 }}>
          <TextField
            label="AccessKey"
            value={form.qiniuAccessKey}
            onChange={(e) => setForm({ ...form, qiniuAccessKey: e.target.value })}
            fullWidth
          />
          <TextField
            label={form.qiniuSecretKeySet ? 'SecretKey（已保存，留空不改）' : 'SecretKey'}
            type="password"
            value={form.qiniuSecretKey}
            onChange={(e) => setForm({ ...form, qiniuSecretKey: e.target.value })}
            fullWidth
          />
          <TextField
            label="Bucket"
            value={form.qiniuBucket}
            onChange={(e) => setForm({ ...form, qiniuBucket: e.target.value })}
            fullWidth
          />
          <TextField
            label="上传域名"
            value={form.qiniuUploadUrl}
            onChange={(e) => setForm({ ...form, qiniuUploadUrl: e.target.value })}
            fullWidth
            helperText="默认 https://upload.qiniup.com"
          />
          <TextField
            label="下载/CDN 域名"
            value={form.qiniuDomain}
            onChange={(e) => setForm({ ...form, qiniuDomain: e.target.value })}
            fullWidth
            helperText="如 https://xxx.clouddn.com"
          />
        </Stack>
      ) : (
        <Stack spacing={1} sx={{ mt: 1 }}>
          <TextField
            label="Endpoint"
            value={form.s3Endpoint}
            onChange={(e) => setForm({ ...form, s3Endpoint: e.target.value })}
            fullWidth
            helperText="填区域端点，勿带 bucket，如 s3.cn-south-1.qiniucs.com"
          />
          <TextField
            label="Region"
            value={form.s3Region}
            onChange={(e) => setForm({ ...form, s3Region: e.target.value })}
            fullWidth
          />
          <TextField
            label="Bucket"
            value={form.s3Bucket}
            onChange={(e) => setForm({ ...form, s3Bucket: e.target.value })}
            fullWidth
          />
          <TextField
            label="AccessKey"
            value={form.s3AccessKey}
            onChange={(e) => setForm({ ...form, s3AccessKey: e.target.value })}
            fullWidth
          />
          <TextField
            label={form.s3SecretKeySet ? 'SecretKey（已保存，留空不改）' : 'SecretKey'}
            type="password"
            value={form.s3SecretKey}
            onChange={(e) => setForm({ ...form, s3SecretKey: e.target.value })}
            fullWidth
          />
          <TextField
            label="公开访问 / CDN 前缀"
            value={form.s3PublicBaseUrl}
            onChange={(e) => setForm({ ...form, s3PublicBaseUrl: e.target.value })}
            fullWidth
            helperText="下载 URL 前缀，可选"
          />
          <FormControlLabel
            control={
              <Switch
                checked={form.s3ForcePathStyle}
                onChange={(e) =>
                  setForm({ ...form, s3ForcePathStyle: e.target.checked })
                }
              />
            }
            label="Force path style"
          />
        </Stack>
      )}

      <Button type="submit" variant="contained" sx={{ mt: 3 }} disabled={busy}>
        {busy ? '保存中…' : '保存'}
      </Button>
    </Box>
  );
}
