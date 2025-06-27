import React, { useState, useEffect } from 'react';
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
  Snackbar,
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
  Add as AddIcon,
} from '@mui/icons-material';
import { GetDeviceFolders, GetFolders, SelectFolder } from '../../wailsjs/go/main/App';

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

// 生成随机文件夹 ID
function generateFolderId(): string {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < 10; i++) {
    if (i === 5) result += '-';
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

// 文件夹编辑弹框组件
function FolderEditDialog({
  open,
  folder,
  onClose,
  onSave,
  onDelete,
  isAddMode = false
}: {
  open: boolean;
  folder: Folder | null;
  onClose: () => void;
  onSave: (folder: Folder) => void;
  onDelete: (folderId: string) => void;
  isAddMode?: boolean;
}) {
  const [activeTab, setActiveTab] = useState(0);
  const [editedFolder, setEditedFolder] = useState<Folder | null>(null);
  const [snackbar, setSnackbar] = useState<{
    open: boolean;
    message: string;
    severity: 'success' | 'error' | 'warning' | 'info';
  }>({
    open: false,
    message: '',
    severity: 'success'
  });

  const [deleteConfirmOpen, setDeleteConfirmOpen] = useState(false);

  useEffect(() => {
    if (folder) {
      setEditedFolder({ ...folder });
    } else if (isAddMode) {
      // 创建新的文件夹配置
      setEditedFolder({
        id: generateFolderId(),
        label: '',
        path: '',
        type: 'sendreceive',
        paused: false,
        rescanIntervalS: 3600,
        fsWatcherEnabled: true,
        ignorePerms: false,
        autoNormalize: true,
        minDiskFree: {
          value: 1,
          unit: '%'
        },
        versioning: {
          type: 'none',
          params: {}
        },
        devices: []
      });
    }
  }, [folder, isAddMode]);

  const handleSave = () => {
    if (editedFolder) {
      onSave(editedFolder);
    }
  };

  const handleDelete = () => {
    if (editedFolder) {
      setDeleteConfirmOpen(true);
    }
  };

  const handleConfirmDelete = () => {
    if (editedFolder) {
      onDelete(editedFolder.id);
      setDeleteConfirmOpen(false);
    }
  };

  const handleCancelDelete = () => {
    setDeleteConfirmOpen(false);
  };

  const handleSelectFolder = async () => {
    try {
      const selectedPath = await SelectFolder();
      if (selectedPath) {
        setEditedFolder(prev => prev ? { ...prev, path: selectedPath } : null);
        setSnackbar({
          open: true,
          message: `✅ 文件夹选择成功！\n\n路径: ${selectedPath}`,
          severity: 'success'
        });
      }
    } catch (error) {
      console.error('选择文件夹失败:', error);
      setSnackbar({
        open: true,
        message: '文件夹选择失败，请手动输入路径',
        severity: 'error'
      });
    }
  };

  if (!editedFolder) return null;

  return (
    <>
      <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
        <DialogTitle>
          {isAddMode ? '添加文件夹' : '编辑文件夹'}
        </DialogTitle>
        <DialogContent>
          {/* 标签页 */}
          <Box sx={{ borderBottom: 1, borderColor: 'divider', mb: 2 }}>
            <Tabs value={activeTab} onChange={(e, newValue) => setActiveTab(newValue)}>
              <Tab label="基本设置" />
              <Tab label="共享设置" />
              <Tab label="忽略模式" />
              <Tab label="高级设置" />
            </Tabs>
          </Box>

          {/* 基本设置 */}
          {activeTab === 0 && (
            <Box sx={{ p: 1 }}>
              <TextField
                fullWidth
                label="文件夹名称"
                value={editedFolder.label}
                onChange={(e) => setEditedFolder(prev => prev ? { ...prev, label: e.target.value } : null)}
                margin="normal"
                helperText="为文件夹指定一个易于识别的名称"
              />

              <Box sx={{ mt: 2, mb: 1 }}>
                <Typography variant="subtitle2" gutterBottom>
                  文件夹路径
                </Typography>
                <Box sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
                  <TextField
                    fullWidth
                    label="文件夹路径"
                    value={editedFolder.path}
                    onChange={(e) => setEditedFolder(prev => prev ? { ...prev, path: e.target.value } : null)}
                    margin="normal"
                    helperText="本地计算机上的文件夹路径"
                    disabled={!isAddMode}
                  />
                  {isAddMode && (
                    <Button
                      variant="outlined"
                      size="small"
                      onClick={handleSelectFolder}
                      startIcon={<FolderIcon />}
                      sx={{
                        minWidth: 'auto',
                        px: 2,
                        height: '56px',
                        borderColor: 'rgba(0, 0, 0, 0.23)',
                        '&:hover': {
                          borderColor: 'rgba(0, 0, 0, 0.87)',
                        }
                      }}
                    >
                      浏览
                    </Button>
                  )}
                </Box>
                {isAddMode && (
                  <Box sx={{ mt: 1, p: 1, bgcolor: 'grey.50', borderRadius: 1 }}>
                    <Typography variant="caption" color="text.secondary">
                      <strong>路径格式提示：</strong><br />
                      • Linux/Mac: /home/username/foldername 或 ~/foldername<br />
                      • Windows: C:\\Users\\username\\foldername 或 D:\\foldername<br />
                      • 相对路径: ./foldername 或 ../foldername
                    </Typography>
                  </Box>
                )}
              </Box>

              <FormControl fullWidth margin="normal">
                <InputLabel>文件夹类型</InputLabel>
                <Select
                  value={editedFolder.type || 'sendreceive'}
                  onChange={(e) => setEditedFolder(prev => prev ? { ...prev, type: e.target.value } : null)}
                  disabled={!isAddMode}
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
                    checked={editedFolder.paused || false}
                    onChange={(e) => setEditedFolder(prev => prev ? { ...prev, paused: e.target.checked } : null)}
                  />
                }
                label="暂停同步"
                sx={{ mt: 1 }}
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
                rows={4}
                label="忽略模式"
                placeholder="每行一个模式，例如：*.tmp&#10;.DS_Store&#10;node_modules/"
                margin="normal"
              />
            </Box>
          )}

          {/* 高级设置 */}
          {activeTab === 3 && (
            <Box sx={{ p: 1 }}>
              <Typography variant="subtitle1" gutterBottom>
                高级设置
              </Typography>

              <TextField
                fullWidth
                type="number"
                label="重新扫描间隔（秒）"
                value={editedFolder.rescanIntervalS || 3600}
                onChange={(e) => setEditedFolder(prev => prev ? { ...prev, rescanIntervalS: parseInt(e.target.value) || 3600 } : null)}
                margin="normal"
                helperText="自动重新扫描文件夹的间隔时间"
              />

              <FormControlLabel
                control={
                  <Checkbox
                    checked={editedFolder.fsWatcherEnabled || false}
                    onChange={(e) => setEditedFolder(prev => prev ? { ...prev, fsWatcherEnabled: e.target.checked } : null)}
                  />
                }
                label="启用文件系统监视器"
                sx={{ mt: 1 }}
              />

              <FormControlLabel
                control={
                  <Checkbox
                    checked={editedFolder.ignorePerms || false}
                    onChange={(e) => setEditedFolder(prev => prev ? { ...prev, ignorePerms: e.target.checked } : null)}
                  />
                }
                label="忽略权限"
                sx={{ mt: 1 }}
              />

              <FormControlLabel
                control={
                  <Checkbox
                    checked={editedFolder.autoNormalize || false}
                    onChange={(e) => setEditedFolder(prev => prev ? { ...prev, autoNormalize: e.target.checked } : null)}
                  />
                }
                label="自动标准化文件名"
                sx={{ mt: 1 }}
              />
            </Box>
          )}
        </DialogContent>

        <DialogActions>
          {!isAddMode && (
            <Button
              onClick={handleDelete}
              color="error"
              startIcon={<DeleteIcon />}
            >
              删除
            </Button>
          )}
          <Box sx={{ flexGrow: 1 }} />
          <Button onClick={onClose} startIcon={<CloseIcon />}>
            取消
          </Button>
          <Button
            onClick={handleSave}
            variant="contained"
            startIcon={<SaveIcon />}
            disabled={!editedFolder.label || !editedFolder.path}
          >
            {isAddMode ? '添加' : '保存'}
          </Button>
        </DialogActions>
      </Dialog>

      <Snackbar
        open={snackbar.open}
        autoHideDuration={6000}
        onClose={() => setSnackbar(prev => ({ ...prev, open: false }))}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
      >
        <Alert
          onClose={() => setSnackbar(prev => ({ ...prev, open: false }))}
          severity={snackbar.severity}
          sx={{ width: '100%' }}
        >
          {snackbar.message}
        </Alert>
      </Snackbar>

      {/* 删除确认对话框 */}
      <Dialog
        open={deleteConfirmOpen}
        onClose={handleCancelDelete}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle sx={{ pb: 1 }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <DeleteIcon color="error" />
            <Typography variant="h6">确认删除文件夹</Typography>
          </Box>
        </DialogTitle>
        <DialogContent>
          <Typography variant="body1" sx={{ mb: 2 }}>
            确定要删除以下文件夹吗？此操作无法撤销。
          </Typography>
          <Box sx={{ bgcolor: 'grey.50', p: 2, borderRadius: 1, mb: 2 }}>
            <Typography variant="subtitle2" color="text.secondary" gutterBottom>
              文件夹名称
            </Typography>
            <Typography variant="body1" sx={{ mb: 1 }}>
              {editedFolder?.label || editedFolder?.id}
            </Typography>
            <Typography variant="subtitle2" color="text.secondary" gutterBottom>
              文件夹路径
            </Typography>
            <Typography variant="body2" color="text.secondary">
              {editedFolder?.path}
            </Typography>
          </Box>
          <Alert severity="warning" sx={{ mt: 2 }}>
            <Typography variant="body2">
              ⚠️ 删除后，该文件夹将从所有同步设备中移除，且无法恢复。
            </Typography>
          </Alert>
        </DialogContent>
        <DialogActions sx={{ p: 2, pt: 1 }}>
          <Button onClick={handleCancelDelete} color="inherit">
            取消
          </Button>
          <Button
            onClick={handleConfirmDelete}
            variant="contained"
            color="error"
            startIcon={<DeleteIcon />}
          >
            确认删除
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
}

// 文件夹列表组件
function FolderList({ folders, deviceName, deviceId, onRefresh }: {
  folders: Folder[] | null,
  deviceName: string,
  deviceId: string,
  onRefresh?: () => void
}) {
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [selectedFolder, setSelectedFolder] = useState<Folder | null>(null);
  const [isAddMode, setIsAddMode] = useState(false);
  const [snackbarOpen, setSnackbarOpen] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');
  const [snackbarSeverity, setSnackbarSeverity] = useState<'success' | 'error'>('success');

  const handleEditFolder = (folder: Folder, event: React.MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();
    setSelectedFolder(folder);
    setIsAddMode(false);
    setEditDialogOpen(true);
  };

  const handleAddFolder = () => {
    setSelectedFolder(null);
    setIsAddMode(true);
    setEditDialogOpen(true);
  };

  const handleSaveFolder = async (updatedFolder: Folder) => {
    try {
      console.log('保存文件夹:', updatedFolder);

      let apiUrl: string;
      if (deviceId === 'local') {
        apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
      } else {
        // 对于远程设备，需要根据设备地址构建 API URL
        // 这里简化处理，实际应该从设备信息中获取地址
        apiUrl = `http://localhost:8080/api/device/${deviceId}/folders`;
      }

      const method = isAddMode ? 'POST' : 'PUT';
      const url = isAddMode ? apiUrl : `${apiUrl}/${updatedFolder.id}`;

      const response = await fetch(url, {
        method,
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(updatedFolder),
      });

      if (!response.ok) {
        throw new Error(`API 请求失败: ${response.status}`);
      }

      const result = await response.json();
      if (result.code !== 0) {
        throw new Error(result.data || 'API 返回错误');
      }

      console.log('文件夹保存成功:', result);

      // 关闭弹框
      setEditDialogOpen(false);

      // 显示成功消息
      setSnackbarOpen(true);
      setSnackbarMessage('文件夹保存成功！');
      setSnackbarSeverity('success');

      // 重新加载文件夹列表
      onRefresh?.();
    } catch (error) {
      console.error('保存文件夹失败:', error);
      setSnackbarOpen(true);
      setSnackbarMessage('保存文件夹失败: ' + (error instanceof Error ? error.message : String(error)));
      setSnackbarSeverity('error');
    }
  };

  const handleDeleteFolder = async (folderId: string) => {
    try {
      console.log('删除文件夹:', folderId);

      let apiUrl: string;
      if (deviceId === 'local') {
        apiUrl = `http://localhost:8080/api/device/${deviceId}/folders/${folderId}`;
      } else {
        apiUrl = `http://localhost:8080/api/device/${deviceId}/folders/${folderId}`;
      }

      const response = await fetch(apiUrl, {
        method: 'DELETE',
      });

      if (!response.ok) {
        throw new Error(`API 请求失败: ${response.status}`);
      }

      const result = await response.json();
      if (result.code !== 0) {
        throw new Error(result.data || 'API 返回错误');
      }

      console.log('文件夹删除成功:', result);

      // 关闭弹框
      setEditDialogOpen(false);

      // 显示成功消息
      setSnackbarOpen(true);
      setSnackbarMessage('文件夹删除成功！');
      setSnackbarSeverity('success');

      // 立即从本地状态中移除文件夹，避免重复删除
      if (folders) {
        const updatedFolders = folders.filter(folder => folder.id !== folderId);
        // 这里需要更新父组件的状态，但由于这是一个子组件，我们需要通过回调来通知父组件
        // 暂时先重新加载，确保状态同步
        onRefresh?.();
      }
    } catch (error) {
      console.error('删除文件夹失败:', error);
      setSnackbarOpen(true);
      setSnackbarMessage('删除文件夹失败: ' + (error instanceof Error ? error.message : String(error)));
      setSnackbarSeverity('error');

      // 如果是"Folder not found"错误，自动刷新页面
      if (error instanceof Error && error.message.includes('Folder not found')) {
        setTimeout(() => {
          window.location.reload();
        }, 2000);
      }
    }
  };

  if (!folders) {
    return (
      <Alert severity="warning" sx={{ mt: 2 }}>
        正在加载文件夹列表...
      </Alert>
    );
  }

  return (
    <>
      {/* 添加文件夹按钮 */}
      <Box sx={{ mb: 3, display: 'flex', justifyContent: 'flex-end' }}>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={handleAddFolder}
          sx={{ borderRadius: 2 }}
        >
          添加文件夹
        </Button>
      </Box>

      {folders.length === 0 ? (
        <Alert severity="info" sx={{ mt: 2 }}>
          该设备没有共享文件夹
        </Alert>
      ) : (
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
      )}

      {/* 文件夹编辑弹框 */}
      <FolderEditDialog
        open={editDialogOpen}
        folder={selectedFolder}
        onClose={() => setEditDialogOpen(false)}
        onSave={handleSaveFolder}
        onDelete={handleDeleteFolder}
        isAddMode={isAddMode}
      />

      <Snackbar
        open={snackbarOpen}
        autoHideDuration={6000}
        onClose={() => setSnackbarOpen(false)}
      >
        <Alert onClose={() => setSnackbarOpen(false)} severity={snackbarSeverity}>
          {snackbarMessage}
        </Alert>
      </Snackbar>
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

  // 重新加载文件夹列表的函数
  const reloadFolders = async () => {
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
    reloadFolders();
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

      <FolderList folders={folders} deviceName={deviceName} deviceId={deviceId} onRefresh={reloadFolders} />
    </Box>
  );
} 