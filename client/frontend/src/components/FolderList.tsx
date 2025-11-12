import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
    Box,
    Button,
    Card,
    CardContent,
    Typography,
    IconButton,
    Chip,
    Alert,
    Snackbar,
    Grid,
    Tooltip,
} from '@mui/material';
import {
    Add as AddIcon,
    Edit as EditIcon,
    Folder as FolderIcon,
    Share as ShareIcon,
    Pause as PauseIcon,
    PlayArrow as PlayIcon,
} from '@mui/icons-material';
import FolderEditDialog from './FolderEditDialog';
import { Folder, Device } from '../types';

interface FolderListProps {
    folders: Folder[] | null;
    deviceName: string;
    deviceId: string;
    onRefresh?: () => void;
}

export default function FolderList({
    folders,
    deviceName,
    deviceId,
    onRefresh
}: FolderListProps) {
    const navigate = useNavigate();
    const [editDialogOpen, setEditDialogOpen] = useState(false);
    const [selectedFolder, setSelectedFolder] = useState<Folder | null>(null);
    const [isAddMode, setIsAddMode] = useState(false);
    const [snackbarOpen, setSnackbarOpen] = useState(false);
    const [snackbarMessage, setSnackbarMessage] = useState('');
    const [snackbarSeverity, setSnackbarSeverity] = useState<'success' | 'error'>('success');
    const [allDevices, setAllDevices] = useState<Device[]>([]);

    // 获取所有设备列表
    const loadAllDevices = async () => {
        try {
            const response = await fetch('http://localhost:8080/api/devices');
            if (!response.ok) {
                // 如果是 404 或 500+ 错误，可能是后端服务未启动，静默失败
                if (response.status === 404 || response.status >= 500) {
                    setAllDevices([]);
                    return;
                }
                throw new Error(`API 请求失败: ${response.status}`);
            }
            const result = await response.json();
            if (result.code !== 0) {
                throw new Error(result.data || 'API 返回错误');
            }
            setAllDevices(result.data || []);
        } catch (error: any) {
            // 网络错误或 CORS 错误，完全静默处理（在浏览器环境中这是正常的）
            const errorMessage = error?.message || String(error);
            if (error instanceof TypeError || 
                errorMessage.includes('Failed to fetch') || 
                errorMessage.includes('Load failed') ||
                errorMessage.includes('CORS') ||
                errorMessage.includes('access control') ||
                errorMessage.includes('NetworkError')) {
                // 完全静默，不显示任何警告或错误
            }
            // 如果获取失败，不影响其他功能，设置空数组
            setAllDevices([]);
        }
    };

    // 组件加载时获取设备列表
    useEffect(() => {
        loadAllDevices();
    }, []);

    // 根据设备ID获取设备名称
    const getDeviceName = (deviceId: string) => {
        const device = allDevices.find(d => d.deviceID === deviceId);
        return device ? device.name || deviceId : deviceId;
    };

    // 获取文件夹的共享设备名称列表
    const getSharedDeviceNames = (folder: Folder) => {
        if (folder.sharedDevices && folder.sharedDevices.length > 0) {
            return folder.sharedDevices.map(deviceId => getDeviceName(deviceId));
        }
        return [];
    };

    // 处理文件夹卡片点击
    const handleFolderClick = (folder: Folder) => {
        console.log('点击文件夹:', folder);
        // 跳转到文件夹详情页面
        navigate(`/folder/${deviceId}/${folder.id}`);
    };

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
            <Box sx={{ mb: 3, display: 'flex' }}>
                <Button
                    variant="contained"
                    startIcon={<AddIcon />}
                    onClick={handleAddFolder}
                    sx={{ borderRadius: 2 }}
                >
                    添加文件夹
                </Button>
            </Box>

            {/* 文件夹列表 */}
            <Grid container spacing={2}>
                {folders.length === 0 ? (
                    <Grid item xs={12}>
                        <Alert severity="info" sx={{ mt: 2 }}>
                            该设备还没有共享文件夹
                        </Alert>
                    </Grid>
                ) : (
                    folders.map((folder) => (
                        <Grid item xs={12} md={6} lg={4} key={folder.id}>
                            <Card
                                sx={{
                                    height: '100%',
                                    display: 'flex',
                                    flexDirection: 'column',
                                    cursor: 'pointer',
                                    '&:hover': {
                                        boxShadow: 3,
                                        transform: 'translateY(-2px)',
                                        transition: 'all 0.2s ease-in-out'
                                    }
                                }}
                                onClick={() => handleFolderClick(folder)}
                            >
                                <CardContent sx={{ flexGrow: 1, display: 'flex', flexDirection: 'column' }}>
                                    {/* 文件夹标题和操作按钮 */}
                                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', mb: 2 }}>
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flex: 1 }}>
                                            <FolderIcon color="primary" />
                                            <Typography variant="h6" component="h3" sx={{ fontWeight: 600, wordBreak: 'break-word' }}>
                                                {folder.label || '未命名文件夹'}
                                            </Typography>
                                        </Box>
                                        <Tooltip title="编辑文件夹">
                                            <IconButton
                                                size="small"
                                                onClick={(e) => handleEditFolder(folder, e)}
                                                sx={{ color: 'primary.main' }}
                                            >
                                                <EditIcon fontSize="small" />
                                            </IconButton>
                                        </Tooltip>
                                    </Box>

                                    {/* 文件夹路径 */}
                                    <Typography
                                        variant="body2"
                                        color="text.secondary"
                                        sx={{
                                            mb: 2,
                                            fontFamily: 'monospace',
                                            fontSize: '0.75rem',
                                            wordBreak: 'break-all',
                                            flex: 1
                                        }}
                                    >
                                        {folder.path}
                                    </Typography>

                                    {/* 文件夹状态和类型 */}
                                    <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, mb: 2 }}>
                                        {/* 同步类型 */}
                                        <Chip
                                            label={folder.type === 'sendreceive' ? '双向同步' :
                                                folder.type === 'sendonly' ? '仅发送' :
                                                    folder.type === 'receiveonly' ? '仅接收' : '未知'}
                                            size="small"
                                            color={folder.type === 'sendreceive' ? 'primary' : 'default'}
                                            variant="outlined"
                                        />

                                        {/* 暂停状态 */}
                                        {folder.paused && (
                                            <Chip
                                                icon={<PauseIcon />}
                                                label="已暂停"
                                                size="small"
                                                color="warning"
                                                variant="outlined"
                                            />
                                        )}

                                        {/* 共享状态 */}
                                        {folder.sharedDevices && folder.sharedDevices.length > 0 && (
                                            <Chip
                                                icon={<ShareIcon />}
                                                label={`共享给 ${folder.sharedDevices.length} 个设备`}
                                                size="small"
                                                color="success"
                                                variant="outlined"
                                            />
                                        )}
                                    </Box>

                                    {/* 共享设备列表 */}
                                    {folder.sharedDevices && folder.sharedDevices.length > 0 && (
                                        <Box sx={{ mt: 'auto' }}>
                                            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 1 }}>
                                                共享设备:
                                            </Typography>
                                            <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                                                {getSharedDeviceNames(folder).map((deviceName, index) => (
                                                    <Chip
                                                        key={index}
                                                        label={deviceName}
                                                        size="small"
                                                        variant="outlined"
                                                        sx={{ fontSize: '0.7rem' }}
                                                    />
                                                ))}
                                            </Box>
                                        </Box>
                                    )}
                                </CardContent>
                            </Card>
                        </Grid>
                    ))
                )}
            </Grid>

            {/* 文件夹编辑对话框 */}
            <FolderEditDialog
                open={editDialogOpen}
                folder={selectedFolder}
                onClose={() => setEditDialogOpen(false)}
                onSave={handleSaveFolder}
                onDelete={handleDeleteFolder}
                isAddMode={isAddMode}
            />

            {/* 消息提示 */}
            <Snackbar
                open={snackbarOpen}
                autoHideDuration={3000}
                onClose={() => setSnackbarOpen(false)}
            >
                <Alert
                    onClose={() => setSnackbarOpen(false)}
                    severity={snackbarSeverity}
                    sx={{ width: '100%' }}
                >
                    {snackbarMessage}
                </Alert>
            </Snackbar>
        </>
    );
} 