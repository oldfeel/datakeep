import { useState, useEffect, useCallback } from 'react';
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
  Snackbar,
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  ListItemAvatar,
  Avatar,
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
  Notifications as NotificationsIcon,
  Info as InfoIcon,
  Warning as WarningIcon,
  Error as ErrorIcon,
  CheckCircle as CheckCircleIcon,
} from '@mui/icons-material';
import DeviceDetail from './DeviceDetail';
import FolderDetail from './FolderDetail';
import './App.css';

// Syncthing 事件类型定义
interface SyncthingEvent {
  id: number;
  globalID: number;
  time: string;
  type: string;
  data: any;
}

// 事件类型枚举
const EventTypes = {
  Starting: 'Starting',
  StartupComplete: 'StartupComplete',
  DeviceDiscovered: 'DeviceDiscovered',
  DeviceConnected: 'DeviceConnected',
  DeviceDisconnected: 'DeviceDisconnected',
  DeviceRejected: 'DeviceRejected',
  PendingDevicesChanged: 'PendingDevicesChanged',
  LocalChangeDetected: 'LocalChangeDetected',
  RemoteChangeDetected: 'RemoteChangeDetected',
  LocalIndexUpdated: 'LocalIndexUpdated',
  RemoteIndexUpdated: 'RemoteIndexUpdated',
  ItemStarted: 'ItemStarted',
  ItemFinished: 'ItemFinished',
  StateChanged: 'StateChanged',
  FolderRejected: 'FolderRejected',
  PendingFoldersChanged: 'PendingFoldersChanged',
  ConfigSaved: 'ConfigSaved',
  DownloadProgress: 'DownloadProgress',
  RemoteDownloadProgress: 'RemoteDownloadProgress',
  FolderSummary: 'FolderSummary',
  FolderCompletion: 'FolderCompletion',
  FolderErrors: 'FolderErrors',
  DevicePaused: 'DevicePaused',
  DeviceResumed: 'DeviceResumed',
  ClusterConfigReceived: 'ClusterConfigReceived',
  FolderScanProgress: 'FolderScanProgress',
  FolderPaused: 'FolderPaused',
  FolderResumed: 'FolderResumed',
  ListenAddressesChanged: 'ListenAddressesChanged',
  LoginAttempt: 'LoginAttempt',
  FolderWatchStateChanged: 'FolderWatchStateChanged',
  Failure: 'Failure',
} as const;

interface Device {
  deviceID: string;
  name: string;
  addresses?: string[] | null;
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

// 事件监听服务
// 使用代理接口避免跨域问题
class SyncthingEventService {
  private lastEventId = 0;
  private isConnected = false;
  private reconnectTimeout: number | null = null;
  private eventListeners: Map<string, ((event: SyncthingEvent) => void)[]> = new Map();

  constructor(private baseUrl: string = 'http://localhost:8080') { }

  // 添加事件监听器
  addEventListener(eventType: string, callback: (event: SyncthingEvent) => void) {
    if (!this.eventListeners.has(eventType)) {
      this.eventListeners.set(eventType, []);
    }
    this.eventListeners.get(eventType)!.push(callback);
  }

  // 移除事件监听器
  removeEventListener(eventType: string, callback: (event: SyncthingEvent) => void) {
    const listeners = this.eventListeners.get(eventType);
    if (listeners) {
      const index = listeners.indexOf(callback);
      if (index > -1) {
        listeners.splice(index, 1);
      }
    }
  }

  // 触发事件
  private triggerEvent(event: SyncthingEvent) {
    const listeners = this.eventListeners.get(event.type);
    if (listeners) {
      listeners.forEach(callback => callback(event));
    }
  }

  // 开始事件监听
  async start() {
    if (this.isConnected) return;

    try {
      await this.pollEvents();
    } catch (error) {
      console.error('Failed to start event polling:', error);
      this.scheduleReconnect();
    }
  }

  // 停止事件监听
  stop() {
    this.isConnected = false;
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
  }

  // 轮询事件
  private async pollEvents() {
    this.isConnected = true;
    console.log('开始事件轮询...');

    while (this.isConnected) {
      try {
        // 使用代理接口
        const response = await fetch(`${this.baseUrl}/api/syncthing/events?since=${this.lastEventId}&timeout=60`);

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const events: SyncthingEvent[] = await response.json();

        if (events && events.length > 0) {
          console.log(`收到 ${events.length} 个事件:`, events);
          // 处理接收到的事件
          events.forEach(event => {
            this.lastEventId = event.id;
            this.triggerEvent(event);
          });
        }
      } catch (error) {
        console.error('Event polling error:', error);
        this.isConnected = false;
        this.scheduleReconnect();
        break;
      }
    }
  }

  // 安排重连
  private scheduleReconnect() {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
    }

    this.reconnectTimeout = setTimeout(() => {
      if (!this.isConnected) {
        console.log('Attempting to reconnect to event stream...');
        this.start();
      }
    }, 5000); // 5秒后重连
  }

  // 获取连接状态
  getConnectionStatus() {
    return this.isConnected;
  }
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
          sx={{ flexDirection: 'column', alignItems: 'flex-start', py: 2 }}
        >
          <Box sx={{ display: 'flex', alignItems: 'center', width: '100%', mb: 1 }}>
            <ListItemIcon sx={{ minWidth: 40 }}>
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
            <Box sx={{ flexGrow: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
              <Typography variant="body1" component="span">
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
          </Box>

          <Box sx={{ pl: 6, width: '100%' }}>
            {device.connected && (
              <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 1 }}>
                <Typography variant="caption" color="text.secondary" component="span">
                  接收: {formatBytes(device.inBytesTotal)}
                </Typography>
                <Typography variant="caption" color="text.secondary" component="span">
                  发送: {formatBytes(device.outBytesTotal)}
                </Typography>
              </Box>
            )}
            {device.addresses && device.addresses.length > 0 && (
              <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                {device.addresses.slice(0, 2).map((addr, index) => (
                  <Chip
                    key={index}
                    size="small"
                    label={addr}
                    variant="outlined"
                    sx={{ fontSize: '0.7rem' }}
                  />
                ))}
                {device.addresses.length > 2 && (
                  <Chip
                    size="small"
                    label={`+${device.addresses.length - 2} 更多`}
                    variant="outlined"
                    sx={{ fontSize: '0.7rem' }}
                  />
                )}
              </Box>
            )}
          </Box>
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
  const [eventService] = useState(() => new SyncthingEventService());
  const [isEventConnected, setIsEventConnected] = useState(false);
  const [eventNotifications, setEventNotifications] = useState<Array<{ id: string, message: string, severity: 'success' | 'info' | 'warning' | 'error' }>>([]);
  const [messageList, setMessageList] = useState<Array<{ id: string, message: string, severity: 'success' | 'info' | 'warning' | 'error', timestamp: Date }>>([]);
  const [messageDialogOpen, setMessageDialogOpen] = useState(false);
  const navigate = useNavigate();

  // 事件处理函数
  const handleNotificationClose = (id: string) => {
    setEventNotifications(prev => prev.filter(notification => notification.id !== id));
  };

  // 添加自动移除通知的函数
  const removeNotificationAfterDelay = useCallback((id: string, delay: number = 3000) => {
    setTimeout(() => {
      handleNotificationClose(id);
    }, delay);
  }, []);

  // 修改事件处理函数，添加自动移除
  const handleDeviceConnected = useCallback((event: SyncthingEvent) => {
    console.log('设备已连接:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `设备 ${event.data.id} 已连接`;

    // 更新事件通知（3秒后自动消失）
    setEventNotifications(prev => [...prev, {
      id: messageId,
      message,
      severity: 'success'
    }]);

    // 更新持久化消息列表
    setMessageList(prev => [...prev, {
      id: messageId,
      message,
      severity: 'success',
      timestamp: new Date()
    }]);

    // 3秒后自动移除通知
    removeNotificationAfterDelay(messageId, 3000);

    // 刷新设备列表
    loadDevices();
  }, [removeNotificationAfterDelay]);

  const handleDeviceDisconnected = useCallback((event: SyncthingEvent) => {
    console.log('设备已断开:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `设备 ${event.data.id} 已断开连接`;

    setEventNotifications(prev => [...prev, {
      id: messageId,
      message,
      severity: 'warning'
    }]);

    setMessageList(prev => [...prev, {
      id: messageId,
      message,
      severity: 'warning',
      timestamp: new Date()
    }]);

    removeNotificationAfterDelay(messageId, 3000);
    loadDevices();
  }, [removeNotificationAfterDelay]);

  const handleStateChanged = useCallback((event: SyncthingEvent) => {
    console.log('文件夹状态改变:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `文件夹 ${event.data.folder} 状态: ${event.data.to}`;

    setEventNotifications(prev => [...prev, {
      id: messageId,
      message,
      severity: 'info'
    }]);

    setMessageList(prev => [...prev, {
      id: messageId,
      message,
      severity: 'info',
      timestamp: new Date()
    }]);

    removeNotificationAfterDelay(messageId, 3000);
  }, [removeNotificationAfterDelay]);

  const handleItemFinished = useCallback((event: SyncthingEvent) => {
    console.log('文件同步完成:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `文件同步完成: ${event.data.folder}/${event.data.item}`;

    setEventNotifications(prev => [...prev, {
      id: messageId,
      message,
      severity: 'success'
    }]);

    setMessageList(prev => [...prev, {
      id: messageId,
      message,
      severity: 'success',
      timestamp: new Date()
    }]);

    removeNotificationAfterDelay(messageId, 3000);
  }, [removeNotificationAfterDelay]);

  const handleFolderErrors = useCallback((event: SyncthingEvent) => {
    console.log('文件夹错误:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `文件夹 ${event.data.folder} 出现错误`;

    setEventNotifications(prev => [...prev, {
      id: messageId,
      message,
      severity: 'error'
    }]);

    setMessageList(prev => [...prev, {
      id: messageId,
      message,
      severity: 'error',
      timestamp: new Date()
    }]);

    removeNotificationAfterDelay(messageId, 3000);
  }, [removeNotificationAfterDelay]);

  const handleFailure = useCallback((event: SyncthingEvent) => {
    console.log('系统错误:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `系统错误: ${event.data.error}`;

    setEventNotifications(prev => [...prev, {
      id: messageId,
      message,
      severity: 'error'
    }]);

    setMessageList(prev => [...prev, {
      id: messageId,
      message,
      severity: 'error',
      timestamp: new Date()
    }]);

    removeNotificationAfterDelay(messageId, 3000);
  }, [removeNotificationAfterDelay]);

  // 设置事件监听器
  useEffect(() => {
    eventService.addEventListener(EventTypes.DeviceConnected, handleDeviceConnected);
    eventService.addEventListener(EventTypes.DeviceDisconnected, handleDeviceDisconnected);
    eventService.addEventListener(EventTypes.StateChanged, handleStateChanged);
    eventService.addEventListener(EventTypes.ItemFinished, handleItemFinished);
    eventService.addEventListener(EventTypes.FolderErrors, handleFolderErrors);
    eventService.addEventListener(EventTypes.Failure, handleFailure);

    // 启动事件监听
    eventService.start();

    // 定期检查连接状态
    const statusCheckInterval = setInterval(() => {
      setIsEventConnected(eventService.getConnectionStatus());
    }, 1000);

    return () => {
      eventService.removeEventListener(EventTypes.DeviceConnected, handleDeviceConnected);
      eventService.removeEventListener(EventTypes.DeviceDisconnected, handleDeviceDisconnected);
      eventService.removeEventListener(EventTypes.StateChanged, handleStateChanged);
      eventService.removeEventListener(EventTypes.ItemFinished, handleItemFinished);
      eventService.removeEventListener(EventTypes.FolderErrors, handleFolderErrors);
      eventService.removeEventListener(EventTypes.Failure, handleFailure);
      eventService.stop();
      clearInterval(statusCheckInterval);
    };
  }, [eventService, handleDeviceConnected, handleDeviceDisconnected, handleStateChanged, handleItemFinished, handleFolderErrors, handleFailure]);

  useEffect(() => {
    loadDevices();

    // 每30秒自动刷新设备列表以更新连接状态
    const interval = setInterval(() => {
      loadDevices();
    }, 30000);

    return () => clearInterval(interval);
  }, []);

  // 加载设备列表 - 使用原有的 API 服务 (8080 端口)
  const loadDevices = async () => {
    try {
      const resp = await fetch('http://localhost:8080/api/devices');
      if (!resp.ok) throw new Error('API 请求失败');
      const result = await resp.json();
      if (result.code !== 0) throw new Error(result.data || 'API 返回错误');
      setDevices(result.data || []);
    } catch (err) {
      console.error('Failed to load devices:', err);
      setDevices([]);
    }
  };

  const handleSearchChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    setSearchText(event.target.value);
  };

  const handleDeviceClick = (device: Device) => {
    navigate(`/device/${device.deviceID}`);
  };

  const handleMessageDialogOpen = () => {
    setMessageDialogOpen(true);
  };

  const handleMessageDialogClose = () => {
    setMessageDialogOpen(false);
  };

  const clearAllMessages = () => {
    setMessageList([]);
  };

  const removeMessageFromList = (id: string) => {
    setMessageList(prev => prev.filter(message => message.id !== id));
  };

  const getSeverityIcon = (severity: 'success' | 'info' | 'warning' | 'error') => {
    switch (severity) {
      case 'success':
        return <CheckCircleIcon color="success" />;
      case 'info':
        return <InfoIcon color="info" />;
      case 'warning':
        return <WarningIcon color="warning" />;
      case 'error':
        return <ErrorIcon color="error" />;
      default:
        return <InfoIcon />;
    }
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
          {/* 事件连接状态指示器 */}
          <Box sx={{ ml: 2, display: 'flex', alignItems: 'center', gap: 1 }}>
            <Chip
              size="small"
              label={isEventConnected ? '事件已连接' : '事件未连接'}
              color={isEventConnected ? 'success' : 'error'}
              variant={isEventConnected ? 'filled' : 'outlined'}
              sx={{ fontSize: '0.7rem' }}
            />
            <Button
              size="small"
              variant="outlined"
              onClick={() => {
                console.log('手动测试事件监听');
                eventService.start();
              }}
              sx={{
                color: 'white',
                borderColor: 'white',
                '&:hover': {
                  borderColor: 'white',
                  backgroundColor: 'rgba(255, 255, 255, 0.1)',
                }
              }}
            >
              测试连接
            </Button>
            {/* 消息按钮 */}
            <IconButton
              onClick={handleMessageDialogOpen}
              sx={{
                color: 'white',
                border: '1px solid rgba(255, 255, 255, 0.3)',
                '&:hover': {
                  borderColor: 'white',
                  backgroundColor: 'rgba(255, 255, 255, 0.1)',
                }
              }}
            >
              <Badge badgeContent={messageList.length} color="error">
                <NotificationsIcon />
              </Badge>
            </IconButton>
          </Box>
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

      {/* 事件通知 - 改为纵向列表显示 */}
      <Box
        sx={{
          position: 'fixed',
          top: 80, // AppBar 下方留一点空间
          right: 16,
          zIndex: 2000,
          display: 'flex',
          flexDirection: 'column',
          gap: 1,
          maxHeight: 'calc(100vh - 100px)',
          overflow: 'hidden',
        }}
      >
        {eventNotifications.map((notification, index) => (
          <Box
            key={notification.id}
            sx={{
              animation: 'slideInRight 0.3s ease-out',
              '@keyframes slideInRight': {
                '0%': {
                  transform: 'translateX(100%)',
                  opacity: 0,
                },
                '100%': {
                  transform: 'translateX(0)',
                  opacity: 1,
                },
              },
            }}
          >
            <Alert
              onClose={() => handleNotificationClose(notification.id)}
              severity={notification.severity}
              sx={{
                width: 320,
                maxWidth: '90vw',
                boxShadow: 2,
                '& .MuiAlert-message': {
                  wordBreak: 'break-word',
                },
              }}
            >
              {notification.message}
            </Alert>
          </Box>
        ))}
      </Box>

      {/* 消息列表弹框 */}
      <Dialog
        open={messageDialogOpen}
        onClose={handleMessageDialogClose}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <Typography variant="h6">
              事件消息列表 ({messageList.length})
            </Typography>
            <Button
              onClick={clearAllMessages}
              disabled={messageList.length === 0}
              color="error"
              size="small"
            >
              清空所有
            </Button>
          </Box>
        </DialogTitle>
        <DialogContent>
          {messageList.length === 0 ? (
            <Box sx={{ textAlign: 'center', py: 4 }}>
              <NotificationsIcon sx={{ fontSize: 48, color: 'text.secondary', mb: 2 }} />
              <Typography variant="body1" color="text.secondary">
                暂无消息
              </Typography>
              <Typography variant="body2" color="text.secondary">
                当有 syncthing 事件时会显示在这里
              </Typography>
            </Box>
          ) : (
            <List sx={{ width: '100%' }}>
              {messageList.map((message) => (
                <ListItem
                  key={message.id}
                  alignItems="flex-start"
                  sx={{
                    border: '1px solid',
                    borderColor: 'divider',
                    borderRadius: 1,
                    mb: 1,
                    '&:last-child': { mb: 0 }
                  }}
                >
                  <ListItemAvatar>
                    <Avatar sx={{ bgcolor: 'transparent' }}>
                      {getSeverityIcon(message.severity)}
                    </Avatar>
                  </ListItemAvatar>
                  <ListItemText
                    primary={
                      <Typography
                        variant="body1"
                        color="text.primary"
                        sx={{ fontWeight: 500 }}
                      >
                        {message.message}
                      </Typography>
                    }
                    secondary={
                      <Typography
                        variant="caption"
                        color="text.secondary"
                        sx={{ display: 'block', mt: 0.5 }}
                      >
                        {message.timestamp.toLocaleString()} | ID: {message.id}
                      </Typography>
                    }
                  />
                  <IconButton
                    edge="end"
                    onClick={() => removeMessageFromList(message.id)}
                    size="small"
                  >
                    <AddIcon sx={{ transform: 'rotate(45deg)' }} />
                  </IconButton>
                </ListItem>
              ))}
            </List>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={handleMessageDialogClose}>
            关闭
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

export default App;
