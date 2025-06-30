import React, { useState, useEffect } from 'react';
import {
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
    Alert,
    Box,
    Typography,
    Grid,
} from '@mui/material';
import {
    Folder as FolderIcon,
    Edit as EditIcon,
    Save as SaveIcon,
    Close as CloseIcon,
    Delete as DeleteIcon,
    Settings as SettingsIcon,
    Share as ShareIcon,
    Add as AddIcon,
} from '@mui/icons-material';
import { SelectFolder } from '../../wailsjs/go/main/App';
import { Folder, Device } from '../types';
import { generateFolderId } from '../utils/folderUtils';

interface FolderEditDialogProps {
    open: boolean;
    folder: Folder | null;
    onClose: () => void;
    onSave: (folder: Folder) => void;
    onDelete: (folderId: string) => void;
    isAddMode?: boolean;
}

export default function FolderEditDialog({
    open,
    folder,
    onClose,
    onSave,
    onDelete,
    isAddMode = false
}: FolderEditDialogProps) {
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
    const [allDevices, setAllDevices] = useState<Device[]>([]);
    const [loadingDevices, setLoadingDevices] = useState(false);
    const [localDeviceID, setLocalDeviceID] = useState<string>('');
    const [sharedDevices, setSharedDevices] = useState<Set<string>>(new Set());

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

    const loadLocalDeviceID = async () => {
        try {
            const response = await fetch('http://localhost:8080/api/local-device-id');
            if (response.ok) {
                const result = await response.json();
                if (result.code === 0) {
                    setLocalDeviceID(result.data.deviceID);
                }
            }
        } catch (error) {
            console.error('获取本地设备ID失败:', error);
        }
    };

    const loadAllDevices = async () => {
        try {
            setLoadingDevices(true);
            const response = await fetch('http://localhost:8080/api/devices');
            if (response.ok) {
                const result = await response.json();
                if (result.code === 0) {
                    setAllDevices(result.data);
                }
            }
        } catch (error) {
            console.error('加载设备列表失败:', error);
        } finally {
            setLoadingDevices(false);
        }
    };

    useEffect(() => {
        if (open) {
            loadLocalDeviceID();
            loadAllDevices();
        }
    }, [open]);

    const handleDeviceShareChange = async (deviceId: string, isShared: boolean) => {
        if (!editedFolder) return;

        const newSharedDevices = new Set(sharedDevices);
        if (isShared) {
            newSharedDevices.add(deviceId);
        } else {
            newSharedDevices.delete(deviceId);
        }
        setSharedDevices(newSharedDevices);

        // 更新编辑中的文件夹
        setEditedFolder(prev => prev ? {
            ...prev,
            sharedDevices: Array.from(newSharedDevices)
        } : null);
    };

    if (!editedFolder) return null;

    return (
        <>
            <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
                <DialogTitle>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <FolderIcon />
                        {isAddMode ? '添加文件夹' : '编辑文件夹'}
                    </Box>
                </DialogTitle>
                <DialogContent>
                    <Tabs value={activeTab} onChange={(_, newValue) => setActiveTab(newValue)} sx={{ mb: 2 }}>
                        <Tab label="基本信息" />
                        <Tab label="共享设置" />
                        <Tab label="高级设置" />
                    </Tabs>

                    {activeTab === 0 && (
                        <Grid container spacing={2}>
                            <Grid item xs={12}>
                                <TextField
                                    fullWidth
                                    label="文件夹名称"
                                    value={editedFolder.label}
                                    onChange={(e) => setEditedFolder({ ...editedFolder, label: e.target.value })}
                                    placeholder="输入文件夹名称"
                                />
                            </Grid>
                            <Grid item xs={12}>
                                <Box sx={{ display: 'flex', gap: 1 }}>
                                    <TextField
                                        fullWidth
                                        label="文件夹路径"
                                        value={editedFolder.path}
                                        onChange={(e) => setEditedFolder({ ...editedFolder, path: e.target.value })}
                                        placeholder="选择或输入文件夹路径"
                                    />
                                    <Button
                                        variant="outlined"
                                        onClick={handleSelectFolder}
                                        sx={{ minWidth: 'auto', px: 2 }}
                                    >
                                        选择
                                    </Button>
                                </Box>
                            </Grid>
                            <Grid item xs={12} md={6}>
                                <FormControl fullWidth>
                                    <InputLabel>同步类型</InputLabel>
                                    <Select
                                        value={editedFolder.type || 'sendreceive'}
                                        onChange={(e) => setEditedFolder({ ...editedFolder, type: e.target.value })}
                                        label="同步类型"
                                    >
                                        <MenuItem value="sendreceive">发送和接收</MenuItem>
                                        <MenuItem value="sendonly">仅发送</MenuItem>
                                        <MenuItem value="receiveonly">仅接收</MenuItem>
                                    </Select>
                                </FormControl>
                            </Grid>
                            <Grid item xs={12} md={6}>
                                <FormControlLabel
                                    control={
                                        <Checkbox
                                            checked={editedFolder.paused || false}
                                            onChange={(e) => setEditedFolder({ ...editedFolder, paused: e.target.checked })}
                                        />
                                    }
                                    label="暂停同步"
                                />
                            </Grid>
                        </Grid>
                    )}

                    {activeTab === 1 && (
                        <Box>
                            <Typography variant="h6" sx={{ mb: 2 }}>
                                共享设备
                            </Typography>
                            {loadingDevices ? (
                                <Typography>加载设备中...</Typography>
                            ) : (
                                <Grid container spacing={2}>
                                    {allDevices
                                        .filter(device => device.deviceID !== localDeviceID)
                                        .map(device => (
                                            <Grid item xs={12} key={device.deviceID}>
                                                <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
                                                    <Checkbox
                                                        checked={sharedDevices.has(device.deviceID)}
                                                        onChange={(e) => handleDeviceShareChange(device.deviceID, e.target.checked)}
                                                    />
                                                    <Box sx={{ flex: 1 }}>
                                                        <Typography variant="body2" sx={{ fontWeight: 500 }}>
                                                            {device.name || device.deviceID}
                                                        </Typography>
                                                        <Typography variant="caption" color="text.secondary">
                                                            {device.deviceID}
                                                        </Typography>
                                                    </Box>
                                                    <Chip
                                                        size="small"
                                                        label={device.connected ? '已连接' : '未连接'}
                                                        color={device.connected ? 'success' : 'default'}
                                                    />
                                                </Box>
                                            </Grid>
                                        ))}
                                </Grid>
                            )}
                        </Box>
                    )}

                    {activeTab === 2 && (
                        <Grid container spacing={2}>
                            <Grid item xs={12} md={6}>
                                <TextField
                                    fullWidth
                                    type="number"
                                    label="扫描间隔 (秒)"
                                    value={editedFolder.rescanIntervalS || 3600}
                                    onChange={(e) => setEditedFolder({ ...editedFolder, rescanIntervalS: parseInt(e.target.value) || 3600 })}
                                    helperText="设置为 -1 禁用自动扫描"
                                />
                            </Grid>
                            <Grid item xs={12} md={6}>
                                <FormControlLabel
                                    control={
                                        <Checkbox
                                            checked={editedFolder.fsWatcherEnabled !== false}
                                            onChange={(e) => setEditedFolder({ ...editedFolder, fsWatcherEnabled: e.target.checked })}
                                        />
                                    }
                                    label="启用文件系统监控"
                                />
                            </Grid>
                            <Grid item xs={12} md={6}>
                                <FormControlLabel
                                    control={
                                        <Checkbox
                                            checked={editedFolder.ignorePerms || false}
                                            onChange={(e) => setEditedFolder({ ...editedFolder, ignorePerms: e.target.checked })}
                                        />
                                    }
                                    label="忽略权限"
                                />
                            </Grid>
                            <Grid item xs={12} md={6}>
                                <FormControlLabel
                                    control={
                                        <Checkbox
                                            checked={editedFolder.autoNormalize !== false}
                                            onChange={(e) => setEditedFolder({ ...editedFolder, autoNormalize: e.target.checked })}
                                        />
                                    }
                                    label="自动标准化"
                                />
                            </Grid>
                        </Grid>
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
                    <Button onClick={onClose} startIcon={<CloseIcon />}>
                        取消
                    </Button>
                    <Button
                        onClick={handleSave}
                        variant="contained"
                        startIcon={<SaveIcon />}
                        disabled={!editedFolder.label.trim() || !editedFolder.path.trim()}
                    >
                        保存
                    </Button>
                </DialogActions>
            </Dialog>

            {/* 删除确认对话框 */}
            <Dialog open={deleteConfirmOpen} onClose={handleCancelDelete}>
                <DialogTitle>确认删除</DialogTitle>
                <DialogContent>
                    <Typography>
                        确定要删除文件夹 "{editedFolder?.label}" 吗？此操作不可恢复。
                    </Typography>
                </DialogContent>
                <DialogActions>
                    <Button onClick={handleCancelDelete}>取消</Button>
                    <Button onClick={handleConfirmDelete} color="error" variant="contained">
                        确认删除
                    </Button>
                </DialogActions>
            </Dialog>

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
        </>
    );
} 