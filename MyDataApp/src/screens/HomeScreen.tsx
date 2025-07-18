import React, { useState, useEffect } from 'react';
import {
  View,
  StyleSheet,
  FlatList,
  RefreshControl,
  Alert,
} from 'react-native';
import {
  Card,
  Title,
  Paragraph,
  Chip,
  Snackbar,
} from 'react-native-paper';
import { SearchBar } from '../components/SearchBar';
import { SimpleServiceManager } from '../components/SimpleServiceManager';
import { CustomFAB } from '../components/CustomFAB';
import { PermissionStatus } from '../components/PermissionStatus';
import { apiService } from '../services/api';
import { Device, Folder } from '../types';

export const HomeScreen: React.FC = () => {
  const [devices, setDevices] = useState<Device[]>([]);
  const [folders, setFolders] = useState<Folder[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [snackbarVisible, setSnackbarVisible] = useState(false);
  const [snackbarMessage, setSnackbarMessage] = useState('');
  const [permissions, setPermissions] = useState({
    notifications: false,
    storage: false,
  });
  const [serviceStatus, setServiceStatus] = useState<'running' | 'stopped' | 'starting' | 'error'>('stopped');

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      setIsLoading(true);
      const [devicesData, foldersData] = await Promise.all([
        apiService.getDevices(),
        apiService.getFolders(),
      ]);
      setDevices(devicesData);
      setFolders(foldersData);
    } catch (error) {
      console.error('Failed to load data:', error);
      showSnackbar('加载数据失败');
    } finally {
      setIsLoading(false);
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

  const handleDeleteFolder = (folderId: string) => {
    Alert.alert(
      '确认删除',
      '确定要删除这个文件夹吗？',
      [
        { text: '取消', style: 'cancel' },
        {
          text: '删除',
          style: 'destructive',
          onPress: async () => {
            try {
              await apiService.deleteFolder(folderId);
              showSnackbar('文件夹删除成功');
              loadData(); // 重新加载数据
            } catch (error) {
              console.error('Failed to delete folder:', error);
              showSnackbar('删除失败');
            }
          },
        },
      ]
    );
  };

  const filteredDevices = devices.filter(device =>
    device.name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const filteredFolders = folders.filter(folder =>
    folder.label.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const renderDevice = ({ item }: { item: Device }) => (
    <Card style={styles.card} mode="outlined">
      <Card.Content>
        <Title>{item.name}</Title>
        <Paragraph>{item.address}</Paragraph>
        <View style={styles.chipContainer}>
          <Chip
            mode="outlined"
            style={[
              styles.statusChip,
              {
                backgroundColor: item.status === 'connected' ? '#4CAF50' : '#FF5722',
              },
            ]}
            textStyle={{ color: 'white' }}
          >
            {item.status === 'connected' ? '已连接' : '未连接'}
          </Chip>
          {item.isLocal && (
            <Chip mode="outlined" style={styles.localChip}>
              本机
            </Chip>
          )}
        </View>
      </Card.Content>
    </Card>
  );

  const renderFolder = ({ item }: { item: Folder }) => (
    <Card style={styles.card} mode="outlined">
      <Card.Content>
        <Title>{item.label}</Title>
        <Paragraph>{item.path}</Paragraph>
        <View style={styles.chipContainer}>
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
      <PermissionStatus 
        permissions={permissions}
        serviceStatus={serviceStatus}
      />
      
      <SimpleServiceManager 
        onServiceStarted={() => {
          console.log('Syncthing 服务已启动');
          setServiceStatus('running');
        }}
        onServiceStopped={() => {
          console.log('Syncthing 服务已停止');
          setServiceStatus('stopped');
        }}
      />

      <SearchBar
        value={searchQuery}
        onChangeText={setSearchQuery}
        placeholder="搜索设备或文件夹..."
        height={40}
        fontSize={14}
        onClear={() => setSearchQuery('')}
      />

      <FlatList
        data={filteredDevices}
        renderItem={renderDevice}
        keyExtractor={(item) => item.id}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
        ListHeaderComponent={
          <Title style={styles.sectionTitle}>设备 ({filteredDevices.length})</Title>
        }
        style={styles.list}
      />

      <FlatList
        data={filteredFolders}
        renderItem={renderFolder}
        keyExtractor={(item) => item.id}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} />
        }
        ListHeaderComponent={
          <Title style={styles.sectionTitle}>文件夹 ({filteredFolders.length})</Title>
        }
        style={styles.list}
      />

      <CustomFAB
        icon="plus"
        onPress={() => {
          // TODO: 实现添加文件夹功能
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
  list: {
    flex: 1,
  },
  card: {
    marginHorizontal: 16,
    marginVertical: 4,
  },
  chipContainer: {
    flexDirection: 'row',
    marginTop: 8,
    gap: 8,
  },
  statusChip: {
    marginRight: 8,
  },
  localChip: {
    backgroundColor: '#2196F3',
  },
  typeChip: {
    backgroundColor: '#FF9800',
  },
  deviceCountChip: {
    backgroundColor: '#9C27B0',
  },
  sectionTitle: {
    marginHorizontal: 16,
    marginTop: 16,
    marginBottom: 8,
  },
  fab: {
    position: 'absolute',
    margin: 16,
    right: 0,
    bottom: 0,
  },
}); 