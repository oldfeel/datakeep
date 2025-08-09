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
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  FormControlLabel,
  Checkbox,
} from '@mui/material';
import {
  Menu as MenuIcon,
  Search as SearchIcon,
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
  BugReport as BugReportIcon,
} from '@mui/icons-material';
import DeviceDetail from './DeviceDetail';
import FolderDetail from './FolderDetail';
import FilePreview from './FilePreview';
import TestWailsHTTPS from './TestWailsHTTPS';
import { API_CONFIG } from '../config/api';
import { 
  GetHTTPSDevices, 
  GetHTTPSWifiInfo, 
  GetHTTPSDeviceFolders, 
  GetHTTPSSyncthingEvents,
  GetHTTPSSyncthingDeviceID,
  GetHTTPSSyncthingConfigDevices,
  GetHTTPSSyncthingDiscovery,
  PostHTTPSAddDevice
} from '../../wailsjs/go/main/App';
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
  addresses: string[];
  compression: string;
  certName: string;
  introducer: boolean;
  connected: boolean;
  connectionType: string;
  clientVersion: string;
  inBytesTotal: number;
  outBytesTotal: number;
  isLocalNetwork: boolean;
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

  constructor(private baseUrl: string = API_CONFIG.BASE_URL) { }

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
        // 使用 Wails 绑定函数避免证书验证问题
        const eventsData = await GetHTTPSSyncthingEvents(this.lastEventId, 60);
        
        // 将返回的数据转换为 SyncthingEvent 数组
        const events: SyncthingEvent[] = Array.isArray(eventsData) ? eventsData as SyncthingEvent[] : [];

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
function DeviceList({ devices, onDeviceClick, onAddDeviceClick }: {
  devices: Device[],
  onDeviceClick: (device: Device) => void,
  onAddDeviceClick: () => void
}) {
  // 格式化字节数为可读格式
  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  };

  // 判断是否为本机设备
  const isLocalDevice = (device: Device) => {
    return device.connectionType === 'local' || 
           device.clientVersion === 'local' || 
           device.crypto === 'local';
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
    if (isLocalDevice(device)) return '本机设备';
    if (!device.connected) return '离线';
    if (device.isLocalNetwork) return '本地连接';
    switch (device.connectionType) {
      case 'tcp-server': return 'TCP 服务器';
      case 'tcp-client': return 'TCP 客户端';
      case 'quic': return 'QUIC';
      default: return device.connectionType || '未知';
    }
  };

  // 获取设备显示名称
  const getDeviceDisplayName = (device: Device) => {
    if (isLocalDevice(device)) {
      return '本机设备';
    }
    return device.name || device.deviceID;
  };

  return (
    <List>
      {devices.map((device) => {
        const isLocal = isLocalDevice(device);
        return (
          <ListItemButton
            key={device.deviceID}
            onClick={() => onDeviceClick(device)}
            sx={{ 
              flexDirection: 'column', 
              alignItems: 'flex-start', 
              py: 2,
              // 为本机设备添加特殊样式
              ...(isLocal && {
                backgroundColor: 'rgba(25, 118, 210, 0.08)',
                borderLeft: '4px solid #1976d2',
                '&:hover': {
                  backgroundColor: 'rgba(25, 118, 210, 0.12)',
                }
              })
            }}
          >
            <Box sx={{ display: 'flex', alignItems: 'center', width: '100%', mb: 1 }}>
              <ListItemIcon sx={{ minWidth: 40 }}>
                <Badge
                  color={isLocal ? 'primary' : (device.connected ? 'success' : 'error')}
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
                <Typography 
                  variant="body1" 
                  component="span"
                  sx={{
                    fontWeight: isLocal ? 'bold' : 'normal',
                    color: isLocal ? 'primary.main' : 'inherit'
                  }}
                >
                  {getDeviceDisplayName(device)}
                </Typography>
                <Chip
                  size="small"
                  label={getConnectionTypeText(device)}
                  color={isLocal ? 'primary' : (device.connected ? 'success' : 'default')}
                  variant={isLocal ? 'filled' : (device.connected ? 'filled' : 'outlined')}
                  sx={{ 
                    fontSize: '0.7rem', 
                    height: '20px',
                    fontWeight: isLocal ? 'bold' : 'normal'
                  }}
                />
              </Box>
            </Box>

            <Box sx={{ pl: 6, width: '100%' }}>
              {device.connected && !isLocal && (
                <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 1 }}>
                  <Typography variant="caption" color="text.secondary" component="span">
                    接收: {formatBytes(device.inBytesTotal)}
                  </Typography>
                  <Typography variant="caption" color="text.secondary" component="span">
                    发送: {formatBytes(device.outBytesTotal)}
                  </Typography>
                </Box>
              )}
              {isLocal && (
                <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', mb: 1 }}>
                  <Typography variant="caption" color="primary.main" component="span">
                    本地设备 - 无需网络连接
                  </Typography>
                </Box>
              )}
              {device.addresses && device.addresses.length > 0 && !isLocal && (
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
        );
      })}
      <Divider />
      <ListItem>
        <Button
          fullWidth
          variant="outlined"
          startIcon={<AddIcon />}
          onClick={onAddDeviceClick}
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
  const [addDeviceDialogOpen, setAddDeviceDialogOpen] = useState(false);
  const [newDevice, setNewDevice] = useState({
    deviceID: '',
    name: ''
  });
  const [deviceValidation, setDeviceValidation] = useState({
    isValid: false,
    isUnique: true,
    error: ''
  });
  const [discoveryUnknown, setDiscoveryUnknown] = useState<string[]>([]);
  const [nearbyDevices, setNearbyDevices] = useState<Array<{ id: string, name?: string }>>([]);
  const [wifiName, setWifiName] = useState<string>('');
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



  // 获取WiFi信息
  const getWifiInfo = useCallback(async () => {
    try {
      const result = await GetHTTPSWifiInfo();
      if (result && typeof result === 'object' && 'code' in result && result.code === 0) {
        setWifiName(result.data.wifiName);
      }
    } catch (error) {
      console.error('获取WiFi信息失败:', error);
      setWifiName('获取失败');
    }
  }, []);

  // 加载设备列表 - 使用 Wails 绑定调用 HTTPS API
  const loadDevices = useCallback(async () => {
    try {
      console.log('开始加载设备列表...');
      const result = await GetHTTPSDevices();
      if (result && typeof result === 'object' && 'code' in result && result.code !== 0) {
        throw new Error(result.data || 'API 返回错误');
      }
      const devicesData = result?.data || [];
      console.log('设备列表加载成功，设备数量:', devicesData.length);
      
      setDevices(devicesData);
      return devicesData;
    } catch (err) {
      console.error('Failed to load devices:', err);
      setDevices([]);
      throw err;
    }
  }, []);

  // 修改事件处理函数，添加自动移除
  const handleDeviceConnected = useCallback(async (event: SyncthingEvent) => {
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
    await loadDevices();
  }, [removeNotificationAfterDelay, loadDevices]);

  const handleDeviceDisconnected = useCallback(async (event: SyncthingEvent) => {
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
    await loadDevices();
  }, [removeNotificationAfterDelay, loadDevices]);

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

  // 处理配置保存事件 - 当设备被移除时会触发此事件
  const handleConfigSaved = useCallback(async (event: SyncthingEvent) => {
    console.log('配置已保存:', event.data);
    const messageId = `${event.id}-${event.globalID}-${Date.now()}-${Math.random()}`;
    const message = `配置已保存`;

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

    // 配置保存后刷新设备列表
    await loadDevices();
  }, [removeNotificationAfterDelay, loadDevices]);

  // 设置事件监听器
  useEffect(() => {
    eventService.addEventListener(EventTypes.DeviceConnected, handleDeviceConnected);
    eventService.addEventListener(EventTypes.DeviceDisconnected, handleDeviceDisconnected);
    eventService.addEventListener(EventTypes.StateChanged, handleStateChanged);
    eventService.addEventListener(EventTypes.ItemFinished, handleItemFinished);
    eventService.addEventListener(EventTypes.FolderErrors, handleFolderErrors);
    eventService.addEventListener(EventTypes.Failure, handleFailure);
    eventService.addEventListener(EventTypes.ConfigSaved, handleConfigSaved);

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
      eventService.removeEventListener(EventTypes.ConfigSaved, handleConfigSaved);
      eventService.stop();
      clearInterval(statusCheckInterval);
    };
  }, [eventService, handleDeviceConnected, handleDeviceDisconnected, handleStateChanged, handleItemFinished, handleFolderErrors, handleFailure, handleConfigSaved]);

  // 加载设备列表和WiFi信息
  useEffect(() => {
    loadDevices();
    getWifiInfo();

    // 每30秒自动刷新设备列表以更新连接状态
    const interval = setInterval(() => {
      loadDevices();
    }, 30000);

    // 每60秒刷新WiFi信息
    const wifiInterval = setInterval(() => {
      getWifiInfo();
    }, 60000);

    return () => {
      clearInterval(interval);
      clearInterval(wifiInterval);
    };
  }, [loadDevices, getWifiInfo]);

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

  // 修正的设备添加相关函数
  const handleAddDeviceClick = async () => {
    setAddDeviceDialogOpen(true);
    // 重置表单
    setNewDevice({
      deviceID: '',
      name: ''
    });
    setDeviceValidation({
      isValid: false,
      isUnique: true,
      error: ''
    });

    // 获取附近发现的设备 - 使用代理接口避免跨域问题
    try {
      const response = await fetch('http://localhost:8080/api/syncthing/discovery');
      if (response.ok) {
        const data = await response.json();
        // 过滤掉已添加的设备，只保留未添加的设备
        const unknownDevices = Object.keys(data).filter(id =>
          !devices.some(device => device.deviceID === id)
        ).slice(0, 5); // 只显示前5个
        setDiscoveryUnknown(unknownDevices);
      }
    } catch (error) {
      console.log('无法获取附近设备:', error);
      setDiscoveryUnknown([]);
    }
  };

  const handleAddDeviceClose = () => {
    setAddDeviceDialogOpen(false);
  };

  const handleSelectNearbyDevice = (deviceID: string) => {
    setNewDevice(prev => ({ ...prev, deviceID }));
    validateDeviceID(deviceID);
  };

  const validateDeviceID = async (deviceID: string) => {
    const cleanID = deviceID.replace(/[\s-]/g, '');

    // Syncthing 设备 ID 格式：8组，每组7个字符，总共56个字符
    if (cleanID.length !== 56) {
      setDeviceValidation({
        isValid: false,
        isUnique: true,
        error: '设备 ID 长度必须为 56 位（8组，每组7个字符）'
      });
      return;
    }

    if (!/^[A-Z0-9]+$/.test(cleanID)) {
      setDeviceValidation({
        isValid: false,
        isUnique: true,
        error: '设备 ID 只能包含大写字母和数字'
      });
      return;
    }

    // 验证设备 ID 有效性（通过 Wails 绑定）
    try {
      const result = await GetHTTPSSyncthingDeviceID(cleanID);

      if (result && typeof result === 'object' && 'error' in result && result.error) {
        setDeviceValidation({
          isValid: false,
          isUnique: true,
          error: '设备 ID 格式无效'
        });
      } else {
        setDeviceValidation({
          isValid: true,
          isUnique: true,
          error: ''
        });
      }
    } catch (error) {
      // 如果 API 调用失败，使用基本验证
      setDeviceValidation({
        isValid: true,
        isUnique: true,
        error: ''
      });
    }
  };

  const handleDeviceIDChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const value = event.target.value;
    setNewDevice(prev => ({ ...prev, deviceID: value }));
    validateDeviceID(value);
  };

  const handleSaveDevice = async () => {
    if (!deviceValidation.isValid) {
      return;
    }

    try {
      // 构建设备配置（使用默认值）
      const deviceConfig = {
        deviceID: newDevice.deviceID.replace(/[\s-]/g, ''),
        name: newDevice.name,
        addresses: ['dynamic'], // 默认使用动态发现
        compression: 'metadata', // 默认元数据压缩
        introducer: false,
        autoAcceptFolders: false,
        untrusted: false,
        numConnections: 0,
        maxRecvKbps: 0,
        maxSendKbps: 0
      };

      // 调用 Wails 绑定添加设备
      const result = await PostHTTPSAddDevice(JSON.stringify(deviceConfig));

      if (result && typeof result === 'object' && 'error' in result && result.error) {
        throw new Error('添加设备失败');
      }

      // 添加成功
      setEventNotifications(prev => [...prev, {
        id: `${Date.now()}-${Math.random()}`,
        message: `设备 ${deviceConfig.name || deviceConfig.deviceID} 添加成功`,
        severity: 'success'
      }]);

      setMessageList(prev => [...prev, {
        id: `${Date.now()}-${Math.random()}`,
        message: `设备 ${deviceConfig.name || deviceConfig.deviceID} 添加成功`,
        severity: 'success',
        timestamp: new Date()
      }]);

      // 刷新设备列表
      loadDevices();

      // 关闭弹框
      setAddDeviceDialogOpen(false);
    } catch (error) {
      console.error('添加设备失败:', error);
      setEventNotifications(prev => [...prev, {
        id: `${Date.now()}-${Math.random()}`,
        message: `添加设备失败: ${error instanceof Error ? error.message : '未知错误'}`,
        severity: 'error'
      }]);

      setMessageList(prev => [...prev, {
        id: `${Date.now()}-${Math.random()}`,
        message: `添加设备失败: ${error instanceof Error ? error.message : '未知错误'}`,
        severity: 'error',
        timestamp: new Date()
      }]);
    }
  };

  // 获取附近设备列表
  const loadNearbyDevices = async () => {
    try {
      const data = await GetHTTPSSyncthingDiscovery();

      // 处理发现的数据，提取未知设备
      const unknownDevices: Array<{ id: string, name?: string }> = [];
      if (data && typeof data === 'object') {
        Object.keys(data).forEach(deviceId => {
          // 检查是否已存在该设备
          const existingDevice = devices.find(d => d.deviceID === deviceId);
          if (!existingDevice) {
            unknownDevices.push({ id: deviceId });
          }
        });
      }

      setNearbyDevices(unknownDevices);
    } catch (error) {
      console.error('获取附近设备失败:', error);
      setNearbyDevices([]);
    }
  };

  // 验证设备 ID 格式
  const validateDeviceId = async (deviceId: string) => {
    const cleanID = deviceId.replace(/[^A-Z0-9]/g, '');
    if (cleanID.length !== 63) {
      return false;
    }

    try {
      // 使用 Wails 绑定验证设备 ID
      const result = await GetHTTPSSyncthingDeviceID(cleanID);
      return result && typeof result === 'object' && !('error' in result);
    } catch (error) {
      console.error('设备 ID 验证失败:', error);
      return false;
    }
  };

  // 添加设备
  const handleAddDevice = async () => {
    if (!newDevice.deviceID.trim()) {
      setDeviceValidation({
        isValid: false,
        isUnique: true,
        error: '请输入设备 ID'
      });
      return;
    }

    try {
      // 使用 Wails 绑定获取设备列表
      const devices = await GetHTTPSSyncthingConfigDevices();

      // 检查设备是否已存在
      const deviceExists = devices.some((device: any) => device.deviceID === newDevice.deviceID);
      if (deviceExists) {
        setDeviceValidation({
          isValid: false,
          isUnique: false,
          error: '设备已存在'
        });
        return;
      }

      // 这里可以添加实际的设备添加逻辑
      console.log('添加设备:', { id: newDevice.deviceID, name: newDevice.name });

      // 清空表单并关闭弹框
      setNewDevice({
        deviceID: '',
        name: ''
      });
      setDeviceValidation({
        isValid: true,
        isUnique: true,
        error: ''
      });
      setAddDeviceDialogOpen(false);

      // 刷新设备列表
      loadDevices();

    } catch (error) {
      console.error('添加设备失败:', error);
      setDeviceValidation({
        isValid: false,
        isUnique: true,
        error: '添加设备失败: ' + (error as Error).message
      });
    }
  };

  return (
    <Box sx={{ display: 'flex', height: '100vh' }}>
      {/* 顶部 AppBar */}
      <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }}>
        <Toolbar>
          <Box sx={{ display: 'flex', alignItems: 'center', flexGrow: 0, mr: 2 }}>
            <Typography
              variant="h6"
              noWrap
              component="div"
              sx={{ cursor: 'pointer' }}
              onClick={() => navigate('/')}
            >
              我的数据
            </Typography>
            {wifiName && (
              <Typography
                variant="caption"
                sx={{ 
                  ml: 1, 
                  color: 'rgba(255, 255, 255, 0.7)',
                  fontSize: '0.75rem',
                  fontWeight: 400,
                  marginTop: 1
                }}
              >
                当前wifi: {wifiName}
              </Typography>
            )}
          </Box>
          <TextField
            size="small"
            placeholder="搜索设备或文件夹..."
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
          {/* 测试按钮 */}
          <IconButton
            onClick={() => navigate('/test-https')}
            sx={{
              color: 'white',
              border: '1px solid rgba(255, 255, 255, 0.3)',
              mr: 1,
              '&:hover': {
                borderColor: 'white',
                backgroundColor: 'rgba(255, 255, 255, 0.1)',
              }
            }}
          >
            <BugReportIcon />
          </IconButton>
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
        <DeviceList
          devices={filteredDevices}
          onDeviceClick={handleDeviceClick}
          onAddDeviceClick={handleAddDeviceClick}
        />
      </Drawer>

      {/* 主内容区域 */}
      <Box component="main" sx={{ flexGrow: 1, p: 3, marginTop: '64px' }}>
        <Routes>
          <Route path="/" element={<Navigate to="/device/local" replace />} />
          <Route path="/device/:deviceId" element={<DeviceDetail />} />
          <Route path="/folder/:deviceId/:folderId" element={<FolderDetail />} />
          <Route path="/preview/:deviceId/:folderId/:filePath" element={<FilePreview />} />
          <Route path="/test-https" element={<TestWailsHTTPS />} />
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

      {/* 完整的设备添加弹框 */}
      <Dialog
        open={addDeviceDialogOpen}
        onClose={handleAddDeviceClose}
        maxWidth="md"
        fullWidth
      >
        <DialogTitle>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <AddIcon />
            <Typography variant="h6">添加设备</Typography>
          </Box>
        </DialogTitle>
        <DialogContent>
          <Box sx={{ mt: 2 }}>
            {/* 设备 ID 部分 */}
            <Typography variant="h6" sx={{ mb: 2 }}>设备 ID</Typography>

            <TextField
              fullWidth
              label="设备 ID"
              value={newDevice.deviceID}
              onChange={handleDeviceIDChange}
              error={!deviceValidation.isValid && newDevice.deviceID !== ''}
              helperText={
                deviceValidation.error ||
                '在此处输入的设备 ID 可以在另一台设备的"操作 > 显示 ID"对话框中找到。空格和破折号是可选的（忽略）。'
              }
              sx={{ mb: 2 }}
              placeholder="例如: ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ"
            />

            {/* 附近设备选择 */}
            {discoveryUnknown.length > 0 && (
              <Box sx={{ mb: 3 }}>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                  您还可以选择以下附近的设备之一：
                </Typography>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                  {discoveryUnknown.map((deviceID) => (
                    <Button
                      key={deviceID}
                      variant="outlined"
                      size="small"
                      onClick={() => handleSelectNearbyDevice(deviceID)}
                      sx={{
                        justifyContent: 'flex-start',
                        textTransform: 'none',
                        fontFamily: 'monospace',
                        fontSize: '0.8rem',
                        py: 1,
                        px: 2
                      }}
                    >
                      {deviceID}
                    </Button>
                  ))}
                </Box>
              </Box>
            )}

            {/* 设备名称部分 */}
            <Typography variant="h6" sx={{ mb: 2 }}>设备名称</Typography>

            <TextField
              fullWidth
              label="设备名称"
              value={newDevice.name}
              onChange={(e) => setNewDevice(prev => ({ ...prev, name: e.target.value }))}
              helperText="在集群状态中显示该名称，而不是设备 ID。如果留空，将更新为设备通告的名称。"
              sx={{ mb: 2 }}
              placeholder="例如: 我的手机"
            />

            {/* 提示信息 */}
            <Alert severity="info" sx={{ mt: 2 }}>
              <Typography variant="body2">
                若您在本机添加新设备，记住您也必须在这个新设备上添加本机。
              </Typography>
            </Alert>
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleAddDeviceClose}>
            取消
          </Button>
          <Button
            onClick={handleSaveDevice}
            disabled={!deviceValidation.isValid}
            variant="contained"
            color="primary"
          >
            添加设备
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

export default App;
