import React, { useState, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import {
  Box,
  Typography,
  Breadcrumbs,
  Paper,
  Alert,
  CircularProgress,
  IconButton,
  Tooltip,
  Snackbar,
} from '@mui/material';
import {
  Home as HomeIcon,
  ArrowBack as BackIcon,
  Download as DownloadIcon,
  OpenInNew as OpenInNewIcon,
  Image as ImageIcon,
  Description as DocumentIcon,
  PictureAsPdf as PdfIcon,
  VideoFile as VideoIcon,
  Audiotrack as AudioIcon,
  Code as CodeIcon,
  InsertDriveFile as FileIcon,
} from '@mui/icons-material';
import { Link as MuiLink } from '@mui/material';

interface FileInfo {
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

  // 代码文件
  if (['js', 'ts', 'jsx', 'tsx', 'html', 'css', 'scss', 'sass', 'less', 'json', 'xml', 'yaml', 'yml', 'py', 'java', 'cpp', 'c', 'cs', 'php', 'rb', 'go', 'rs', 'swift', 'kt', 'dart'].includes(extension)) {
    return <CodeIcon sx={{ mr: 1, color: '#607D8B' }} />;
  }

  // 默认文件图标
  return <FileIcon sx={{ mr: 1, color: 'text.secondary' }} />;
};

// 判断文件类型
const getFileType = (fileName: string) => {
  const extension = fileName.toLowerCase().split('.').pop() || '';
  
  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico', 'tiff', 'tif'].includes(extension)) {
    return 'image';
  }
  if (extension === 'pdf') {
    return 'pdf';
  }
  if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v', '3gp'].includes(extension)) {
    return 'video';
  }
  if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a'].includes(extension)) {
    return 'audio';
  }
  if (['txt', 'md', 'json', 'xml', 'yaml', 'yml', 'js', 'ts', 'jsx', 'tsx', 'html', 'css', 'scss', 'sass', 'less', 'py', 'java', 'cpp', 'c', 'cs', 'php', 'rb', 'go', 'rs', 'swift', 'kt', 'dart'].includes(extension)) {
    return 'text';
  }
  return 'unknown';
};

function FilePreview() {
  const { deviceId, folderId, filePath } = useParams<{ 
    deviceId: string; 
    folderId: string; 
    filePath: string;
  }>();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [fileContent, setFileContent] = useState<string | null>(null);
  const [fileUrl, setFileUrl] = useState<string | null>(null);
  const [deviceName, setDeviceName] = useState<string>('');
  const [folderName, setFolderName] = useState<string>('');
  const [device, setDevice] = useState<Device | null>(null);
  const [snackbar, setSnackbar] = useState<{
    open: boolean;
    message: string;
    severity: 'success' | 'error' | 'warning' | 'info';
  }>({
    open: false,
    message: '',
    severity: 'success'
  });

  const decodedFilePath = filePath ? decodeURIComponent(filePath) : '';
  const fileName = decodedFilePath.split('/').pop() || '';
  const fileType = getFileType(fileName);
  
  // 解析完整路径用于面包屑导航
  const pathSegments = decodedFilePath.split('/').filter(segment => segment.length > 0);
  console.log('FilePreview - original filePath:', filePath);
  console.log('FilePreview - decodedFilePath:', decodedFilePath);
  console.log('FilePreview - pathSegments:', pathSegments);

  // 加载设备信息
  useEffect(() => {
    const loadDeviceInfo = async () => {
      if (!deviceId) return;

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
          console.error('Failed to load device info:', err);
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
    };

    loadDeviceInfo();
  }, [deviceId]);

  // 加载文件夹信息
  useEffect(() => {
    const loadFolderInfo = async () => {
      if (!deviceId || !folderId) return;

      try {
        let apiUrl: string;
        if (deviceId === 'local') {
          apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
        } else if (device && device.addresses && device.addresses.length > 0) {
          const ipAddresses = device.addresses.filter(addr => {
            const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}$/;
            return ipv4Regex.test(addr) &&
              !addr.includes('[') &&
              !addr.includes('relay://') &&
              !addr.includes('quic://');
          });

          if (ipAddresses.length > 0) {
            const remoteIp = ipAddresses[0];
            apiUrl = `http://${remoteIp}:8080/api/device/${deviceId}/folders`;
          } else {
            throw new Error('设备没有可用的 IPv4 地址');
          }
        } else {
          throw new Error('设备未连接或没有可用地址');
        }

        const resp = await fetch(apiUrl);
        if (!resp.ok) throw new Error('API 请求失败');
        const result = await resp.json();
        if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
        
        const folder = result.data.find((f: any) => f.id === folderId);
        if (folder) {
          setFolderName(folder.label || folder.id);
        }
      } catch (err) {
        console.error('Failed to load folder info:', err);
        setFolderName(folderId);
      }
    };

    loadFolderInfo();
  }, [deviceId, folderId, device]);

  // 加载文件内容
  useEffect(() => {
    const loadFileContent = async () => {
      if (!deviceId || !folderId || !decodedFilePath) return;

      try {
        setLoading(true);
        setError(null);

        console.log('文件路径解码后:', decodedFilePath);
        console.log('使用 HTTP API 获取文件预览');

        if (fileType === 'image' || fileType === 'video' || fileType === 'audio' || fileType === 'pdf') {
          // 对于媒体文件，使用 HTTP API 获取预览
          try {
            // 使用 HTTP API 而不是 HTTPS API
            const apiUrl = `http://localhost:8080/api/folder/${encodeURIComponent(folderId)}/preview?path=${encodeURIComponent(decodedFilePath)}`;
            
            const response = await fetch(apiUrl);
            if (!response.ok) {
              throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            // 获取内容类型
            const contentType = response.headers.get('Content-Type') || 'application/octet-stream';
            
            // 对于媒体文件，创建 blob URL
            const blob = await response.blob();
            const url = URL.createObjectURL(blob);
            setFileUrl(url);
            setFileContent(null);
            
            console.log('媒体文件预览成功:', contentType);
          } catch (err) {
            console.error('获取媒体文件预览失败:', err);
            setError('获取文件预览失败: ' + (err instanceof Error ? err.message : String(err)));
            setFileUrl(null);
            setFileContent(null);
          }
        } else if (fileType === 'text') {
          // 对于文本文件，使用 HTTP API 获取内容
          try {
            const apiUrl = `http://localhost:8080/api/folder/${encodeURIComponent(folderId)}/preview?path=${encodeURIComponent(decodedFilePath)}`;
            
            const response = await fetch(apiUrl);
            if (!response.ok) {
              throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            
            const content = await response.text();
            setFileContent(content);
            setFileUrl(null);
            
            console.log('文本文件内容获取成功');
          } catch (err) {
            console.error('获取文本文件内容失败:', err);
            setError('获取文件内容失败: ' + (err instanceof Error ? err.message : String(err)));
            setFileContent(null);
            setFileUrl(null);
          }
        } else {
          // 不支持的文件类型
          setError('不支持预览此类型的文件');
          setFileContent(null);
          setFileUrl(null);
        }
      } catch (err) {
        console.error('Failed to load file content:', err);
        setError(err instanceof Error ? err.message : '加载文件失败');
        setFileContent(null);
        setFileUrl(null);
      } finally {
        setLoading(false);
      }
    };

    loadFileContent();
  }, [deviceId, folderId, decodedFilePath, device, fileType]);

  const handleDownload = () => {
    if (fileUrl) {
      const link = document.createElement('a');
      link.href = fileUrl;
      link.download = fileName;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      
      setSnackbar({
        open: true,
        message: '开始下载文件',
        severity: 'success'
      });
    }
  };

  const handleOpenInNewTab = () => {
    if (fileUrl) {
      window.open(fileUrl, '_blank');
    }
  };

  const formatFileSize = (size: number) => {
    if (size === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(size) / Math.log(k));
    return `${parseFloat((size / Math.pow(k, i)).toFixed(2))} ${sizes[i]}`;
  };

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '50vh' }}>
        <CircularProgress />
      </Box>
    );
  }

  if (error) {
    return (
      <Box>
        <Alert severity="error" sx={{ mb: 2 }}>
          {error}
        </Alert>
        <Box sx={{ mt: 2 }}>
          <IconButton onClick={() => navigate(-1)}>
            <BackIcon />
          </IconButton>
          <Typography variant="body1">返回</Typography>
        </Box>
      </Box>
    );
  }

  return (
    <Box>
      {/* 面包屑导航 */}
      <Breadcrumbs sx={{ mb: 3 }}>
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
          {folderName}
        </MuiLink>
        
        {/* 动态生成路径层级 */}
        {pathSegments.map((segment, index) => {
          const isLast = index === pathSegments.length - 1;
          const currentPath = pathSegments.slice(0, index + 1).join('/');
          
          console.log(`FilePreview breadcrumb segment ${index}:`, segment, 'path:', currentPath, 'isLast:', isLast);
          
          if (isLast) {
            // 最后一个段是文件名，不显示链接
            return (
              <Typography key={index} color="text.primary">
                {segment}
              </Typography>
            );
          } else {
            // 中间的路径段，显示为可点击的链接
            const encodedPath = encodeURIComponent(currentPath);
            const linkUrl = `/folder/${deviceId}/${folderId}?path=${encodedPath}`;
            console.log(`FilePreview breadcrumb link ${index}:`, linkUrl, 'encoded path:', encodedPath);
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

      {/* 文件信息头部 */}
      <Paper sx={{ p: 2, mb: 3 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
            {getFileIcon(fileName)}
            <Box>
              <Typography variant="h6">{fileName}</Typography>
              <Typography variant="body2" color="text.secondary">
                {fileType === 'image' ? '图片文件' :
                 fileType === 'video' ? '视频文件' :
                 fileType === 'audio' ? '音频文件' :
                 fileType === 'pdf' ? 'PDF 文档' :
                 fileType === 'text' ? '文本文件' : '未知类型'}
              </Typography>
            </Box>
          </Box>
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Tooltip title="在新标签页中打开">
              <IconButton onClick={handleOpenInNewTab} disabled={!fileUrl}>
                <OpenInNewIcon />
              </IconButton>
            </Tooltip>
            <Tooltip title="下载文件">
              <IconButton onClick={handleDownload} disabled={!fileUrl}>
                <DownloadIcon />
              </IconButton>
            </Tooltip>
          </Box>
        </Box>
      </Paper>

      {/* 文件预览内容 */}
      <Paper sx={{ p: 2, minHeight: '400px' }}>
        {fileType === 'image' && fileUrl && (
          <Box sx={{ textAlign: 'center' }}>
            <img 
              src={fileUrl} 
              alt={fileName}
              style={{ 
                maxWidth: '100%', 
                maxHeight: '70vh',
                objectFit: 'contain'
              }}
            />
          </Box>
        )}

        {fileType === 'video' && fileUrl && (
          <Box sx={{ textAlign: 'center' }}>
            <video 
              controls 
              style={{ 
                maxWidth: '100%', 
                maxHeight: '70vh'
              }}
            >
              <source src={fileUrl} type="video/mp4" />
              您的浏览器不支持视频播放。
            </video>
          </Box>
        )}

        {fileType === 'audio' && fileUrl && (
          <Box sx={{ textAlign: 'center', py: 4 }}>
            <audio controls style={{ width: '100%' }}>
              <source src={fileUrl} type="audio/mpeg" />
              您的浏览器不支持音频播放。
            </audio>
          </Box>
        )}

        {fileType === 'pdf' && fileUrl && (
          <Box sx={{ height: '70vh' }}>
            <iframe
              src={fileUrl}
              style={{ 
                width: '100%', 
                height: '100%',
                border: 'none'
              }}
              title={fileName}
            />
          </Box>
        )}

        {fileType === 'text' && fileContent && (
          <Box sx={{ 
            backgroundColor: '#f5f5f5', 
            p: 2, 
            borderRadius: 1,
            fontFamily: 'monospace',
            fontSize: '0.875rem',
            whiteSpace: 'pre-wrap',
            overflow: 'auto',
            maxHeight: '70vh'
          }}>
            {fileContent}
          </Box>
        )}

        {fileType === 'unknown' && (
          <Box sx={{ textAlign: 'center', py: 4 }}>
            <Typography variant="body1" color="text.secondary">
              不支持预览此类型的文件
            </Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
              请使用下载功能获取文件
            </Typography>
          </Box>
        )}
      </Paper>

      {/* 消息提示 */}
      <Snackbar
        open={snackbar.open}
        autoHideDuration={3000}
        onClose={() => setSnackbar({ ...snackbar, open: false })}
      >
        <Alert
          onClose={() => setSnackbar({ ...snackbar, open: false })}
          severity={snackbar.severity}
          sx={{ width: '100%' }}
        >
          {snackbar.message}
        </Alert>
      </Snackbar>
    </Box>
  );
}

export default FilePreview; 