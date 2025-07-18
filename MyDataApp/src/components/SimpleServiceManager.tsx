import React, { useState } from 'react';
import { View, StyleSheet, Alert } from 'react-native';
import { Button, Card, Title, Paragraph } from 'react-native-paper';

interface SimpleServiceManagerProps {
  onServiceStarted?: () => void;
  onServiceStopped?: () => void;
}

export const SimpleServiceManager: React.FC<SimpleServiceManagerProps> = ({
  onServiceStarted,
  onServiceStopped
}) => {
  const [loading, setLoading] = useState(false);

  const handleStartService = async () => {
    setLoading(true);
    try {
      // 服务启动由 Android 原生代码处理
      // 这里只是显示信息
      Alert.alert('信息', 'Syncthing 服务将通过 Android 前台服务启动，HTTPS API 服务器运行在端口 8443');
      onServiceStarted?.();
    } catch (error) {
      Alert.alert('错误', `启动服务失败: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  const handleStopService = async () => {
    setLoading(true);
    try {
      // 服务停止由 Android 原生代码处理
      // 这里只是显示信息
      Alert.alert('信息', 'Syncthing 服务将通过 Android 前台服务停止');
      onServiceStopped?.();
    } catch (error) {
      Alert.alert('错误', `停止服务失败: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card style={styles.card}>
      <Card.Content>
        <Title>Syncthing HTTPS API</Title>
        <Paragraph style={styles.description}>
          Syncthing 服务通过 Android 前台服务运行，HTTPS API 服务器在端口 8443 上提供 REST API。
          您可以通过 HTTPS API 与 Syncthing 进行通信。
        </Paragraph>
        
        <View style={styles.apiInfo}>
          <Paragraph style={styles.apiTitle}>可用的 API 端点：</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• GET /api/devices</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• GET /api/device/{'{deviceId}'}/folders</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• GET /api/folder/{'{folderId}'}</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• GET /api/local-device-id</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• GET /api/wifi-info</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• POST /api/folder/{'{folderId}'}/share</Paragraph>
          <Paragraph style={styles.apiEndpoint}>• GET /api/syncthing/events</Paragraph>
        </View>
      </Card.Content>
      
      <Card.Actions style={styles.actions}>
        <Button
          mode="contained"
          onPress={handleStartService}
          disabled={loading}
          style={styles.button}
        >
          查看服务信息
        </Button>
        
        <Button
          mode="outlined"
          onPress={handleStopService}
          disabled={loading}
          style={styles.button}
        >
          查看 API 状态
        </Button>
      </Card.Actions>
    </Card>
  );
};

const styles = StyleSheet.create({
  card: {
    margin: 16,
    elevation: 4,
  },
  description: {
    marginVertical: 8,
    lineHeight: 20,
  },
  apiInfo: {
    marginTop: 16,
    padding: 12,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
  },
  apiTitle: {
    fontWeight: 'bold',
    marginBottom: 8,
  },
  apiEndpoint: {
    fontSize: 12,
    fontFamily: 'monospace',
    marginBottom: 4,
  },
  actions: {
    justifyContent: 'space-around',
    paddingHorizontal: 16,
  },
  button: {
    flex: 1,
    marginHorizontal: 4,
  },
}); 