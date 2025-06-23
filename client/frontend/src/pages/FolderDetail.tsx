import { useState, useEffect } from 'react';
import { useParams, Link, useNavigate, useSearchParams } from 'react-router-dom';
import {
  Box,
  Typography,
  Breadcrumbs,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  IconButton,
  Skeleton,
  Alert,
  Tooltip,
  CircularProgress,
} from '@mui/material';
import {
  Home as HomeIcon,
  Folder as FolderIcon,
  InsertDriveFile as FileIcon,
  ArrowUpward as UpIcon,
  Refresh as RefreshIcon,
} from '@mui/icons-material';
import { Link as RouterLink } from 'react-router-dom';
import { Link as MuiLink } from '@mui/material';

interface File {
  id: number;
  folderId: string;
  path: string;
  name: string;
  size: number;
  modTime: number;
  isDir: boolean;
}

// 判断是否为目录
const isDirectory = (file: File) =>
  file.type === 'DIRECTORY' || file.type === 'FILE_INFO_TYPE_DIRECTORY';

function FolderDetail() {
  const { folderId } = useParams<{ folderId: string }>();
  const [files, setFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [currentPath, setCurrentPath] = useState<string[]>([]);

  // 切换 deviceId 或 folderId 时重置路径
  useEffect(() => {
    setCurrentPath([]);
  }, [deviceId, folderId]);

  // 加载设备名称和文件夹信息
  useEffect(() => {
    const loadDeviceAndFolderInfo = async () => {
      if (!deviceId || !folderId) return;
      
      // 加载设备名称
      if (deviceId === 'local') {
        setDeviceName('本机');
      } else {
        try {
          const resp = await fetch('http://localhost:8080/api/devices');
          if (!resp.ok) throw new Error('API 请求失败');
          const result = await resp.json();
          if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
          const device = result.data.find((d: any) => d.deviceID === deviceId);
          if (device) {
            setDeviceName(device.name || device.deviceID);
          } else {
            setDeviceName(deviceId);
          }
        } catch (err) {
          console.error('Failed to load device name:', err);
          setDeviceName(deviceId);
        }
      }

      // 加载文件夹信息
      try {
        const resp = await fetch(`http://localhost:8080/api/device/${deviceId}/folders`);
        if (!resp.ok) throw new Error('API 请求失败');
        const result = await resp.json();
        if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
        const folder = result.data.find((f: any) => f.id === folderId);
        if (folder) {
          setFolderInfo(folder);
        }
      } catch (err) {
        console.error('Failed to load folder info:', err);
      }
    };
    loadDeviceAndFolderInfo();
  }, [deviceId, folderId]);

  useEffect(() => {
    if (folderId) {
      loadFiles();
    }
  }, [folderId, currentPath]);

  const loadFiles = async () => {
    try {
      setLoading(true);
      setError(null);
      const path = currentPath.join('/');
      // 通过 HTTP API 获取文件列表（使用绝对路径，避免 dev server 代理问题）
      const resp = await fetch(`http://localhost:8080/api/folder/${folderId}?path=${encodeURIComponent(path)}`);
      if (!resp.ok) throw new Error('API 请求失败');
      const result = await resp.json();
      if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
      setFiles(result.data);
    } catch (err) {
      console.error('Failed to load files:', err);
      setError(err instanceof Error ? err.message : '加载文件失败');
    } finally {
      setLoading(false);
    }
  };

  const handleFileClick = (file: File) => {
    if (isDirectory(file)) {
      setCurrentPath([...currentPath, file.name]);
    } else {
      // TODO: 处理文件点击，例如预览或下载
      console.log('File clicked:', file);
    }
  };

  const handleBreadcrumbClick = (index: number) => {
    setCurrentPath(currentPath.slice(0, index + 1));
  };

  const formatFileSize = (size: number) => {
    if (size === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(size) / Math.log(k));
    return `${parseFloat((size / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
  };

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', p: 3 }}>
        <CircularProgress />
      </Box>
    );
  }

  if (error) {
    return (
      <Box sx={{ p: 3 }}>
        <Alert severity="error">{error}</Alert>
      </Box>
    );
  }

  return (
    <Box>
      {/* 面包屑导航 */}
      <Breadcrumbs sx={{ mb: 2 }}>
        <MuiLink
          component={Link}
          to="/"
          sx={{ textDecoration: 'none' }}
        >
          设备
        </MuiLink>
        <MuiLink
          component={Link}
          to={`/device/${deviceId}`}
          sx={{ textDecoration: 'none' }}
        >
          {deviceName}
        </MuiLink>
        <MuiLink
          component="button"
          variant="body1"
          onClick={() => navigate(-1)}
          sx={{ textDecoration: 'none', display: 'flex', alignItems: 'center' }}
        >
          根目录
        </MuiLink>
        {currentPath.length === 0 ? (
          <Typography color="text.primary">根目录</Typography>
        ) : (
          currentPath.map((path, index) => (
            <MuiLink
              key={index}
              component="button"
              variant="body1"
              onClick={() => handleBreadcrumbClick(index)}
              sx={{ textDecoration: 'none' }}
            >
              {path}
            </MuiLink>
          ))
        )}
      </Breadcrumbs>

      {/* 文件列表 */}
      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>名称</TableCell>
              <TableCell>类型</TableCell>
              <TableCell align="right">大小</TableCell>
              <TableCell>修改时间</TableCell>
              <TableCell>权限</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {files.map((file) => (
              <TableRow
                key={file.id}
                hover
                onClick={() => handleFileClick(file)}
                sx={{ cursor: 'pointer' }}
              >
                <TableCell>
                  <Box sx={{ display: 'flex', alignItems: 'center' }}>
                    {isDirectory(file) ? (
                      <FolderIcon sx={{ mr: 1, color: 'primary.main' }} />
                    ) : (
                      <FileIcon sx={{ mr: 1, color: 'text.secondary' }} />
                    )}
                    {file.name}
                  </Box>
                </TableCell>
                <TableCell>{isDirectory(file) ? '文件夹' : '文件'}</TableCell>
                <TableCell align="right">
                  {isDirectory(file) ? '-' : formatFileSize(file.size)}
                </TableCell>
                <TableCell>{formatDate(file.modified)}</TableCell>
                <TableCell>{file.permissions}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
    </Box>
  );
}

export default FolderDetail; 