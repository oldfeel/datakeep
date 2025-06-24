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

interface Folder {
  id: string;
  label: string;
  path: string;
}

interface Device {
  deviceID: string;
  name: string;
  addresses?: string[] | null;
  connected: boolean;
  isLocal: boolean;
}

// 文件夹列表组件
function FolderList({ folders, deviceName, deviceId }: { folders: Folder[] | null, deviceName: string, deviceId: string }) {
  if (!folders) {
    return (
      <Alert severity="warning" sx={{ mt: 2 }}>
        正在加载文件夹列表...
      </Alert>
    );
  }

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
              to={`/folder/${deviceId}/${folder.id}`}
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
  const [device, setDevice] = useState<Device | null>(null);

  // 获取设备信息
  useEffect(() => {
    const loadDeviceInfo = async () => {
      try {
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
          const resp = await fetch('http://localhost:8080/api/devices');
          if (!resp.ok) throw new Error('API 请求失败');
          const result = await resp.json();
          if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
          const foundDevice = result.data.find((d: any) => d.deviceID === deviceId);
          console.log('Found device:', foundDevice); // 调试日志
          if (foundDevice) {
            setDeviceName(foundDevice.name || foundDevice.deviceID);
            setDevice(foundDevice);
            console.log('Device addresses:', foundDevice.addresses); // 调试日志
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
        }
      } catch (err) {
        console.error('Failed to load device info:', err);
        setDeviceName(deviceId);
        setDevice({
          deviceID: deviceId,
          name: deviceId,
          addresses: [],
          connected: false,
          isLocal: false
        });
      }
    };

    loadDeviceInfo();
  }, [deviceId]);

  // 获取文件夹列表
  useEffect(() => {
    const loadFolders = async () => {
      if (!device) return; // 等待设备信息加载完成

      try {
        setLoading(true);
        setError(null);

        console.log('Current device:', device); // 调试日志
        console.log('Device addresses:', device.addresses || []); // 调试日志
        console.log('Device isLocal:', device.isLocal); // 调试日志

        // 构建 API URL
        let apiUrl: string;
        if (deviceId === 'local') {
          // 本地设备，使用本地 API
          apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
          console.log('Using local API'); // 调试日志
        } else if (device.addresses && device.addresses.length > 0) {
          // 远程设备，现在地址已经是纯IP地址
          const ipAddresses = device.addresses.filter(addr => {
            // 过滤出有效的IPv4地址
            const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}$/;
            return ipv4Regex.test(addr) && 
                   !addr.includes('[') && 
                   !addr.includes('relay://') &&
                   !addr.includes('quic://');
          });
          
          if (ipAddresses.length > 0) {
            console.log('All available IPv4 addresses:', ipAddresses); // 调试日志
            
            // 优先选择局域网地址
            let selectedIp = null;
            
            // 1. 优先选择 192.168.2.x（主要网络）
            const lan192_2Addresses = ipAddresses.filter(ip => ip.startsWith('192.168.2.'));
            if (lan192_2Addresses.length > 0) {
              selectedIp = lan192_2Addresses[0];
              console.log('Found 192.168.2.x addresses:', lan192_2Addresses);
              console.log('Selected primary LAN IP (192.168.2.x):', selectedIp);
            } else {
              // 2. 其次选择其他 192.168.x.x
              const lan192Addresses = ipAddresses.filter(ip => ip.startsWith('192.168.'));
              if (lan192Addresses.length > 0) {
                selectedIp = lan192Addresses[0];
                console.log('Found other 192.168.x.x addresses:', lan192Addresses);
                console.log('Selected LAN IP (192.168.x.x):', selectedIp);
              } else {
                // 3. 再次选择 10.x.x.x
                const lan10Addresses = ipAddresses.filter(ip => ip.startsWith('10.'));
                if (lan10Addresses.length > 0) {
                  selectedIp = lan10Addresses[0];
                  console.log('Found 10.x.x.x addresses:', lan10Addresses);
                  console.log('Selected LAN IP (10.x.x.x):', selectedIp);
                } else {
                  // 4. 再次选择 172.16-31.x.x
                  const lan172Addresses = ipAddresses.filter(ip => {
                    const parts = ip.split('.');
                    if (parts.length === 4) {
                      const secondOctet = parseInt(parts[1]);
                      return secondOctet >= 16 && secondOctet <= 31;
                    }
                    return false;
                  });
                  if (lan172Addresses.length > 0) {
                    selectedIp = lan172Addresses[0];
                    console.log('Found 172.16-31.x.x addresses:', lan172Addresses);
                    console.log('Selected LAN IP (172.16-31.x.x):', selectedIp);
                  } else {
                    // 5. 最后选择其他地址
                    selectedIp = ipAddresses[0];
                    console.log('No LAN addresses found, using fallback IP:', selectedIp);
                  }
                }
              }
            }
            
            if (selectedIp) {
              apiUrl = `http://${selectedIp}:8080/api/device/${deviceId}/folders`;
              console.log('Using remote API with IP:', selectedIp); // 调试日志
            } else {
              throw new Error('无法解析设备地址');
            }
          } else {
            throw new Error('设备没有可用的 IPv4 地址');
          }
        } else {
          throw new Error('设备未连接或没有可用地址');
        }

        console.log('Fetching folders from:', apiUrl);
        const resp = await fetch(apiUrl);
        if (!resp.ok) throw new Error('API 请求失败');
        const result = await resp.json();
        if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
        setFolders(result.data);
      } catch (err) {
        console.error('Failed to load folders:', err);
        setError('加载数据失败: ' + (err instanceof Error ? err.message : String(err)));
      } finally {
        setLoading(false);
      }
    };

    loadFolders();
  }, [device, deviceId]);

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

      {device && !device.isLocal && device.addresses && device.addresses.length > 0 && (
        <Alert severity="info" sx={{ mb: 2 }}>
          正在从远程设备获取数据: {device.addresses[0] || '未知地址'}
        </Alert>
      )}

      <FolderList folders={folders} deviceName={deviceName} deviceId={deviceId} />
    </Box>
  );
} 