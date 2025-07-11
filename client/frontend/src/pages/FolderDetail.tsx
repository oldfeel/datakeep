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
  Image as ImageIcon,
  Description as DocumentIcon,
  PictureAsPdf as PdfIcon,
  VideoFile as VideoIcon,
  Audiotrack as AudioIcon,
  Archive as ArchiveIcon,
  Code as CodeIcon,
  TableChart as SpreadsheetIcon,
  Slideshow as PresentationIcon,
  PlayArrow as ExecutableIcon,
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

interface Device {
  deviceID: string;
  name: string;
  addresses?: string[] | null;
  connected: boolean;
  isLocalNetwork: boolean;
}

// 判断是否为目录
const isDirectory = (file: File) => file.isDir;

// 根据文件扩展名获取对应的图标
const getFileIcon = (fileName: string) => {
  const extension = fileName.toLowerCase().split('.').pop() || '';

  // 图片文件
  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico', 'tiff', 'tif'].includes(extension)) {
    return <ImageIcon sx={{ mr: 1, color: '#4CAF50' }} />;
  }

  // PDF 文件
  if (extension === 'pdf') {
    return <PdfIcon sx={{ mr: 1, color: '#F44336' }} />;
  }

  // 文档文件
  if (['doc', 'docx', 'txt', 'rtf', 'odt'].includes(extension)) {
    return <DocumentIcon sx={{ mr: 1, color: '#2196F3' }} />;
  }

  // 视频文件
  if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v', '3gp'].includes(extension)) {
    return <VideoIcon sx={{ mr: 1, color: '#FF9800' }} />;
  }

  // 音频文件
  if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a'].includes(extension)) {
    return <AudioIcon sx={{ mr: 1, color: '#9C27B0' }} />;
  }

  // 压缩文件
  if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].includes(extension)) {
    return <ArchiveIcon sx={{ mr: 1, color: '#795548' }} />;
  }

  // 代码文件
  if (['js', 'ts', 'jsx', 'tsx', 'html', 'css', 'scss', 'sass', 'less', 'json', 'xml', 'yaml', 'yml', 'py', 'java', 'cpp', 'c', 'cs', 'php', 'rb', 'go', 'rs', 'swift', 'kt', 'dart'].includes(extension)) {
    return <CodeIcon sx={{ mr: 1, color: '#607D8B' }} />;
  }

  // 表格文件
  if (['xls', 'xlsx', 'csv', 'ods'].includes(extension)) {
    return <SpreadsheetIcon sx={{ mr: 1, color: '#4CAF50' }} />;
  }

  // 演示文件
  if (['ppt', 'pptx', 'odp'].includes(extension)) {
    return <PresentationIcon sx={{ mr: 1, color: '#FF5722' }} />;
  }

  // 可执行文件
  if (['exe', 'msi', 'app', 'dmg', 'deb', 'rpm', 'pkg', 'sh', 'bat', 'cmd'].includes(extension)) {
    return <ExecutableIcon sx={{ mr: 1, color: '#E91E63' }} />;
  }

  // 默认文件图标
  return <FileIcon sx={{ mr: 1, color: 'text.secondary' }} />;
};

function FolderDetail() {
  const { deviceId, folderId } = useParams<{ deviceId: string; folderId: string }>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [files, setFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [currentPath, setCurrentPath] = useState<string[]>([]);
  const [deviceName, setDeviceName] = useState<string>('');
  const [folderInfo, setFolderInfo] = useState<{ id: string; label: string; path: string } | null>(null);
  const [device, setDevice] = useState<Device | null>(null);

  // 从 URL 参数中读取路径
  useEffect(() => {
    const pathParam = searchParams.get('path');
    console.log('URL path parameter:', pathParam);
    if (pathParam) {
      const pathSegments = pathParam.split('/').filter(segment => segment.length > 0);
      console.log('Parsed path segments:', pathSegments);
      setCurrentPath(pathSegments);
    } else {
      console.log('No path parameter, setting empty path');
      setCurrentPath([]);
    }
  }, [searchParams]);

  // 切换 deviceId 或 folderId 时重置路径（但只在没有 path 参数时）
  useEffect(() => {
    const pathParam = searchParams.get('path');
    if (!pathParam) {
      setCurrentPath([]);
    }
  }, [deviceId, folderId, searchParams]);

  // 加载设备名称和文件夹信息
  useEffect(() => {
    const loadDeviceAndFolderInfo = async () => {
      if (!deviceId || !folderId) return;

      // 加载设备信息
      if (deviceId === 'local') {
        setDeviceName('本机');
        setDevice({
          deviceID: 'local',
          name: '本机',
          addresses: [],
          connected: true,
          isLocalNetwork: true
        });
      } else {
        try {
          const resp = await fetch('http://localhost:8080/api/devices');
          if (!resp.ok) throw new Error('API 请求失败');
          const result = await resp.json();
          if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
          const foundDevice = result.data.find((d: any) => d.deviceID === deviceId);
          if (foundDevice) {
            setDeviceName(foundDevice.name || foundDevice.deviceID);
            setDevice(foundDevice);
          } else {
            setDeviceName(deviceId);
            setDevice({
              deviceID: deviceId,
              name: deviceId,
              addresses: [],
              connected: false,
              isLocalNetwork: false
            });
          }
        } catch (err) {
          console.error('Failed to load device name:', err);
          setDeviceName(deviceId);
          setDevice({
            deviceID: deviceId,
            name: deviceId,
            addresses: [],
            connected: false,
            isLocalNetwork: false
          });
        }
      }

      // 加载文件夹信息
      try {
        let apiUrl: string;
        // 对于 Syncthing 文件夹，总是使用本地 API
        apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;

        console.log('Fetching folders from:', apiUrl);
        const resp = await fetch(apiUrl);
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
    if (folderId && device) {
      console.log('loadFiles triggered - currentPath:', currentPath);
      loadFiles();
    }
  }, [folderId, currentPath, device]);

  const loadFiles = async () => {
    if (!device || !folderId) return; // 等待设备信息加载完成，确保folderId存在

    try {
      setLoading(true);
      setError(null);
      const path = currentPath.join('/');

      // 构建 API URL
      let apiUrl: string;
      // 对于 Syncthing 文件夹，总是使用本地 API
      if (path) {
        apiUrl = `http://localhost:8080/api/folder/${encodeURIComponent(folderId)}?path=${encodeURIComponent(path)}`;
      } else {
        apiUrl = `http://localhost:8080/api/folder/${encodeURIComponent(folderId)}`;
      }

      console.log('Fetching files from:', apiUrl, 'currentPath:', currentPath, 'path:', path);
      const resp = await fetch(apiUrl);
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
      const newPath = [...currentPath, file.name];
      const pathString = newPath.join('/');
      navigate(`/folder/${deviceId}/${folderId}?path=${encodeURIComponent(pathString)}`);
    } else {
      // 跳转到文件预览页面
      const fullPath = currentPath.length > 0 ? `${currentPath.join('/')}/${file.name}` : file.name;
      const encodedPath = encodeURIComponent(fullPath);
      navigate(`/preview/${deviceId}/${folderId}/${encodedPath}`);
    }
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
      {/* 远程设备提示 */}
      {device && !device.isLocalNetwork && device.addresses && device.addresses.length > 0 && (
        <Alert severity="info" sx={{ mb: 2 }}>
          正在从远程设备获取数据: {device.addresses[0]}
        </Alert>
      )}

      {/* 面包屑导航 */}
      <Breadcrumbs sx={{ mb: 2 }}>
        <MuiLink component={Link} to="/" sx={{ textDecoration: 'none', color: 'inherit' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <HomeIcon fontSize="small" />
            <Typography color="text.primary">首页</Typography>
          </Box>
        </MuiLink>
        <MuiLink component={Link} to={`/device/${deviceId}`} sx={{ textDecoration: 'none', color: 'inherit' }}>
          {deviceName}
        </MuiLink>
        <MuiLink component={Link} to={`/folder/${deviceId}/${folderId}`} sx={{ textDecoration: 'none', color: 'inherit' }}>
          {folderInfo?.label || '根目录'}
        </MuiLink>
        
        {/* 动态生成路径层级 */}
        {currentPath.map((segment, index) => {
          const isLast = index === currentPath.length - 1;
          const currentPathString = currentPath.slice(0, index + 1).join('/');
          
          console.log(`Breadcrumb segment ${index}:`, segment, 'path:', currentPathString, 'isLast:', isLast);
          
          if (isLast) {
            // 最后一个段是当前目录，不显示链接
            return (
              <Typography key={index} color="text.primary">
                {segment}
              </Typography>
            );
          } else {
            // 中间的路径段，显示为可点击的链接
            const linkUrl = `/folder/${deviceId}/${folderId}?path=${encodeURIComponent(currentPathString)}`;
            console.log(`Breadcrumb link ${index}:`, linkUrl);
            return (
              <MuiLink
                key={index}
                component={Link}
                to={linkUrl}
                sx={{ textDecoration: 'none', color: 'inherit' }}
              >
                {segment}
              </MuiLink>
            );
          }
        })}
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
                      getFileIcon(file.name)
                    )}
                    {file.name}
                  </Box>
                </TableCell>
                <TableCell>{isDirectory(file) ? '文件夹' : '文件'}</TableCell>
                <TableCell align="right">
                  {isDirectory(file) ? '-' : formatFileSize(file.size)}
                </TableCell>
                <TableCell>{formatDate(new Date(file.modTime * 1000).toISOString())}</TableCell>
                <TableCell>-</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </TableContainer>
    </Box>
  );
}

export default FolderDetail; 