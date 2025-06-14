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
  PictureAsPdf as PdfIcon,
  Description as DocIcon,
  Movie as VideoIcon,
  Audiotrack as AudioIcon,
  Code as CodeIcon,
  Archive as ArchiveIcon,
  TextSnippet as TextIcon,
  Computer as ComputerIcon,
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
const isDirectory = (file: File) => file.isDir;

// 获取文件图标
const getFileIcon = (fileName: string, isDir: boolean) => {
  if (isDir) {
    return <FolderIcon sx={{ mr: 1, color: 'primary.main' }} />;
  }

  const ext = fileName.toLowerCase().split('.').pop() || '';

  // 图片文件
  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'].includes(ext)) {
    return <ImageIcon sx={{ mr: 1, color: '#2196f3' }} />;
  }

  // PDF文件
  if (ext === 'pdf') {
    return <PdfIcon sx={{ mr: 1, color: '#f44336' }} />;
  }

  // 文档文件
  if (['doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'].includes(ext)) {
    return <DocIcon sx={{ mr: 1, color: '#4caf50' }} />;
  }

  // 视频文件
  if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv', 'webm'].includes(ext)) {
    return <VideoIcon sx={{ mr: 1, color: '#ff9800' }} />;
  }

  // 音频文件
  if (['mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'].includes(ext)) {
    return <AudioIcon sx={{ mr: 1, color: '#9c27b0' }} />;
  }

  // 代码文件
  if (['js', 'ts', 'jsx', 'tsx', 'py', 'java', 'cpp', 'c', 'h', 'go', 'rs', 'php', 'html', 'css', 'json', 'xml', 'yaml', 'yml'].includes(ext)) {
    return <CodeIcon sx={{ mr: 1, color: '#795548' }} />;
  }

  // 压缩文件
  if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2'].includes(ext)) {
    return <ArchiveIcon sx={{ mr: 1, color: '#607d8b' }} />;
  }

  // 文本文件
  if (['txt', 'md', 'log', 'ini', 'conf'].includes(ext)) {
    return <TextIcon sx={{ mr: 1, color: '#9e9e9e' }} />;
  }

  // 默认文件图标
  return <FileIcon sx={{ mr: 1, color: 'text.secondary' }} />;
};

function FolderDetail() {
  const { folderId } = useParams<{ folderId: string }>();
  const [searchParams] = useSearchParams();
  const deviceName = searchParams.get('deviceName') || '本机';
  const [files, setFiles] = useState<File[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [currentPath, setCurrentPath] = useState<string[]>([]);
  const navigate = useNavigate();

  // 切换 folderId 时重置路径
  useEffect(() => {
    setCurrentPath([]);
  }, [folderId]);

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
          component="button"
          variant="body1"
          onClick={() => navigate(-1)}
          sx={{ textDecoration: 'none', display: 'flex', alignItems: 'center' }}
        >
          <ComputerIcon sx={{ mr: 0.5 }} fontSize="small" />
          {deviceName}
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
                    {getFileIcon(file.name, isDirectory(file))}
                    {file.name}
                  </Box>
                </TableCell>
                <TableCell>{isDirectory(file) ? '文件夹' : '文件'}</TableCell>
                <TableCell align="right">
                  {isDirectory(file) ? '-' : formatFileSize(file.size)}
                </TableCell>
                <TableCell>{new Date(file.modTime * 1000).toLocaleString('zh-CN')}</TableCell>
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