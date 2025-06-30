import React, { useState, useEffect } from 'react';
import {
    Box,
    Typography,
    Grid,
    Card,
    CardContent,
    IconButton,
    Tooltip,
    Dialog,
    DialogTitle,
    DialogContent,
    DialogActions,
    Button,
    TextField,
    Skeleton,
    Snackbar,
    Alert,
} from '@mui/material';
import {
    Edit as EditIcon,
    Save as SaveIcon,
    Cancel as CancelIcon,
    Delete as DeleteIcon,
    ContentCopy as CopyIcon,
    ExpandLess as ExpandLessIcon,
    ExpandMore as ExpandMoreIcon,
} from '@mui/icons-material';
import { Device } from '../types';

interface DeviceInfoCardProps {
    device: Device | null;
    onDeviceNameChange: (newName: string) => void;
    onRemoveDevice: () => void;
}

export default function DeviceInfoCard({
    device,
    onDeviceNameChange,
    onRemoveDevice
}: DeviceInfoCardProps) {
    const [isEditing, setIsEditing] = useState(false);
    const [editedName, setEditedName] = useState(device?.name || '');
    const [isExpanded, setIsExpanded] = useState(true);
    const [removeDialogOpen, setRemoveDialogOpen] = useState(false);
    const [snackbar, setSnackbar] = useState<{
        open: boolean;
        message: string;
        severity: 'success' | 'error' | 'warning' | 'info';
    }>({
        open: false,
        message: '',
        severity: 'success'
    });

    useEffect(() => {
        setEditedName(device?.name || '');
    }, [device?.name]);

    const handleSave = async () => {
        if (device && editedName.trim() !== device.name) {
            try {
                onDeviceNameChange(editedName.trim());
                setIsEditing(false);
                setSnackbar({
                    open: true,
                    message: '设备名称更新成功',
                    severity: 'success'
                });
            } catch (error) {
                console.error('更新设备名称失败:', error);
                setSnackbar({
                    open: true,
                    message: '更新设备名称失败',
                    severity: 'error'
                });
            }
        } else {
            setIsEditing(false);
        }
    };

    const handleCancel = () => {
        setEditedName(device?.name || '');
        setIsEditing(false);
    };

    const copyDeviceId = () => {
        if (device?.deviceID) {
            navigator.clipboard.writeText(device.deviceID);
            setSnackbar({
                open: true,
                message: '设备ID已复制到剪贴板',
                severity: 'success'
            });
        }
    };

    if (!device) {
        return (
            <Card sx={{ mb: 2, maxWidth: 800 }}>
                <CardContent>
                    <Skeleton variant="text" width="60%" height={32} />
                    <Skeleton variant="text" width="40%" height={24} />
                </CardContent>
            </Card>
        );
    }

    return (
        <>
            <Card sx={{ mb: 2, maxWidth: 800 }}>
                <CardContent>
                    <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                            <Typography variant="h6" component="h2" sx={{ fontWeight: 600 }}>
                                设备信息
                            </Typography>
                            <IconButton
                                size="small"
                                onClick={() => setIsExpanded(!isExpanded)}
                                sx={{ color: 'primary.main' }}
                            >
                                {isExpanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
                            </IconButton>
                        </Box>
                        <Button
                            size="small"
                            variant="outlined"
                            color="error"
                            startIcon={<DeleteIcon />}
                            onClick={() => setRemoveDialogOpen(true)}
                        >
                            移除设备
                        </Button>
                    </Box>

                    {isExpanded && (
                        <Grid container spacing={2}>
                            {/* 设备ID */}
                            <Grid item xs={12}>
                                <Box sx={{ mb: 2, display: 'flex', alignItems: 'center', gap: 2 }}>
                                    <Typography variant="body2" color="text.secondary" sx={{ minWidth: '80px', fontWeight: 500 }}>
                                        设备ID:
                                    </Typography>
                                    <Box sx={{
                                        display: 'flex',
                                        alignItems: 'center',
                                        gap: 1,
                                        p: 1,
                                        bgcolor: 'grey.50',
                                        borderRadius: 1,
                                        border: '1px solid',
                                        borderColor: 'grey.300',
                                        flex: 1,
                                        height: '40px'
                                    }}>
                                        <Typography
                                            variant="body2"
                                            sx={{
                                                fontFamily: 'monospace',
                                                flex: 1,
                                                wordBreak: 'break-all'
                                            }}
                                        >
                                            {device.deviceID}
                                        </Typography>
                                        <Tooltip title="复制设备ID">
                                            <IconButton size="small" onClick={copyDeviceId}>
                                                <CopyIcon fontSize="small" />
                                            </IconButton>
                                        </Tooltip>
                                    </Box>
                                </Box>
                            </Grid>

                            {/* 设备名称 */}
                            <Grid item xs={12}>
                                <Box sx={{ mb: 2, display: 'flex', alignItems: 'center', gap: 2 }}>
                                    <Typography variant="body2" color="text.secondary" sx={{ minWidth: '80px', fontWeight: 500 }}>
                                        设备名称:
                                    </Typography>
                                    {isEditing ? (
                                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flex: 1 }}>
                                            <TextField
                                                size="small"
                                                value={editedName}
                                                onChange={(e) => setEditedName(e.target.value)}
                                                placeholder="输入设备名称"
                                                sx={{ flex: 1 }}
                                                autoFocus
                                            />
                                            <IconButton
                                                size="small"
                                                onClick={handleSave}
                                                color="primary"
                                                disabled={!editedName.trim()}
                                            >
                                                <SaveIcon />
                                            </IconButton>
                                            <IconButton size="small" onClick={handleCancel}>
                                                <CancelIcon />
                                            </IconButton>
                                        </Box>
                                    ) : (
                                        <Box sx={{
                                            display: 'flex',
                                            alignItems: 'center',
                                            gap: 1,
                                            p: 1,
                                            bgcolor: 'grey.50',
                                            borderRadius: 1,
                                            border: '1px solid',
                                            borderColor: 'grey.300',
                                            height: '40px',
                                            flex: 1
                                        }}>
                                            <Typography variant="body2" sx={{ flex: 1 }}>
                                                {device.name || '未设置名称'}
                                            </Typography>
                                            <IconButton
                                                size="small"
                                                onClick={() => setIsEditing(true)}
                                                sx={{ color: 'primary.main' }}
                                            >
                                                <EditIcon fontSize="small" />
                                            </IconButton>
                                        </Box>
                                    )}
                                </Box>
                            </Grid>
                        </Grid>
                    )}
                </CardContent>
            </Card>

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

            {/* 移除设备确认对话框 */}
            <Dialog open={removeDialogOpen} onClose={() => setRemoveDialogOpen(false)}>
                <DialogTitle>确认移除设备</DialogTitle>
                <DialogContent>
                    <Typography>确定要移除该设备吗？此操作不可恢复。</Typography>
                </DialogContent>
                <DialogActions>
                    <Button onClick={() => setRemoveDialogOpen(false)}>取消</Button>
                    <Button onClick={() => { setRemoveDialogOpen(false); onRemoveDevice(); }} color="error" variant="contained">确认移除</Button>
                </DialogActions>
            </Dialog>
        </>
    );
} 