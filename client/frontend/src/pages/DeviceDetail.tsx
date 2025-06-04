import { useState, useEffect } from 'react';
import { useParams, Link } from 'react-router-dom';
import {
  Box,
  Typography,
  Grid,
  Card,
  CardContent,
  CardActionArea,
  Skeleton,
  Alert,
  Breadcrumbs,
} from '@mui/material';
import {
  Folder as FolderIcon,
  Home as HomeIcon,
} from '@mui/icons-material';
import { GetDevices, GetDeviceFolders } from '../../wailsjs/go/main/App';

interface Folder {
  id: string;
  label: string;
  path: string;
}

// 文件夹列表组件
function FolderList({ folders, deviceName }: { folders: Folder[], deviceName: string }) {
  if (folders.length === 0) {
    return (
      <Alert severity="info" sx={{ mt: 2 }}>
        该设备没有共享文件夹
      </Alert>
    );
  }

  return (
    <Grid container spacing={2}>
      {folders.map((folder) => (
        <Grid item xs={12} sm={6} md={4} key={folder.id}>
          <Card
            sx={{
              height: '100%',
              display: 'flex',
              flexDirection: 'column',
              '&:hover': {
                boxShadow: 6,
              },
            }}
          >
            <CardActionArea
              component={Link}
              to={`/folder/${folder.id}`}
              sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', alignItems: 'stretch' }}
            >
              <CardContent sx={{ flexGrow: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
                  <FolderIcon sx={{ mr: 1, color: 'primary.main' }} />
                  <Typography variant="h6" component="div" noWrap>
                    {folder.label || folder.id}
                  </Typography>
                </Box>
                <Typography variant="body2" color="text.secondary" sx={{
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  display: '-webkit-box',
                  WebkitLineClamp: 3,
                  WebkitBoxOrient: 'vertical',
                }}>
                  {folder.path}
                </Typography>
              </CardContent>
            </CardActionArea>
          </Card>
        </Grid>
      ))}
    </Grid>
  );
}

// 设备详情页面组件
export default function DeviceDetail() {
  const { deviceId = 'local' } = useParams();
  const [folders, setFolders] = useState<Folder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [deviceName, setDeviceName] = useState<string>('');

  useEffect(() => {
    const loadData = async () => {
      try {
        setLoading(true);
        setError(null);

        // 获取设备名称
        if (deviceId === 'local') {
          setDeviceName('本机');
        } else {
          const devices = await GetDevices();
          const device = devices.find(d => d.deviceID === deviceId);
          if (device) {
            setDeviceName(device.name || device.deviceID);
          } else {
            setDeviceName(deviceId);
          }
        }

        // 获取文件夹列表
        const folders = await GetDeviceFolders(deviceId);
        setFolders(folders);
      } catch (err) {
        console.error('Failed to load data:', err);
        setError('加载数据失败');
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, [deviceId]);

  if (loading) {
    return (
      <Box sx={{ p: 3 }}>
        <Skeleton variant="text" width={200} height={40} sx={{ mb: 3 }} />
        <Grid container spacing={2}>
          {[1, 2, 3].map((i) => (
            <Grid item xs={12} sm={6} md={4} key={i}>
              <Skeleton variant="rectangular" height={140} />
            </Grid>
          ))}
        </Grid>
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
    <Box sx={{ p: 3 }}>
      <Breadcrumbs sx={{ mb: 3 }}>
        <Link to="/" style={{ textDecoration: 'none', color: 'inherit' }}>
          <Box sx={{ display: 'flex', alignItems: 'center' }}>
            <HomeIcon sx={{ mr: 0.5 }} fontSize="small" />
            <Typography>设备</Typography>
          </Box>
        </Link>
        <Typography color="text.primary">{deviceName}</Typography>
      </Breadcrumbs>

      <Typography variant="h5" sx={{ mb: 3 }}>
        {deviceName} 的文件夹
      </Typography>

      <FolderList folders={folders} deviceName={deviceName} />
    </Box>
  );
} 