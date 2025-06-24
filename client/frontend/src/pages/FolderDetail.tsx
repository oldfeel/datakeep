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
  addresses: string[];
  connected: boolean;
  isLocal: boolean;
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
  const [files, setFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [currentPath, setCurrentPath] = useState<string[]>([]);
  const [deviceName, setDeviceName] = useState<string>('');
  const [folderInfo, setFolderInfo] = useState<{ id: string; label: string; path: string } | null>(null);
  const [device, setDevice] = useState<Device | null>(null);

  // 切换 deviceId 或 folderId 时重置路径
  useEffect(() => {
    setCurrentPath([]);
  }, [deviceId, folderId]);

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
          isLocal: true
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
              isLocal: false
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
            isLocal: false
          });
        }
      }

      // 加载文件夹信息
      try {
        let apiUrl: string;
        if (deviceId === 'local') {
          // 本地设备，使用本地 API
          apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
        } else {
          // 远程设备，暂时使用本地 API 获取文件夹信息
          // 因为此时 device 状态可能还没有更新
          apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
        }

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
      loadFiles();
    }
  }, [folderId, currentPath, device]);

  const loadFiles = async () => {
    if (!device) return; // 等待设备信息加载完成

    try {
      setLoading(true);
      setError(null);
      const path = currentPath.join('/');
      
      // 构建 API URL
      let apiUrl: string;
      if (deviceId === 'local') {
        // 本地设备，使用本地 API
        apiUrl = `http://localhost:8080/api/folder/${folderId}?path=${encodeURIComponent(path)}`;
      } else if (device.addresses.length > 0) {
        // 远程设备，使用第一个可用的 IP 地址
        const remoteIp = device.addresses[0];
        apiUrl = `http://${remoteIp}:8080/api/folder/${folderId}?path=${encodeURIComponent(path)}`;
      } else {
        throw new Error('设备未连接或没有可用地址');
      }

      console.log('Fetching files from:', apiUrl);
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
      {/* 远程设备提示 */}
      {device && !device.isLocal && device.addresses.length > 0 && (
        <Alert severity="info" sx={{ mb: 2 }}>
          正在从远程设备获取数据: {device.addresses[0]}
        </Alert>
      )}

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
          onClick={() => setCurrentPath([])}
          sx={{ textDecoration: 'none', display: 'flex', alignItems: 'center' }}
        >
          {folderInfo?.label || '根目录'}
        </MuiLink>
        {currentPath.map((path, index) => (
          <MuiLink
            key={index}
            component="button"
            variant="body1"
            onClick={() => handleBreadcrumbClick(index)}
            sx={{ textDecoration: 'none' }}
          >
            {path}
          </MuiLink>
        ))}
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