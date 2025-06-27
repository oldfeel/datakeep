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
  IconButton,
  Tooltip,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  FormControlLabel,
  Checkbox,
  Tabs,
  Tab,
  Divider,
  Chip,
} from '@mui/material';
import {
  Folder as FolderIcon,
  Home as HomeIcon,
  Edit as EditIcon,
  Save as SaveIcon,
  Close as CloseIcon,
  Delete as DeleteIcon,
  Settings as SettingsIcon,
  Share as ShareIcon,
  FilterList as FilterListIcon,
} from '@mui/icons-material';

interface Folder {
  id: string;
  label: string;
  path: string;
  type?: string;
  paused?: boolean;
  rescanIntervalS?: number;
  fsWatcherEnabled?: boolean;
  ignorePerms?: boolean;
  autoNormalize?: boolean;
  minDiskFree?: {
    value: number;
    unit: string;
  };
  versioning?: {
    type: string;
    params: any;
  };
  devices?: Array<{
    deviceID: string;
    introducer?: boolean;
    encryptionPassword?: string;
  }>;
}

interface Device {
  deviceID: string;
  name: string;
  addresses?: string[] | null;
  connected: boolean;
  isLocal: boolean;
}

// 文件夹编辑弹框组件
function FolderEditDialog({
  open,
  folder,
  onClose,
  onSave,
  onDelete
}: {
  open: boolean;
  folder: Folder | null;
  onClose: () => void;
  onSave: (folder: Folder) => void;
  onDelete: (folderId: string) => void;
}) {
  const [activeTab, setActiveTab] = useState(0);
  const [editedFolder, setEditedFolder] = useState<Folder | null>(null);

  useEffect(() => {
    if (folder) {
      setEditedFolder({ ...folder });
    }
  }, [folder]);

  const handleSave = () => {
    if (editedFolder) {
      onSave(editedFolder);
    }
  };

  const handleDelete = () => {
    if (editedFolder) {
      onDelete(editedFolder.id);
    }
  };

  if (!editedFolder) return null;

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <EditIcon />
          <Typography variant="h6">编辑文件夹</Typography>
          {editedFolder.label && (
            <Chip label={editedFolder.label} size="small" color="primary" />
          )}
        </Box>
      </DialogTitle>

      <DialogContent>
        <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 2 }}>
          <Tabs value={activeTab} onChange={(_, newValue) => setActiveTab(newValue)}>
            <Tab icon={<SettingsIcon />} label="常规" />
            <Tab icon={<ShareIcon />} label="共享" />
            <Tab icon={<FilterListIcon />} label="忽略模式" />
            <Tab icon={<SettingsIcon />} label="高级" />
          </Tabs>
        </Box>

        {/* 常规设置 */}
        {activeTab === 0 && (
          <Box sx={{ p: 1 }}>
            <TextField
              fullWidth
              label="文件夹标签"
              value={editedFolder.label || ''}
              onChange={(e) => setEditedFolder(prev => prev ? { ...prev, label: e.target.value } : null)}
              margin="normal"
              helperText="可选的描述性标签，在每个设备上可以不同"
            />

            <TextField
              fullWidth
              label="文件夹 ID"
              value={editedFolder.id || ''}
              disabled
              margin="normal"
              helperText="文件夹的唯一标识符，在所有集群设备上必须相同"
            />

            <TextField
              fullWidth
              label="文件夹路径"
              value={editedFolder.path || ''}
              disabled
              margin="normal"
              helperText="本地计算机上的文件夹路径"
            />
          </Box>
        )}

        {/* 共享设置 */}
        {activeTab === 1 && (
          <Box sx={{ p: 1 }}>
            <Typography variant="subtitle1" gutterBottom>
              共享设备
            </Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              选择要与哪些设备共享此文件夹
            </Typography>

            {editedFolder.devices?.map((device) => (
              <Chip
                key={device.deviceID}
                label={device.deviceID}
                variant="outlined"
                sx={{ m: 0.5 }}
              />
            )) || (
                <Typography variant="body2" color="text.secondary">
                  未配置共享设备
                </Typography>
              )}
          </Box>
        )}

        {/* 忽略模式 */}
        {activeTab === 2 && (
          <Box sx={{ p: 1 }}>
            <Typography variant="subtitle1" gutterBottom>
              忽略模式
            </Typography>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              配置要忽略的文件和文件夹模式
            </Typography>

            <TextField
              fullWidth
              multiline
              rows={8}
              label="忽略模式"
              placeholder="输入要忽略的文件模式，每行一个&#10;例如：&#10;*.tmp&#10;.DS_Store&#10;node_modules/"
              margin="normal"
              helperText="使用 glob 模式语法，每行一个模式"
            />
          </Box>
        )}

        {/* 高级设置 */}
        {activeTab === 3 && (
          <Box sx={{ p: 1 }}>
            <Typography variant="subtitle1" gutterBottom>
              高级设置
            </Typography>

            <FormControl fullWidth margin="normal">
              <InputLabel>文件夹类型</InputLabel>
              <Select
                value={editedFolder.type || 'sendreceive'}
                onChange={(e) => setEditedFolder(prev => prev ? { ...prev, type: e.target.value } : null)}
                label="文件夹类型"
              >
                <MenuItem value="sendreceive">发送和接收</MenuItem>
                <MenuItem value="sendonly">仅发送</MenuItem>
                <MenuItem value="receiveonly">仅接收</MenuItem>
                <MenuItem value="receiveencrypted">接收加密</MenuItem>
              </Select>
            </FormControl>

            <FormControlLabel
              control={
                <Checkbox
                  checked={editedFolder.fsWatcherEnabled || false}
                  onChange={(e) => setEditedFolder(prev => prev ? { ...prev, fsWatcherEnabled: e.target.checked } : null)}
                />
              }
              label="监视文件变化"
            />

            <TextField
              fullWidth
              type="number"
              label="完整扫描间隔（秒）"
              value={editedFolder.rescanIntervalS || 3600}
              onChange={(e) => setEditedFolder(prev => prev ? { ...prev, rescanIntervalS: parseInt(e.target.value) || 3600 } : null)}
              margin="normal"
              helperText="定期扫描文件夹以检测变化的间隔时间"
            />

            <FormControlLabel
              control={
                <Checkbox
                  checked={editedFolder.ignorePerms || false}
                  onChange={(e) => setEditedFolder(prev => prev ? { ...prev, ignorePerms: e.target.checked } : null)}
                />
              }
              label="忽略权限"
            />
          </Box>
        )}
      </DialogContent>

      <DialogActions>
        <Button
          onClick={handleDelete}
          color="error"
          startIcon={<DeleteIcon />}
          sx={{ mr: 'auto' }}
        >
          删除
        </Button>
        <Button onClick={onClose} startIcon={<CloseIcon />}>
          取消
        </Button>
        <Button
          onClick={handleSave}
          variant="contained"
          startIcon={<SaveIcon />}
        >
          保存
        </Button>
      </DialogActions>
    </Dialog>
  );
}

// 文件夹列表组件
function FolderList({ folders, deviceName, deviceId }: { folders: Folder[] | null, deviceName: string, deviceId: string }) {
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [selectedFolder, setSelectedFolder] = useState<Folder | null>(null);

  const handleEditFolder = (folder: Folder, event: React.MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();
    setSelectedFolder(folder);
    setEditDialogOpen(true);
  };

  const handleSaveFolder = (updatedFolder: Folder) => {
    console.log('保存文件夹:', updatedFolder);
    // 这里可以添加保存文件夹的逻辑
    setEditDialogOpen(false);
  };

  const handleDeleteFolder = (folderId: string) => {
    console.log('删除文件夹:', folderId);
    // 这里可以添加删除文件夹的逻辑
    setEditDialogOpen(false);
  };

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
    <>
      <Grid container spacing={2}>
        {folders.map((folder) => (
          <Grid item xs={12} sm={6} md={4} key={folder.id}>
            <Card
              sx={{
                height: '100%',
                display: 'flex',
                flexDirection: 'column',
                position: 'relative',
                '&:hover': {
                  boxShadow: 6,
                },
              }}
            >
              {/* 编辑按钮 - 位于右上角 */}
              <Box
                sx={{
                  position: 'absolute',
                  top: 8,
                  right: 8,
                  zIndex: 1,
                  backgroundColor: 'rgba(255, 255, 255, 0.9)',
                  borderRadius: '50%',
                  '&:hover': {
                    backgroundColor: 'rgba(255, 255, 255, 1)',
                  },
                }}
              >
                <Tooltip title="编辑文件夹">
                  <IconButton
                    size="small"
                    onClick={(e) => handleEditFolder(folder, e)}
                    sx={{
                      color: 'primary.main',
                      '&:hover': {
                        backgroundColor: 'rgba(25, 118, 210, 0.1)',
                      },
                    }}
                  >
                    <EditIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              </Box>

              <CardActionArea
                component={Link}
                to={`/folder/${deviceId}/${folder.id}`}
                sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column', alignItems: 'stretch' }}
              >
                <CardContent sx={{ flexGrow: 1, pt: 3 }}>
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

      {/* 文件夹编辑弹框 */}
      <FolderEditDialog
        open={editDialogOpen}
        folder={selectedFolder}
        onClose={() => setEditDialogOpen(false)}
        onSave={handleSaveFolder}
        onDelete={handleDeleteFolder}
      />
    </>
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
          console.log('Found device:', foundDevice);
          if (foundDevice) {
            setDeviceName(foundDevice.name || foundDevice.deviceID);
            setDevice(foundDevice);
            console.log('Device addresses:', foundDevice.addresses);
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
      if (!device) return;

      try {
        setLoading(true);
        setError(null);

        console.log('Current device:', device);
        console.log('Device addresses:', device.addresses || []);
        console.log('Device isLocal:', device.isLocal);

        let apiUrl: string;
        if (deviceId === 'local') {
          apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
          console.log('Using local API');
        } else if (device.addresses && device.addresses.length > 0) {
          const ipAddresses = device.addresses.filter(addr => {
            const ipv4Regex = /^(\d{1,3}\.){3}\d{1,3}$/;
            return ipv4Regex.test(addr) &&
              !addr.includes('[') &&
              !addr.includes('relay://') &&
              !addr.includes('quic://');
          });

          if (ipAddresses.length > 0) {
            console.log('All available IPv4 addresses:', ipAddresses);

            let selectedIp = null;

            const lan192_2Addresses = ipAddresses.filter(ip => ip.startsWith('192.168.2.'));
            if (lan192_2Addresses.length > 0) {
              selectedIp = lan192_2Addresses[0];
              console.log('Found 192.168.2.x addresses:', lan192_2Addresses);
              console.log('Selected primary LAN IP (192.168.2.x):', selectedIp);
            } else {
              const lan192Addresses = ipAddresses.filter(ip => ip.startsWith('192.168.'));
              if (lan192Addresses.length > 0) {
                selectedIp = lan192Addresses[0];
                console.log('Found other 192.168.x.x addresses:', lan192Addresses);
                console.log('Selected LAN IP (192.168.x.x):', selectedIp);
              } else {
                const lan10Addresses = ipAddresses.filter(ip => ip.startsWith('10.'));
                if (lan10Addresses.length > 0) {
                  selectedIp = lan10Addresses[0];
                  console.log('Found 10.x.x.x addresses:', lan10Addresses);
                  console.log('Selected LAN IP (10.x.x.x):', selectedIp);
                } else {
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
                    selectedIp = ipAddresses[0];
                    console.log('No LAN addresses found, using fallback IP:', selectedIp);
                  }
                }
              }
            }

            if (selectedIp) {
              apiUrl = `http://${selectedIp}:8080/api/device/${deviceId}/folders`;
              console.log('Using remote API with IP:', selectedIp);
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