import React, { useState, useEffect } from 'react';
import {
  Box,
  Typography,
  Button,
  Alert,
  CircularProgress,
  Paper,
  List,
  ListItem,
  ListItemText,
  Divider,
} from '@mui/material';
import { apiFetch, apiFetchJson } from '../config/api';

interface TestResult {
  name: string;
  status: 'pending' | 'success' | 'error';
  message: string;
  data?: any;
}

export default function TestHTTPS() {
  const [results, setResults] = useState<TestResult[]>([]);
  const [isRunning, setIsRunning] = useState(false);

  const runTests = async () => {
    setIsRunning(true);
    setResults([]);

    const tests = [
      {
        name: '健康检查',
        url: '/health',
        description: '测试基本连接'
      },
      {
        name: '设备列表',
        url: '/api/devices',
        description: '测试设备 API'
      },
      {
        name: 'WiFi 信息',
        url: '/api/wifi-info',
        description: '测试 WiFi API'
      },
      {
        name: '本地设备 ID',
        url: '/api/deviceid',
        description: '测试设备 ID API'
      }
    ];

    for (const test of tests) {
      // 添加测试到结果列表
      setResults(prev => [...prev, {
        name: test.name,
        status: 'pending',
        message: '测试中...'
      }]);

      try {
        const data = await apiFetchJson(test.url);
        
        setResults(prev => prev.map(r => 
          r.name === test.name 
            ? { ...r, status: 'success', message: '成功', data }
            : r
        ));
      } catch (error) {
        setResults(prev => prev.map(r => 
          r.name === test.name 
            ? { ...r, status: 'error', message: `失败: ${error instanceof Error ? error.message : String(error)}` }
            : r
        ));
      }
    }

    setIsRunning(false);
  };

  const getStatusColor = (status: TestResult['status']) => {
    switch (status) {
      case 'success': return 'success';
      case 'error': return 'error';
      case 'pending': return 'info';
      default: return 'info';
    }
  };

  const getStatusIcon = (status: TestResult['status']) => {
    switch (status) {
      case 'success': return '✅';
      case 'error': return '❌';
      case 'pending': return '⏳';
      default: return '⏳';
    }
  };

  return (
    <Box sx={{ p: 3, maxWidth: 800, mx: 'auto' }}>
      <Typography variant="h4" gutterBottom>
        HTTPS API 连接测试
      </Typography>
      
      <Alert severity="info" sx={{ mb: 3 }}>
        <Typography variant="body2">
          此页面用于测试前端与 HTTPS API 服务器的连接。
          <br />
          如果使用自签名证书，浏览器可能会显示安全警告，请点击"高级"并选择"继续访问"。
        </Typography>
      </Alert>

      <Box sx={{ mb: 3 }}>
        <Button 
          variant="contained" 
          onClick={runTests} 
          disabled={isRunning}
          sx={{ mr: 2 }}
        >
          {isRunning ? <CircularProgress size={20} sx={{ mr: 1 }} /> : null}
          开始测试
        </Button>
        
        <Button 
          variant="outlined" 
          onClick={() => setResults([])}
          disabled={isRunning}
        >
          清空结果
        </Button>
      </Box>

      {results.length > 0 && (
        <Paper sx={{ p: 2 }}>
          <Typography variant="h6" gutterBottom>
            测试结果
          </Typography>
          
          <List>
            {results.map((result, index) => (
              <React.Fragment key={result.name}>
                <ListItem>
                  <ListItemText
                    primary={
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <span>{getStatusIcon(result.status)}</span>
                        <Typography variant="subtitle1">
                          {result.name}
                        </Typography>
                        <Alert 
                          severity={getStatusColor(result.status)} 
                          sx={{ ml: 'auto', py: 0, minHeight: 'auto' }}
                        >
                          {result.message}
                        </Alert>
                      </Box>
                    }
                    secondary={
                      result.data && (
                        <Box sx={{ mt: 1 }}>
                          <Typography variant="caption" color="text.secondary">
                            响应数据:
                          </Typography>
                          <pre style={{ 
                            fontSize: '12px', 
                            backgroundColor: '#f5f5f5', 
                            padding: '8px', 
                            borderRadius: '4px',
                            overflow: 'auto',
                            maxHeight: '200px'
                          }}>
                            {JSON.stringify(result.data, null, 2)}
                          </pre>
                        </Box>
                      )
                    }
                  />
                </ListItem>
                {index < results.length - 1 && <Divider />}
              </React.Fragment>
            ))}
          </List>
        </Paper>
      )}
    </Box>
  );
}
