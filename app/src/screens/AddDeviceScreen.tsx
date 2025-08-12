import React, { useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  ScrollView,
  Alert,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import {
  Card,
  Title,
  Paragraph,
  TextInput,
  Button,
  Chip,
  Snackbar,
  HelperText,
  Divider,
} from 'react-native-paper';
import { useNavigation } from '@react-navigation/native';
import { apiService } from '../services/api';

interface DeviceValidation {
  isValid: boolean;
  isUnique: boolean;
  error: string;
}

interface NewDevice {
  deviceID: string;
  name: string;
}

export const AddDeviceScreen: React.FC = () => {
  const navigation = useNavigation();
  const [newDevice, setNewDevice] = useState<NewDevice>({
    deviceID: '',
    name: '',
  });
  const [deviceValidation, setDeviceValidation] = useState<DeviceValidation>({
    isValid: false,
    isUnique: true,
    error: '',
  });
  const [discoveryUnknown, setDiscoveryUnknown] = useState<string[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [snackbarVisible, setSnackbarVisible] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');

  useEffect(() => {
    loadNearbyDevices();
  }, []);

  // 加载附近发现的设备
  const loadNearbyDevices = async () => {
    try {
      console.log('开始加载附近设备...');
      const nearbyDevices = await apiService.getNearbyDevices();
      console.log('附近设备加载成功，设备数量:', nearbyDevices.length);
      
      if (nearbyDevices.length > 0) {
        setDiscoveryUnknown(nearbyDevices);
      } else {
        console.log('没有发现附近设备');
        setDiscoveryUnknown([]);
      }
    } catch (error) {
      console.log('无法获取附近设备:', error);
      setDiscoveryUnknown([]);
    }
  };

  // 验证设备 ID
  const validateDeviceID = async (deviceID: string) => {
    const cleanID = deviceID.replace(/[\s-]/g, '');

    // Syncthing 设备 ID 格式：8组，每组7个字符，总共56个字符
    if (cleanID.length !== 56) {
      setDeviceValidation({
        isValid: false,
        isUnique: true,
        error: '设备 ID 长度必须为 56 位（8组，每组7个字符）',
      });
      return;
    }

    if (!/^[A-Z0-9]+$/.test(cleanID)) {
      setDeviceValidation({
        isValid: false,
        isUnique: true,
        error: '设备 ID 只能包含大写字母和数字',
      });
      return;
    }

    // 验证设备 ID 有效性
    try {
      // 这里可以调用 API 验证设备 ID
      // 暂时使用基本验证
      setDeviceValidation({
        isValid: true,
        isUnique: true,
        error: '',
      });
    } catch (error) {
      setDeviceValidation({
        isValid: true,
        isUnique: true,
        error: '',
      });
    }
  };

  // 处理设备 ID 变化
  const handleDeviceIDChange = (text: string) => {
    setNewDevice(prev => ({ ...prev, deviceID: text }));
    validateDeviceID(text);
  };

  // 选择附近设备
  const handleSelectNearbyDevice = (deviceID: string) => {
    setNewDevice(prev => ({ ...prev, deviceID }));
    validateDeviceID(deviceID);
  };

  // 保存设备
  const handleSaveDevice = async () => {
    if (!deviceValidation.isValid) {
      return;
    }

    setIsLoading(true);

    try {
      // 构建设备配置
      const deviceConfig = {
        deviceID: newDevice.deviceID.replace(/[\s-]/g, ''),
        name: newDevice.name,
        addresses: ['dynamic'],
        compression: 'metadata',
        introducer: false,
        autoAcceptFolders: false,
        untrusted: false,
        numConnections: 0,
        maxRecvKbps: 0,
        maxSendKbps: 0,
      };

      console.log('🌐 开始添加设备...');
      console.log('📋 设备配置:', deviceConfig);

      // 调用 API 添加设备
      const addedDevice = await apiService.addDevice(deviceConfig);
      console.log('✅ 设备添加成功:', addedDevice);

      // 显示成功消息
      setSnackbarMessage(`设备 ${deviceConfig.name || deviceConfig.deviceID} 添加成功`);
      setSnackbarVisible(true);

      // 延迟返回上一页
      setTimeout(() => {
        navigation.goBack();
      }, 1500);
    } catch (error) {
      console.error('❌ 添加设备失败:', error);
      setSnackbarMessage(`添加设备失败: ${error instanceof Error ? error.message : '未知错误'}`);
      setSnackbarVisible(true);
    } finally {
      setIsLoading(false);
    }
  };

  const showSnackbar = (message: string) => {
    setSnackbarMessage(message);
    setSnackbarVisible(true);
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.content}>
        <Card style={styles.card}>
          <Card.Content>
            <Title style={styles.title}>添加设备</Title>
            <Paragraph style={styles.subtitle}>
              添加新的 Syncthing 设备到您的网络
            </Paragraph>

            <Divider style={styles.divider} />

            {/* 设备 ID 部分 */}
            <Title style={styles.sectionTitle}>设备 ID</Title>
            <TextInput
              label="设备 ID"
              value={newDevice.deviceID}
              onChangeText={handleDeviceIDChange}
              error={!deviceValidation.isValid && newDevice.deviceID !== ''}
              style={styles.textInput}
              placeholder="例如: ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNOPQRSTUVWXYZ"
              mode="outlined"
            />
            <HelperText
              type={deviceValidation.error ? 'error' : 'info'}
              visible={true}
            >
              {deviceValidation.error ||
                '在此处输入的设备 ID 可以在另一台设备的"操作 > 显示 ID"对话框中找到。空格和破折号是可选的（忽略）。'}
            </HelperText>

            {/* 附近设备选择 */}
            {discoveryUnknown.length > 0 && (
              <View style={styles.nearbySection}>
                <Paragraph style={styles.nearbyTitle}>
                  您还可以选择以下附近的设备之一：
                </Paragraph>
                <View style={styles.nearbyDevices}>
                  {discoveryUnknown.map((deviceID) => (
                    <Chip
                      key={deviceID}
                      mode="outlined"
                      onPress={() => handleSelectNearbyDevice(deviceID)}
                      style={styles.nearbyChip}
                      textStyle={styles.nearbyChipText}
                    >
                      {deviceID}
                    </Chip>
                  ))}
                </View>
              </View>
            )}

            <Divider style={styles.divider} />

            {/* 设备名称部分 */}
            <Title style={styles.sectionTitle}>设备名称</Title>
            <TextInput
              label="设备名称"
              value={newDevice.name}
              onChangeText={(text) => setNewDevice(prev => ({ ...prev, name: text }))}
              style={styles.textInput}
              placeholder="例如: 我的手机"
              mode="outlined"
            />
            <HelperText type="info" visible={true}>
              在集群状态中显示该名称，而不是设备 ID。如果留空，将更新为设备通告的名称。
            </HelperText>

            {/* 提示信息 */}
            <Card style={styles.infoCard}>
              <Card.Content>
                <Paragraph style={styles.infoText}>
                  若您在本机添加新设备，记住您也必须在这个新设备上添加本机。
                </Paragraph>
              </Card.Content>
            </Card>
          </Card.Content>
        </Card>
      </ScrollView>

      {/* 底部按钮 */}
      <View style={styles.bottomButtons}>
        <Button
          mode="outlined"
          onPress={() => navigation.goBack()}
          style={styles.cancelButton}
        >
          取消
        </Button>
        <Button
          mode="contained"
          onPress={handleSaveDevice}
          disabled={!deviceValidation.isValid || isLoading}
          loading={isLoading}
          style={styles.saveButton}
        >
          添加设备
        </Button>
      </View>

      <Snackbar
        visible={snackbarVisible}
        onDismiss={() => setSnackbarVisible(false)}
        duration={3000}
      >
        {snackbarMessage}
      </Snackbar>
    </KeyboardAvoidingView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollView: {
    flex: 1,
  },
  content: {
    padding: 16,
  },
  card: {
    marginBottom: 16,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  subtitle: {
    color: '#666',
    marginBottom: 16,
  },
  divider: {
    marginVertical: 16,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  textInput: {
    marginBottom: 8,
  },
  nearbySection: {
    marginTop: 16,
    marginBottom: 16,
  },
  nearbyTitle: {
    color: '#666',
    marginBottom: 8,
  },
  nearbyDevices: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  nearbyChip: {
    marginBottom: 8,
  },
  nearbyChipText: {
    fontFamily: 'monospace',
    fontSize: 12,
  },
  infoCard: {
    marginTop: 16,
    backgroundColor: '#e3f2fd',
  },
  infoText: {
    color: '#1976d2',
  },
  bottomButtons: {
    flexDirection: 'row',
    padding: 16,
    backgroundColor: 'white',
    borderTopWidth: 1,
    borderTopColor: '#e0e0e0',
    gap: 12,
  },
  cancelButton: {
    flex: 1,
  },
  saveButton: {
    flex: 1,
  },
}); 