import React, { useState, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';

import { GetHTTPSDeviceFolders, GetHTTPSDevices, GetDevices } from '../../wailsjs/go/main/App';
import {
  Box,
  Typography,
  Alert,
  Breadcrumbs,
  CircularProgress,
  Snackbar,
} from '@mui/material';
import {
  Home as HomeIcon,
} from '@mui/icons-material';
import DeviceInfoCard from '../components/DeviceInfoCard';
import FolderList from '../components/FolderList';
import { Folder, Device } from '../types';
import { GetFolders } from '../../wailsjs/go/main/App';

// 设备详情页面组件
export default function DeviceDetail() {
  const { deviceId } = useParams<{ deviceId: string }>();
  const navigate = useNavigate();
  const [device, setDevice] = useState<Device | null>(null);
  const [folders, setFolders] = useState<Folder[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [snackbar, setSnackbar] = useState<{
    open: boolean;
    message: string;
    severity: 'success' | 'error' | 'warning' | 'info';
  }>({
    open: false,
    message: '',
    severity: 'success'
  });

  // 重新加载文件夹列表的函数
  const reloadFolders = async () => {
    if (!deviceId) return;

    try {
      console.log('重新加载文件夹列表，设备ID:', deviceId);

      let foldersData: Folder[] = [];

      if (deviceId === 'local') {
        // 本地设备使用 Wails 函数
        try {
          const result = await GetFolders();
          console.log('本地文件夹列表:', result);
          foldersData = result || [];
        } catch (wailsError) {
          console.error('Wails 获取文件夹失败:', wailsError);
          // 如果 Wails 失败，尝试使用 HTTPS API
          try {
            const result = await GetHTTPSDeviceFolders('local');
            if (result && typeof result === 'object' && 'code' in result && result.code === 0) {
              foldersData = result.data || [];
            }
          } catch (httpsError) {
            console.error('HTTPS API 获取文件夹失败:', httpsError);
          }
        }
      } else {
        // 远程设备使用 HTTPS API
        try {
          const result = await GetHTTPSDeviceFolders(deviceId);
          if (result && typeof result === 'object' && 'code' in result && result.code === 0) {
            foldersData = result.data || [];
          } else {
            console.warn('HTTPS API 返回错误:', result);
            // 如果设备离线，设置空列表但不显示错误
            if (result && typeof result === 'object' && 'data' in result && 
                typeof result.data === 'string' && result.data.includes('offline')) {
              foldersData = [];
              setError(null);
              return;
            }
          }
        } catch (apiError) {
          console.error('HTTPS API 请求异常:', apiError);
          // 网络错误时也设置空列表
          foldersData = [];
          setError(null);
          return;
        }
      }

      console.log('设置文件夹列表:', foldersData);
      setFolders(foldersData);
      setError(null);
    } catch (err) {
      console.error('加载文件夹列表失败:', err);
      setError('加载文件夹列表失败: ' + (err instanceof Error ? err.message : String(err)));
      setFolders(null);
    }
  };

  // 加载设备信息和文件夹列表
  useEffect(() => {
    const loadData = async () => {
      if (!deviceId) {
        setError('设备ID不能为空');
        setLoading(false);
        return;
      }

      setLoading(true);
      setError(null);

      try {
        // 加载设备信息
        const loadDeviceInfo = async () => {
          try {
            if (deviceId === 'local') {
              setDevice({
                deviceID: 'local',
                name: '本机',
                addresses: null,
                connected: true,
                isLocalNetwork: true
              });
            } else {
              // 获取远程设备信息 - 使用 Golang 函数
              try {
                const devices = await GetDevices();
                const foundDevice = devices.find((d: any) => d.deviceID === deviceId);

                console.log('Found device:', foundDevice);
                if (foundDevice) {
                  setDevice({
                    deviceID: foundDevice.deviceID,
                    name: foundDevice.name || foundDevice.deviceID,
                    addresses: foundDevice.addresses || null,
                    connected: true, // Golang Device 类型没有 connected 属性，默认为 true
                    isLocalNetwork: false // Golang Device 类型没有 isLocalNetwork 属性，默认为 false
                  });
                  console.log('Device addresses:', foundDevice.addresses);
                } else {
                  setDevice({
                    deviceID: deviceId,
                    name: deviceId,
                    addresses: null,
                    connected: false,
                    isLocalNetwork: false
                  });
                }
              } catch (golangError) {
                console.error('Golang 获取设备失败:', golangError);
                // 如果 Golang 失败，尝试使用 HTTPS API 作为备选
                const result = await GetHTTPSDevices();
                if (result && typeof result === 'object' && 'code' in result && result.code !== 0) {
                  throw new Error(result.data || 'API 返回错误');
                }

                const devices = result?.data || [];
                const foundDevice = devices.find((d: Device) => d.deviceID === deviceId);

                console.log('Found device (HTTPS):', foundDevice);
                if (foundDevice) {
                  setDevice({
                    deviceID: foundDevice.deviceID,
                    name: foundDevice.name || foundDevice.deviceID,
                    addresses: foundDevice.addresses,
                    connected: foundDevice.connected,
                    isLocalNetwork: foundDevice.isLocalNetwork
                  });
                  console.log('Device addresses (HTTPS):', foundDevice.addresses);
                } else {
                  setDevice({
                    deviceID: deviceId,
                    name: deviceId,
                    addresses: null,
                    connected: false,
                    isLocalNetwork: false
                  });
                }
              }
            }
          } catch (err) {
            console.error('Failed to load device info:', err);
            setDevice({
              deviceID: deviceId,
              name: deviceId,
              addresses: null,
              connected: false,
              isLocalNetwork: false
            });
          }
        };

        await loadDeviceInfo();
        await reloadFolders();
      } catch (err) {
        console.error('Failed to load data:', err);
        setError('加载数据失败: ' + (err instanceof Error ? err.message : String(err)));
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, [deviceId]);

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
      </Box>
    );
  }

  if (!deviceId) {
    return (
      <Box>
        <Alert severity="error">
          设备ID不能为空
        </Alert>
      </Box>
    );
  }

  return (
    <Box>
      {/* 面包屑导航 */}
      <Breadcrumbs sx={{ mb: 3 }}>
        <Link to="/" style={{ textDecoration: 'none', color: 'inherit' }}>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <HomeIcon fontSize="small" />
            <Typography color="text.primary">首页</Typography>
          </Box>
        </Link>
        <Typography color="text.primary">{device?.name || device?.deviceID}</Typography>
      </Breadcrumbs>

      {/* 设备信息卡片 */}
      <DeviceInfoCard
        device={device}
        onDeviceNameChange={async (newName) => {
          setDevice(prev => prev ? { ...prev, name: newName } : null);
          console.log('设备名称已更新为:', newName);
        }}
        onRemoveDevice={async () => {
          if (!deviceId || deviceId === 'local') {
            setSnackbar({
              open: true,
              message: '无法移除本机设备',
              severity: 'warning'
            });
            return;
          }

          try {
            console.log('开始移除设备:', deviceId);

            // 使用 HTTPS API 删除设备
            const deleteUrl = `https://localhost:8443/api/device/${deviceId}`;
            const response = await fetch(deleteUrl, {
              method: 'DELETE',
            });

            if (response.ok) {
              const result = await response.json();
              if (result.code === 0) {
                setSnackbar({
                  open: true,
                  message: '设备移除成功',
                  severity: 'success'
                });
                // 移除成功后跳转到首页
                navigate('/');
              } else {
                throw new Error(result.data || '移除设备失败');
              }
            } else {
              throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
          } catch (error) {
            console.error('移除设备失败:', error);
            setSnackbar({
              open: true,
              message: '移除设备失败: ' + (error instanceof Error ? error.message : String(error)),
              severity: 'error'
            });
          }
        }}
      />

      {/* 文件夹列表 */}
      {device && (
        <FolderList
          folders={folders}
          deviceName={device.name || device.deviceID}
          deviceId={deviceId || ''}
          onRefresh={reloadFolders}
        />
      )}

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