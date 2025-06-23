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
} from '@mui/material';
import {
  Menu as MenuIcon,
  Search as SearchIcon,
  Computer as ComputerIcon,
  Devices as DevicesIcon,
  Add as AddIcon,
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
  return (
    <List>
      <ListItemButton onClick={() => onDeviceClick({ deviceID: 'local', name: '本机' } as Device)}>
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
            <DevicesIcon />
          </ListItemIcon>
          <ListItemText 
            primary={device.name || device.deviceID}
            secondary={
              <Box sx={{ mt: 0.5, display: 'block' }}>
                <Typography variant="caption" display="block" color="text.secondary">
                  {device.deviceID}
                </Typography>
                {device.addresses.map((addr, index) => (
                  <Chip
                    key={index}
                    size="small"
                    label={addr}
                    sx={{ mr: 0.5, mt: 0.5 }}
                  />
                ))}
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
