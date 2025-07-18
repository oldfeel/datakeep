import React from 'react';
import { View, StyleSheet } from 'react-native';
import { Card, Title, Paragraph, Chip } from 'react-native-paper';

interface PermissionStatusProps {
  permissions: {
    notifications: boolean;
    storage: boolean;
  };
  serviceStatus: 'running' | 'stopped' | 'starting' | 'error';
}

export const PermissionStatus: React.FC<PermissionStatusProps> = ({
  permissions,
  serviceStatus,
}) => {
  const getServiceStatusColor = (status: string) => {
    switch (status) {
      case 'running':
        return '#4CAF50';
      case 'starting':
        return '#FF9800';
      case 'error':
        return '#F44336';
      default:
        return '#9E9E9E';
    }
  };

  const getServiceStatusText = (status: string) => {
    switch (status) {
      case 'running':
        return '运行中';
      case 'starting':
        return '启动中';
      case 'error':
        return '错误';
      default:
        return '已停止';
    }
  };

  return (
    <Card style={styles.card}>
      <Card.Content>
        <Title>系统状态</Title>
        
        <View style={styles.section}>
          <Paragraph style={styles.sectionTitle}>权限状态：</Paragraph>
          <View style={styles.chipContainer}>
            <Chip
              mode="outlined"
              style={[
                styles.permissionChip,
                { backgroundColor: permissions.notifications ? '#E8F5E8' : '#FFEBEE' }
              ]}
              textStyle={{ color: permissions.notifications ? '#2E7D32' : '#C62828' }}
            >
              {permissions.notifications ? '通知权限 ✓' : '通知权限 ✗'}
            </Chip>
            <Chip
              mode="outlined"
              style={[
                styles.permissionChip,
                { backgroundColor: permissions.storage ? '#E8F5E8' : '#FFEBEE' }
              ]}
              textStyle={{ color: permissions.storage ? '#2E7D32' : '#C62828' }}
            >
              {permissions.storage ? '存储权限 ✓' : '存储权限 ✗'}
            </Chip>
          </View>
        </View>

        <View style={styles.section}>
          <Paragraph style={styles.sectionTitle}>服务状态：</Paragraph>
          <View style={styles.chipContainer}>
            <Chip
              mode="outlined"
              style={[
                styles.serviceChip,
                { backgroundColor: getServiceStatusColor(serviceStatus) + '20' }
              ]}
              textStyle={{ color: getServiceStatusColor(serviceStatus) }}
            >
              Syncthing: {getServiceStatusText(serviceStatus)}
            </Chip>
            <Chip
              mode="outlined"
              style={[
                styles.serviceChip,
                { backgroundColor: serviceStatus === 'running' ? '#4CAF5020' : '#9E9E9E20' }
              ]}
              textStyle={{ color: serviceStatus === 'running' ? '#4CAF50' : '#9E9E9E' }}
            >
              HTTPS API: {serviceStatus === 'running' ? '运行中' : '已停止'}
            </Chip>
          </View>
        </View>

        <Paragraph style={styles.info}>
          • 应用启动时会自动请求必要权限
          • 权限授予后会自动启动 Syncthing 服务
          • HTTPS API 服务器运行在端口 8443
        </Paragraph>
      </Card.Content>
    </Card>
  );
};

const styles = StyleSheet.create({
  card: {
    margin: 16,
    elevation: 4,
  },
  section: {
    marginVertical: 8,
  },
  sectionTitle: {
    fontWeight: 'bold',
    marginBottom: 8,
  },
  chipContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  permissionChip: {
    marginBottom: 4,
  },
  serviceChip: {
    marginBottom: 4,
  },
  info: {
    marginTop: 16,
    fontSize: 12,
    color: '#666',
    lineHeight: 18,
  },
}); 