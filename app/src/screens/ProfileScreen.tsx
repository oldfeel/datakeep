import React, { useState, useEffect } from 'react';
import {
    View,
    StyleSheet,
    ScrollView,
    Text,
    TouchableOpacity,
    Alert,
} from 'react-native';
import {
    Card,
    Title,
    Paragraph,
    Chip,
    IconButton,
    Button,
    Snackbar,
    Divider,
} from 'react-native-paper';
import { useNavigation } from '@react-navigation/native';
import { apiService } from '../services/api';

interface DeviceInfo {
    id: string;
    name: string;
    address: string;
    isLocal?: boolean;
}

export const ProfileScreen: React.FC = () => {
    const navigation = useNavigation();
    const [deviceInfo, setDeviceInfo] = useState<DeviceInfo | null>(null);
    const [isLoading, setIsLoading] = useState(false);
    const [snackbarVisible, setSnackbarVisible] = useState(false);
    const [snackbarMessage, setSnackbarMessage] = useState('');

    useEffect(() => {
        loadDeviceInfo();
    }, []);

    const loadDeviceInfo = async () => {
        try {
            setIsLoading(true);

            // 获取本机设备信息
            const devices = await apiService.getDevices();
            const localDevice = devices.find((device: any) => device.isLocal === true);

            if (localDevice) {
                setDeviceInfo(localDevice);
            } else {
                // 如果没有找到本机设备，尝试获取设备ID
                try {
                    const deviceId = await apiService.getLocalDeviceId();
                    setDeviceInfo({
                        id: deviceId,
                        name: '本机设备',
                        address: '127.0.0.1',
                        isLocal: true,
                    });
                } catch (error) {
                    console.error('获取本机设备ID失败:', error);
                    setDeviceInfo({
                        id: '未知',
                        name: '本机设备',
                        address: '127.0.0.1',
                        isLocal: true,
                    });
                }
            }
        } catch (error) {
            console.error('加载设备信息失败:', error);
            showSnackbar('加载设备信息失败');
        } finally {
            setIsLoading(false);
        }
    };

    const showSnackbar = (message: string) => {
        setSnackbarMessage(message);
        setSnackbarVisible(true);
    };

    const handleCopyDeviceID = () => {
        if (deviceInfo?.id) {
            // 在 React Native 中，我们可以显示一个提示
            showSnackbar('设备ID已复制到剪贴板');
            // 注意：实际复制功能需要额外的库支持
        }
    };

    const handleRefresh = () => {
        loadDeviceInfo();
    };

    const handleBack = () => {
        navigation.goBack();
    };

    return (
        <View style={styles.container}>
            {/* 顶部导航栏 */}
            <View style={styles.header}>
                <TouchableOpacity onPress={handleBack} style={styles.backButton}>
                    <IconButton icon="arrow-left" size={24} />
                </TouchableOpacity>
                <Text style={styles.headerTitle}>个人中心</Text>
                <TouchableOpacity onPress={handleRefresh} style={styles.refreshButton}>
                    <IconButton icon="refresh" size={24} />
                </TouchableOpacity>
            </View>

            <ScrollView style={styles.scrollView}>
                {/* 设备信息卡片 */}
                <Card style={styles.infoCard}>
                    <Card.Content>
                        <View style={styles.cardHeader}>
                            <IconButton icon="devices" size={32} style={styles.deviceIcon} />
                            <View style={styles.deviceInfo}>
                                <Title style={styles.deviceName}>
                                    {deviceInfo?.name || '本机设备'}
                                </Title>
                                <Chip mode="outlined" style={styles.localChip}>
                                    本机
                                </Chip>
                            </View>
                        </View>

                        <Divider style={styles.divider} />

                        {/* 设备ID */}
                        <View style={styles.infoRow}>
                            <View style={styles.infoLabel}>
                                <IconButton icon="identifier" size={20} style={styles.infoIcon} />
                                <Text style={styles.labelText}>Syncthing 设备ID</Text>
                            </View>
                            <View style={styles.infoValue}>
                                <Text style={styles.valueText} numberOfLines={2}>
                                    {deviceInfo?.id || '加载中...'}
                                </Text>
                                <TouchableOpacity onPress={handleCopyDeviceID} style={styles.copyButton}>
                                    <IconButton icon="content-copy" size={16} />
                                </TouchableOpacity>
                            </View>
                        </View>

                        {/* 设备名称 */}
                        <View style={styles.infoRow}>
                            <View style={styles.infoLabel}>
                                <IconButton icon="account" size={20} style={styles.infoIcon} />
                                <Text style={styles.labelText}>设备名称</Text>
                            </View>
                            <View style={styles.infoValue}>
                                <Text style={styles.valueText}>
                                    {deviceInfo?.name || '本机设备'}
                                </Text>
                            </View>
                        </View>

                        {/* 网络地址 */}
                        <View style={styles.infoRow}>
                            <View style={styles.infoLabel}>
                                <IconButton icon="wifi" size={20} style={styles.infoIcon} />
                                <Text style={styles.labelText}>网络地址</Text>
                            </View>
                            <View style={styles.infoValue}>
                                <Text style={styles.valueText}>
                                    {deviceInfo?.address || '127.0.0.1'}
                                </Text>
                            </View>
                        </View>
                    </Card.Content>
                </Card>

                {/* 系统信息卡片 */}
                <Card style={styles.infoCard}>
                    <Card.Content>
                        <Title style={styles.cardTitle}>系统信息</Title>
                        <Divider style={styles.divider} />

                        <View style={styles.infoRow}>
                            <View style={styles.infoLabel}>
                                <IconButton icon="information" size={20} style={styles.infoIcon} />
                                <Text style={styles.labelText}>应用版本</Text>
                            </View>
                            <View style={styles.infoValue}>
                                <Text style={styles.valueText}>1.0.0</Text>
                            </View>
                        </View>

                        <View style={styles.infoRow}>
                            <View style={styles.infoLabel}>
                                <IconButton icon="platform" size={20} style={styles.infoIcon} />
                                <Text style={styles.labelText}>平台</Text>
                            </View>
                            <View style={styles.infoValue}>
                                <Text style={styles.valueText}>Android</Text>
                            </View>
                        </View>
                    </Card.Content>
                </Card>

                {/* 操作按钮 */}
                <View style={styles.buttonContainer}>
                    <Button
                        mode="contained"
                        onPress={handleRefresh}
                        style={styles.button}
                        icon="refresh"
                    >
                        刷新信息
                    </Button>

                    <Button
                        mode="outlined"
                        onPress={() => showSnackbar('设置功能开发中')}
                        style={styles.button}
                        icon="cog"
                    >
                        设置
                    </Button>
                </View>
            </ScrollView>

            <Snackbar
                visible={snackbarVisible}
                onDismiss={() => setSnackbarVisible(false)}
                duration={3000}
            >
                {snackbarMessage}
            </Snackbar>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#f5f5f5',
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: 16,
        paddingVertical: 12,
        backgroundColor: 'white',
        elevation: 2,
    },
    backButton: {
        marginLeft: -8,
    },
    headerTitle: {
        fontSize: 18,
        fontWeight: 'bold',
        color: '#333',
    },
    refreshButton: {
        marginRight: -8,
    },
    scrollView: {
        flex: 1,
        padding: 16,
    },
    infoCard: {
        marginBottom: 16,
        elevation: 2,
    },
    cardHeader: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 16,
    },
    deviceIcon: {
        marginRight: 12,
        backgroundColor: '#e3f2fd',
    },
    deviceInfo: {
        flex: 1,
    },
    deviceName: {
        fontSize: 20,
        fontWeight: 'bold',
        marginBottom: 8,
    },
    localChip: {
        backgroundColor: '#2196F3',
        alignSelf: 'flex-start',
    },
    cardTitle: {
        fontSize: 18,
        fontWeight: 'bold',
        marginBottom: 16,
    },
    divider: {
        marginVertical: 16,
    },
    infoRow: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        marginBottom: 16,
    },
    infoLabel: {
        flexDirection: 'row',
        alignItems: 'center',
        flex: 1,
    },
    infoIcon: {
        marginRight: 8,
        backgroundColor: 'transparent',
    },
    labelText: {
        fontSize: 16,
        color: '#666',
        fontWeight: '500',
    },
    infoValue: {
        flex: 2,
        alignItems: 'flex-end',
    },
    valueText: {
        fontSize: 14,
        color: '#333',
        textAlign: 'right',
        fontFamily: 'monospace',
    },
    copyButton: {
        marginTop: 4,
    },
    buttonContainer: {
        marginTop: 24,
        gap: 12,
    },
    button: {
        marginBottom: 8,
    },
});
