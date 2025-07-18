import React, { useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  ScrollView,
  FlatList,
  RefreshControl,
  Alert,
} from 'react-native';
import {
  Card,
  Title,
  Paragraph,
  Chip,
  IconButton,
  Searchbar,
  Button,
  Snackbar,
} from 'react-native-paper';
import { CustomFAB } from '../components/CustomFAB';
import { apiService } from '../services/api';
import { Device, Folder } from '../types';

// 扩展 Device 接口以匹配参考实现
interface ExtendedDevice extends Device {
  deviceID: string;
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

export const HomeScreen: React.FC = () => {
  const [devices, setDevices] = useState<ExtendedDevice[]>([]);
  const [folders, setFolders] = useState<Folder[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedDevice, setSelectedDevice] = useState<ExtendedDevice | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [snackbarVisible, setSnackbarVisible] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');

  useEffect(() => {
    loadData();
  }, []);

  // 当选中设备改变时，加载对应的文件夹
  useEffect(() => {
    if (selectedDevice) {
      loadDeviceFolders(selectedDevice.deviceID);
    }
  }, [selectedDevice]);

  const loadData = async () => {
    try {
      setIsLoading(true);
      const devicesData = await loadDevices();
      setDevices(devicesData);
      
      // 默认选中第一个设备（通常是本机）
      if (devicesData.length > 0) {
        setSelectedDevice(devicesData[0]);
      }
    } catch (error) {
      console.error('Failed to load data:', error);
      showSnackbar('加载数据失败');
    } finally {
      setIsLoading(false);
    }
  };

  // 加载设备列表 - 参考 client/frontend/src/pages/App.tsx
  const loadDevices = async (): Promise<ExtendedDevice[]> => {
    try {
      console.log('开始加载设备列表...');
      const devicesData = await apiService.getDevices();
      console.log('设备列表加载成功，设备数量:', devicesData.length);
      return devicesData as ExtendedDevice[];
    } catch (err) {
      console.error('Failed to load devices:', err);
      return [];
    }
  };

  // 加载设备文件夹 - 参考 client/frontend/src/components/FolderList.tsx
  const loadDeviceFolders = async (deviceId: string) => {
    try {
      console.log('加载设备文件夹:', deviceId);
      const foldersData = await apiService.getDeviceFolders(deviceId);
      console.log('文件夹加载成功，文件夹数量:', foldersData.length);
      setFolders(foldersData);
    } catch (error) {
      console.error('Failed to load folders:', error);
      setFolders([]);
      showSnackbar('加载文件夹失败');
    }
  };

  const onRefresh = async () => {
    setRefreshing(true);
    await loadData();
    setRefreshing(false);
  };

  const showSnackbar = (message: string) => {
    setSnackbarMessage(message);
    setSnackbarVisible(true);
  };

  const handleDeviceSelect = (device: ExtendedDevice) => {
    setSelectedDevice(device);
  };

  const handleAddDevice = () => {
    showSnackbar('添加设备功能开发中');
  };

  const handleMessagePress = () => {
    showSnackbar('消息功能开发中');
  };

  const handleProfilePress = () => {
    showSnackbar('个人中心功能开发中');
  };

  const handleFolderPress = (folder: Folder) => {
    showSnackbar(`打开文件夹: ${folder.label}`);
  };

  const isLocalDevice = (device: ExtendedDevice) => {
    return device.deviceID === 'local' || device.isLocal;
  };

  const getConnectionStatus = (device: ExtendedDevice) => {
    return device.connected ? '已连接' : '未连接';
  };

  const getConnectionColor = (device: ExtendedDevice) => {
    return device.connected ? '#4CAF50' : '#FF5722';
  };

  const renderDevice = ({ item }: { item: ExtendedDevice }) => (
    <Card 
      style={[
        styles.deviceCard,
        selectedDevice?.deviceID === item.deviceID && styles.selectedDeviceCard
      ]}
      mode="outlined"
      onPress={() => handleDeviceSelect(item)}
    >
      <Card.Content style={styles.deviceCardContent}>
        <Title style={styles.deviceTitle}>{item.name}</Title>
        <Paragraph style={styles.deviceAddress}>{item.address}</Paragraph>
        <View style={styles.deviceChips}>
          <Chip
            mode="outlined"
            style={[
              styles.statusChip,
              { backgroundColor: getConnectionColor(item) }
            ]}
            textStyle={{ color: 'white' }}
          >
            {getConnectionStatus(item)}
          </Chip>
          {isLocalDevice(item) && (
            <Chip mode="outlined" style={styles.localChip}>
              本机
            </Chip>
          )}
        </View>
      </Card.Content>
    </Card>
  );

  const renderFolder = ({ item }: { item: Folder }) => (
    <Card style={styles.folderCard} mode="outlined" onPress={() => handleFolderPress(item)}>
      <Card.Content>
        <Title style={styles.folderTitle}>{item.label}</Title>
        <Paragraph style={styles.folderPath}>{item.path}</Paragraph>
        <View style={styles.folderChips}>
          <Chip mode="outlined" style={styles.typeChip}>
            {item.type === 'sendonly' ? '仅发送' : 
             item.type === 'receiveonly' ? '仅接收' : '双向同步'}
          </Chip>
          <Chip mode="outlined" style={styles.deviceCountChip}>
            {item.devices.length} 个设备
          </Chip>
        </View>
      </Card.Content>
    </Card>
  );

  return (
    <View style={styles.container}>
      {/* 顶部搜索栏和按钮 */}
      <View style={styles.header}>
        <Searchbar
          placeholder="搜索设备或文件夹..."
          onChangeText={setSearchQuery}
          value={searchQuery}
          style={styles.searchBar}
        />
        <View style={styles.headerButtons}>
          <IconButton
            icon="message-outline"
            size={24}
            onPress={handleMessagePress}
            style={styles.headerButton}
          />
          <IconButton
            icon="account-outline"
            size={24}
            onPress={handleProfilePress}
            style={styles.headerButton}
          />
        </View>
      </View>

      <ScrollView 
        style={styles.scrollView}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
      >
        {/* 设备列表 */}
        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Title style={styles.sectionTitle}>
              设备 ({devices.length})
            </Title>
            <Button
              mode="contained"
              onPress={handleAddDevice}
              style={styles.addButton}
              icon="plus"
            >
              添加设备
            </Button>
          </View>
          
          <FlatList
            data={devices}
            renderItem={renderDevice}
            keyExtractor={(item) => item.deviceID}
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.deviceList}
            contentContainerStyle={styles.deviceListContent}
          />
        </View>

        {/* 文件夹列表 */}
        {selectedDevice && (
          <View style={styles.section}>
            <Title style={styles.sectionTitle}>
              {selectedDevice.name} 的文件夹 ({folders.length})
            </Title>
            
            <FlatList
              data={folders}
              renderItem={renderFolder}
              keyExtractor={(item) => item.id}
              numColumns={2}
              showsVerticalScrollIndicator={false}
              style={styles.folderList}
              contentContainerStyle={styles.folderListContent}
            />
          </View>
        )}
      </ScrollView>

      {/* 添加文件夹 FAB */}
      <CustomFAB
        icon="plus"
        onPress={() => {
          showSnackbar('添加文件夹功能开发中');
        }}
      />

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
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: 'white',
    elevation: 2,
  },
  searchBar: {
    flex: 1,
    marginRight: 8,
    elevation: 0,
  },
  headerButtons: {
    flexDirection: 'row',
  },
  headerButton: {
    marginLeft: 4,
  },
  scrollView: {
    flex: 1,
  },
  section: {
    marginVertical: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 16,
    marginBottom: 12,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  addButton: {
    borderRadius: 20,
  },
  deviceList: {
    maxHeight: 120,
  },
  deviceListContent: {
    paddingHorizontal: 16,
  },
  deviceCard: {
    width: 200,
    marginRight: 12,
    marginBottom: 8,
  },
  selectedDeviceCard: {
    borderColor: '#2196F3',
    borderWidth: 2,
  },
  deviceCardContent: {
    padding: 12,
  },
  deviceTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  deviceAddress: {
    fontSize: 12,
    color: '#666',
    marginBottom: 8,
  },
  deviceChips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
  },
  statusChip: {
    marginRight: 4,
  },
  localChip: {
    backgroundColor: '#2196F3',
  },
  folderList: {
    flex: 1,
  },
  folderListContent: {
    paddingHorizontal: 16,
  },
  folderCard: {
    flex: 1,
    margin: 4,
    marginBottom: 8,
  },
  folderTitle: {
    fontSize: 14,
    fontWeight: 'bold',
    marginBottom: 4,
  },
  folderPath: {
    fontSize: 12,
    color: '#666',
    marginBottom: 8,
    fontFamily: 'monospace',
  },
  folderChips: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 4,
  },
  typeChip: {
    backgroundColor: '#FF9800',
    marginRight: 4,
  },
  deviceCountChip: {
    backgroundColor: '#9C27B0',
  },
});
