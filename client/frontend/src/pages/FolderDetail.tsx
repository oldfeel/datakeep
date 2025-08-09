import { useState, useEffect } from 'react';
import { useParams, Link, useNavigate, useSearchParams } from 'react-router-dom';

import { GetHTTPSDevices, GetHTTPSFolderContents, GetHTTPSDeviceFolders } from '../../wailsjs/go/main/App';
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

      console.log('Loading device and folder info for:', deviceId, folderId);

      // 加载设备信息
      if (deviceId === 'local') {
        console.log('Setting local device info');
        setDeviceName('本机');
        const localDevice = {
          deviceID: 'local',
          name: '本机',
          addresses: [],
          connected: true,
          isLocalNetwork: true
        };
        setDevice(localDevice);
        console.log('Local device set:', localDevice);
      } else {
        try {
          console.log('Loading remote device info');
          const result = await GetHTTPSDevices();
          if (result && typeof result === 'object' && 'code' in result && result.code !== 0) {
            throw new Error(result.data || 'API 返回错误');
          }
          const foundDevice = result?.data?.find((d: any) => d.deviceID === deviceId);
          if (foundDevice) {
            setDeviceName(foundDevice.name || foundDevice.deviceID);
            setDevice(foundDevice);
            console.log('Remote device set:', foundDevice);
          } else {
            setDeviceName(deviceId);
            const fallbackDevice = {
              deviceID: deviceId,
              name: deviceId,
              addresses: [],
              connected: false,
              isLocalNetwork: false
            };
            setDevice(fallbackDevice);
            console.log('Fallback device set:', fallbackDevice);
          }
        } catch (err) {
          console.error('Failed to load device name:', err);
          setDeviceName(deviceId);
          const errorDevice = {
            deviceID: deviceId,
            name: deviceId,
            addresses: [],
            connected: false,
            isLocalNetwork: false
          };
          setDevice(errorDevice);
          console.log('Error device set:', errorDevice);
        }
      }

      // 加载文件夹信息
      try {
        // 使用 Wails 绑定获取文件夹信息
        const result = await GetHTTPSDeviceFolders(deviceId);
        if (result && typeof result === 'object' && 'code' in result && result.code === 0) {
          const folder = result.data?.find((f: any) => f.id === folderId);
          if (folder) {
            setFolderInfo(folder);
            console.log('Folder info set:', folder);
          }
        }
      } catch (err) {
        console.error('Failed to load folder info:', err);
      }
    };
    loadDeviceAndFolderInfo();
  }, [deviceId, folderId]);

  useEffect(() => {
    console.log('loadFiles useEffect triggered - folderId:', folderId, 'device:', device, 'currentPath:', currentPath);
    if (folderId && device) {
      console.log('loadFiles useEffect - calling loadFiles');
      loadFiles();
    } else {
      console.log('loadFiles useEffect - skipping loadFiles, missing:', {
        folderId: !!folderId,
        device: !!device
      });
    }
  }, [folderId, currentPath, device]);

  const loadFiles = async () => {
    console.log('loadFiles called - device:', device, 'folderId:', folderId, 'currentPath:', currentPath);
    
    if (!device || !folderId) {
      console.log('loadFiles early return - device or folderId missing');
      return; // 等待设备信息加载完成，确保folderId存在
    }

    try {
      setLoading(true);
      setError(null);
      const path = currentPath.join('/');

      // 使用 Wails 绑定获取文件列表
      console.log('Fetching files from HTTPS API, currentPath:', currentPath, 'path:', path);
      const result = await GetHTTPSFolderContents(folderId, path);
      console.log('HTTPS API response:', result);
      if (result && typeof result === 'object' && 'code' in result && result.code === 0) {
        console.log('Files data:', result.data);
        console.log('Files count:', result.data ? result.data.length : 0);
        setFiles(result.data);
      } else {
        throw new Error(result?.data || 'API 返回错误');
      }
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
            {files.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} align="center">
                  <Typography variant="body2" color="text.secondary">
                    该目录为空
                  </Typography>
                </TableCell>
              </TableRow>
            ) : (
              files.map((file) => (
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
            ))
            )}
          </TableBody>
        </Table>
      </TableContainer>
    </Box>
  );
}

export default FolderDetail; 