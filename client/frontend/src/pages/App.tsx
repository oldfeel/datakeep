import { useState, useEffect } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import {
  AppBar,
  Box,
  CssBaseline,
  Drawer,
  IconButton,
  InputBase,
  List,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Toolbar,
  Typography,
  styled,
  alpha,
  TextField,
  Divider,
  Chip,
  Button,
  Badge,
} from '@mui/material';
import {
  Menu as MenuIcon,
  Search as SearchIcon,
  Computer as ComputerIcon,
  Devices as DevicesIcon,
  Add as AddIcon,
  Wifi as WifiIcon,
  WifiOff as WifiOffIcon,
  SignalCellular4Bar as SignalCellular4BarIcon,
  SignalCellular0Bar as SignalCellular0BarIcon,
} from '@mui/icons-material';
import DeviceDetail from './DeviceDetail';
import FolderDetail from './FolderDetail';
import './App.css';

interface Device {
  deviceID: string;
  name: string;
  addresses: string[];
  compression: string;
  certName: string;
  introducer: boolean;
  connected: boolean;
  connectionType: string;
  clientVersion: string;
  inBytesTotal: number;
  outBytesTotal: number;
  isLocal: boolean;
  crypto: string;
}

interface Folder {
  id: string;
  label: string;
  path: string;
}

const drawerWidth = 240;

const Search = styled('div')(({ theme }) => ({
  position: 'relative',
  borderRadius: theme.shape.borderRadius,
  backgroundColor: alpha(theme.palette.common.white, 0.15),
  '&:hover': {
    backgroundColor: alpha(theme.palette.common.white, 0.25),
  },
  marginRight: theme.spacing(2),
  marginLeft: 0,
  width: '100%',
  [theme.breakpoints.up('sm')]: {
    marginLeft: theme.spacing(3),
    width: 'auto',
  },
}));

const SearchIconWrapper = styled('div')(({ theme }) => ({
  padding: theme.spacing(0, 2),
  height: '100%',
  position: 'absolute',
  pointerEvents: 'none',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
}));

const StyledInputBase = styled(InputBase)(({ theme }) => ({
  color: 'inherit',
  '& .MuiInputBase-input': {
    padding: theme.spacing(1, 1, 1, 0),
    paddingLeft: `calc(1em + ${theme.spacing(4)})`,
    transition: theme.transitions.create('width'),
    width: '100%',
    [theme.breakpoints.up('md')]: {
      width: '20ch',
    },
  },
}));

// 设备列表组件
function DeviceList({ devices, onDeviceClick }: { devices: Device[], onDeviceClick: (device: Device) => void }) {
  // 格式化字节数为可读格式
  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  // 获取连接状态图标
  const getConnectionIcon = (device: Device) => {
    if (device.connected) {
      return <WifiIcon color="success" />;
    } else {
      return <WifiOffIcon color="error" />;
    }
  };

  // 获取连接类型显示文本
  const getConnectionTypeText = (device: Device) => {
    if (!device.connected) return '离线';
    if (device.isLocal) return '本地连接';
    switch (device.connectionType) {
      case 'tcp-server': return 'TCP 服务器';
      case 'tcp-client': return 'TCP 客户端';
      case 'quic': return 'QUIC';
      default: return device.connectionType || '未知';
    }
  };

  return (
    <List>
      <ListItemButton onClick={() => onDeviceClick({ 
        deviceID: 'local', 
        name: '本机',
        addresses: [],
        compression: '',
        certName: '',
        introducer: false,
        connected: true,
        connectionType: 'local',
        clientVersion: '',
        inBytesTotal: 0,
        outBytesTotal: 0,
        isLocal: true,
        crypto: ''
      } as Device)}>
        <ListItemIcon>
          <ComputerIcon />
        </ListItemIcon>
        <ListItemText primary="本机" />
      </ListItemButton>
      <Divider />
      {devices.map((device) => (
        <ListItemButton
          key={device.deviceID}
          onClick={() => onDeviceClick(device)}
        >
          <ListItemIcon>
            <Badge
              badgeContent={device.connected ? '在线' : '离线'}
              color={device.connected ? 'success' : 'error'}
              sx={{
                '& .MuiBadge-badge': {
                  fontSize: '0.6rem',
                  height: '16px',
                  minWidth: '16px',
                }
              }}
            >
              {getConnectionIcon(device)}
            </Badge>
          </ListItemIcon>
          <ListItemText 
            primary={
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Typography variant="body1">
                  {device.name || device.deviceID}
                </Typography>
                <Chip
                  size="small"
                  label={getConnectionTypeText(device)}
                  color={device.connected ? 'success' : 'default'}
                  variant={device.connected ? 'filled' : 'outlined'}
                  sx={{ fontSize: '0.7rem', height: '20px' }}
                />
              </Box>
            }
            secondary={
              <Box sx={{ mt: 0.5, display: 'block' }}>
                <Typography variant="caption" display="block" color="text.secondary">
                  {device.deviceID}
                </Typography>
                {device.connected && (
                  <Box sx={{ mt: 0.5, display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                    <Typography variant="caption" color="text.secondary">
                      接收: {formatBytes(device.inBytesTotal)}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      发送: {formatBytes(device.outBytesTotal)}
                    </Typography>
                    {device.clientVersion && (
                      <Typography variant="caption" color="text.secondary">
                        版本: {device.clientVersion}
                      </Typography>
                    )}
                  </Box>
                )}
                {device.addresses.length > 0 && (
                  <Box sx={{ mt: 0.5 }}>
                    {device.addresses.slice(0, 2).map((addr, index) => (
                      <Chip
                        key={index}
                        size="small"
                        label={addr}
                        variant="outlined"
                        sx={{ mr: 0.5, mt: 0.5, fontSize: '0.7rem' }}
                      />
                    ))}
                    {device.addresses.length > 2 && (
                      <Chip
                        size="small"
                        label={`+${device.addresses.length - 2} 更多`}
                        variant="outlined"
                        sx={{ mr: 0.5, mt: 0.5, fontSize: '0.7rem' }}
                      />
                    )}
                  </Box>
                )}
              </Box>
            }
          />
        </ListItemButton>
      ))}
      <Divider />
      <ListItem>
        <Button
          fullWidth
          variant="outlined"
          startIcon={<AddIcon />}
          onClick={() => {
            // TODO: 实现添加设备的功能
            console.log('添加设备');
          }}
          sx={{
            justifyContent: 'flex-start',
            pl: 2,
            py: 1,
          }}
        >
          添加设备
        </Button>
      </ListItem>
    </List>
  );
}

function App() {
  const [devices, setDevices] = useState<Device[]>([]);
  const [searchText, setSearchText] = useState('');
  const navigate = useNavigate();

  useEffect(() => {
    loadDevices();
    
    // 每30秒自动刷新设备列表以更新连接状态
    const interval = setInterval(() => {
      loadDevices();
    }, 30000);

    return () => clearInterval(interval);
  }, []);

  const loadDevices = async () => {
    try {
      const resp = await fetch('http://localhost:8080/api/devices');
      if (!resp.ok) throw new Error('API 请求失败');
      const result = await resp.json();
      if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
      setDevices(result.data);
    } catch (err) {
      console.error('Failed to load devices:', err);
    }
  };

  const handleSearchChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setSearchText(event.target.value);
  };

  const handleDeviceClick = (device: Device) => {
    navigate(`/device/${device.deviceID}`);
  };

  const filteredDevices = devices.filter(device => 
    device.name.toLowerCase().includes(searchText.toLowerCase()) ||
    device.deviceID.toLowerCase().includes(searchText.toLowerCase())
  );

  return (
    <Box sx={{ display: 'flex', height: '100vh' }}>
      {/* 顶部 AppBar */}
      <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }}>
        <Toolbar>
          <Typography
            variant="h6"
            noWrap
            component="div"
            sx={{ flexGrow: 0, mr: 2, cursor: 'pointer' }}
            onClick={() => navigate('/')}
          >
            MyData
          </Typography>
          <TextField
            size="small"
            placeholder="搜索设备..."
            value={searchText}
            onChange={handleSearchChange}
            sx={{ 
              flexGrow: 1,
              '& .MuiOutlinedInput-root': {
                backgroundColor: 'rgba(255, 255, 255, 0.15)',
                '&:hover': {
                  backgroundColor: 'rgba(255, 255, 255, 0.25)',
                },
                '&.Mui-focused': {
                  backgroundColor: 'rgba(255, 255, 255, 0.25)',
                },
              },
            }}
            InputProps={{
              startAdornment: <SearchIcon sx={{ color: 'white', mr: 1 }} />,
            }}
          />
        </Toolbar>
      </AppBar>

      {/* 左侧菜单 */}
      <Drawer
        variant="permanent"
        sx={{
          width: 240,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: 240,
            boxSizing: 'border-box',
            marginTop: '64px', // AppBar 的高度
          },
        }}
      >
        <DeviceList devices={filteredDevices} onDeviceClick={handleDeviceClick} />
      </Drawer>

      {/* 主内容区域 */}
      <Box component="main" sx={{ flexGrow: 1, p: 3, marginTop: '64px' }}>
        <Routes>
          <Route path="/" element={<Navigate to="/device/local" replace />} />
          <Route path="/device/:deviceId" element={<DeviceDetail />} />
          <Route path="/folder/:deviceId/:folderId" element={<FolderDetail />} />
        </Routes>
      </Box>
    </Box>
  );
}

export default App;
