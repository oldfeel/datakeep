import React, { useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  ScrollView,
  FlatList,
  RefreshControl,
  Alert,
  Text,
  TouchableOpacity,
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
import { useNavigation } from '@react-navigation/native';
import { Modal, Portal, Dialog, Button as PaperButton, TextInput, RadioButton, Checkbox } from 'react-native-paper';

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

// 新设备卡片组件
interface DeviceCardProps {
  icon: string;
  title: string;
  subtitle: string;
  onPress: () => void;
  selected?: boolean;
}
const DeviceCard: React.FC<DeviceCardProps> = ({ icon, title, subtitle, onPress, selected }) => (
  <Card style={[styles.deviceCardNew, selected && styles.deviceCardSelected]} onPress={onPress}>
    <View style={styles.deviceCardContentNew}>
      <IconButton icon={icon} size={28} style={styles.deviceIcon} />
      <View>
        <Text style={styles.deviceTitleNew}>{title}</Text>
        <Text style={styles.deviceSubtitleNew}>{subtitle}</Text>
      </View>
    </View>
  </Card>
);

// 新增添加按钮卡片
interface AddDeviceCardProps {
  onPress: () => void;
}
const AddDeviceCard: React.FC<AddDeviceCardProps> = ({ onPress }) => (
  <Card style={styles.deviceCardNew} onPress={onPress}>
    <View style={[styles.deviceCardContentNew, { justifyContent: 'center', alignItems: 'center' }]}> 
      <IconButton icon="plus" size={32} />
    </View>
  </Card>
);

// 设备类型与图标映射
const getDeviceIcon = (type?: string) => {
  switch (type) {
    case 'phone':
      return 'cellphone';
    case 'pc':
      return 'laptop';
    case 'tv':
      return 'television';
    case 'cloud':
      return 'cloud-outline';
    default:
      return 'devices';
  }
};

// 测试文件夹数据
const testFolders = [
  {
    id: '1',
    name: 'DCIM',
    date: '2025/07/03 19:04',
    count: 8,
    type: '',
    icon: 'folder-image',
  },
  {
    id: '2',
    name: '外包',
    date: '2025/07/03 19:04',
    count: 12,
    type: '',
    icon: 'folder',
  },
  {
    id: '3',
    name: 'Documents',
    date: '2025/06/23 16:21',
    count: 7,
    type: '',
    icon: 'folder',
  },
];

// 文件夹项组件
interface FolderItemProps {
  icon: string;
  name: string;
  date: string;
  count: number;
  type: string;
  onPress: () => void;
}
const FolderItem: React.FC<FolderItemProps> = ({ icon, name, date, count, type, onPress }) => (
  <TouchableOpacity style={styles.folderItem} onPress={onPress}>
    <IconButton icon={icon} size={36} style={styles.folderIcon} />
    <View style={styles.folderInfo}>
      <Text style={styles.folderName}>{name}</Text>
      <View style={styles.folderMetaRow}>
        <Text style={styles.folderMeta}>{date}</Text>
        <Text style={styles.folderMeta}> | {count}项</Text>
        {type ? <Text style={styles.folderMeta}> | {type}</Text> : null}
      </View>
    </View>
    <IconButton icon="chevron-right" size={24} style={styles.folderArrow} />
  </TouchableOpacity>
);

export const HomeScreen: React.FC = () => {
  const navigation: any = useNavigation();
  const [devices, setDevices] = useState<ExtendedDevice[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedDevice, setSelectedDevice] = useState<ExtendedDevice | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [snackbarVisible, setSnackbarVisible] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');

  useEffect(() => {
    loadData();
  }, []);

  // 默认选中本机
  useEffect(() => {
    if (devices.length > 0 && !selectedDevice) {
      const local = devices.find(d => (d as any).isLocal === true);
      setSelectedDevice(local || devices[0]);
    }
  }, [devices]);

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
    (navigation as any).navigate('AddDevice');
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
          <FlatList
            data={[...devices, { isAddButton: true }]}
            renderItem={({ item }) => {
              if ('isAddButton' in item) {
                return <AddDeviceCard onPress={handleAddDevice} />;
              } else {
                // 图标和副标题可根据实际数据调整
                const icon = getDeviceIcon((item as any).device_type);
                const subtitle = item.status === 'connected' ? '在线' : '离线';
                return (
                  <DeviceCard
                    icon={icon}
                    title={item.name}
                    subtitle={subtitle}
                    onPress={() => handleDeviceSelect(item)}
                    selected={selectedDevice?.id === item.id}
                  />
                );
              }
            }}
            keyExtractor={(item, index) => 'isAddButton' in item ? 'add-device-btn' : item.deviceID}
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.deviceList}
            contentContainerStyle={styles.deviceListContent}
          />
        </View>

        {/* 文件夹列表 */}
        <View style={styles.section}>
          <FlatList
            data={testFolders}
            renderItem={({ item }) => (
              <FolderItem
                icon={item.icon}
                name={item.name}
                date={item.date}
                count={item.count}
                type={item.type}
                onPress={() => {}}
              />
            )}
            keyExtractor={item => item.id}
          />
        </View>
      </ScrollView>

      {/* 添加文件夹 FAB */}
      <CustomFAB
        icon="plus"
        onPress={() => navigation.navigate('AddFolder')}
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
    paddingTop: 8,
    paddingBottom: 8,
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
    borderWidth: 2,
    borderColor: '#2196F3',
    backgroundColor: '#e3f2fd',
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
  deviceCardNew: {
    borderRadius: 18,
    backgroundColor: '#f5f8ff',
    marginRight: 12,
    minWidth: 100,
    height: 56,
    paddingLeft: 8,
    paddingRight: 8,
    justifyContent: 'center',
    shadowColor: '#000',
    shadowOpacity: 0.06,
    shadowRadius: 8,
    elevation: 2,
    borderWidth: 0,
  },
  deviceCardContentNew: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 12,
    height: '100%',
  },
  deviceIcon: {
    marginRight: 8,
    backgroundColor: 'transparent',
  },
  deviceTitleNew: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#222',
  },
  deviceSubtitleNew: {
    fontSize: 12,
    color: '#888',
    marginTop: 2,
  },
  deviceCardSelected: {
    borderWidth: 2,
    borderColor: '#2196F3',
    backgroundColor: '#e3f2fd',
  },
  folderItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    paddingHorizontal: 8,
    backgroundColor: '#fff',
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  folderIcon: {
    marginRight: 8,
    backgroundColor: 'transparent',
  },
  folderInfo: {
    flex: 1,
    justifyContent: 'center',
  },
  folderName: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#222',
  },
  folderMetaRow: {
    flexDirection: 'row',
    marginTop: 2,
  },
  folderMeta: {
    fontSize: 12,
    color: '#888',
  },
  folderArrow: {
    marginLeft: 4,
    backgroundColor: 'transparent',
  },
});
