import React, { useState, useEffect } from 'react';
import {
  Box,
  Button,
  Card,
  CardContent,
  Typography,
  Grid,
  Alert,
  CircularProgress,
  Divider,
} from '@mui/material';
import { GetHTTPSDevices, GetHTTPSWifiInfo, GetHTTPSDeviceFolders } from '../../wailsjs/go/main/App';

interface TestResult {
  name: string;
  status: 'idle' | 'loading' | 'success' | 'error';
  data?: any;
  error?: string;
}

const TestWailsHTTPS: React.FC = () => {
  const [results, setResults] = useState<TestResult[]>([
    { name: '设备列表', status: 'idle' },
    { name: 'WiFi 信息', status: 'idle' },
    { name: '本地设备文件夹', status: 'idle' },
  ]);

  const updateResult = (index: number, status: TestResult['status'], data?: any, error?: string) => {
    setResults(prev => prev.map((result, i) => 
      i === index ? { ...result, status, data, error } : result
    ));
  };

  const testDevices = async () => {
    updateResult(0, 'loading');
    try {
      const data = await GetHTTPSDevices();
      updateResult(0, 'success', data);
    } catch (error) {
      updateResult(0, 'error', undefined, error instanceof Error ? error.message : String(error));
    }
  };

  const testWifiInfo = async () => {
    updateResult(1, 'loading');
    try {
      const data = await GetHTTPSWifiInfo();
      updateResult(1, 'success', data);
    } catch (error) {
      updateResult(1, 'error', undefined, error instanceof Error ? error.message : String(error));
    }
  };

  const testDeviceFolders = async () => {
    updateResult(2, 'loading');
    try {
      const data = await GetHTTPSDeviceFolders('local');
      updateResult(2, 'success', data);
    } catch (error) {
      updateResult(2, 'error', undefined, error instanceof Error ? error.message : String(error));
    }
  };

  const testAll = async () => {
    await Promise.all([
      testDevices(),
      testWifiInfo(),
      testDeviceFolders(),
    ]);
  };

  const resetAll = () => {
    setResults(prev => prev.map(result => ({ ...result, status: 'idle', data: undefined, error: undefined })));
  };

  const getStatusColor = (status: TestResult['status']) => {
    switch (status) {
      case 'success': return 'success.main';
      case 'error': return 'error.main';
      case 'loading': return 'info.main';
      default: return 'text.secondary';
    }
  };

  const getStatusIcon = (status: TestResult['status']) => {
    switch (status) {
      case 'loading': return <CircularProgress size={16} />;
      case 'success': return '✅';
      case 'error': return '❌';
      default: return '⏸️';
    }
  };

  return (
    <Box sx={{ p: 3, maxWidth: 1200, mx: 'auto' }}>
      <Typography variant="h4" gutterBottom>
        Wails HTTPS API 测试
      </Typography>
      
      <Alert severity="info" sx={{ mb: 3 }}>
        这个页面测试通过 Wails 绑定函数调用 HTTPS API。Wails 前端运行在 WebView 中，
        无法直接访问 HTTPS API，需要通过 Go 后端的绑定函数来代理请求。
      </Alert>

      <Box sx={{ mb: 3 }}>
        <Button 
          variant="contained" 
          onClick={testAll} 
          sx={{ mr: 2 }}
        >
          测试所有 API
        </Button>
        <Button 
          variant="outlined" 
          onClick={resetAll}
        >
          重置所有测试
        </Button>
      </Box>

      <Grid container spacing={3}>
        {results.map((result, index) => (
          <Grid item xs={12} md={6} lg={4} key={index}>
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', mb: 2 }}>
                  <Typography variant="h6" sx={{ flexGrow: 1 }}>
                    {result.name}
                  </Typography>
                  <Box sx={{ color: getStatusColor(result.status), display: 'flex', alignItems: 'center' }}>
                    {getStatusIcon(result.status)}
                  </Box>
                </Box>

                <Box sx={{ mb: 2 }}>
                  <Button
                    variant="outlined"
                    size="small"
                    onClick={() => {
                      switch (index) {
                        case 0: testDevices(); break;
                        case 1: testWifiInfo(); break;
                        case 2: testDeviceFolders(); break;
                      }
                    }}
                    disabled={result.status === 'loading'}
                  >
                    测试
                  </Button>
                </Box>

                {result.status === 'success' && result.data && (
                  <Box>
                    <Typography variant="body2" color="text.secondary" gutterBottom>
                      响应数据:
                    </Typography>
                    <Box 
                      sx={{ 
                        bgcolor: 'grey.100', 
                        p: 1, 
                        borderRadius: 1,
                        maxHeight: 200,
                        overflow: 'auto',
                        fontFamily: 'monospace',
                        fontSize: '0.75rem'
                      }}
                    >
                      <pre>{JSON.stringify(result.data, null, 2)}</pre>
                    </Box>
                  </Box>
                )}

                {result.status === 'error' && result.error && (
                  <Alert severity="error" sx={{ mt: 1 }}>
                    {result.error}
                  </Alert>
                )}
              </CardContent>
            </Card>
          </Grid>
        ))}
      </Grid>

      <Divider sx={{ my: 3 }} />
      
      <Typography variant="h6" gutterBottom>
        工作原理说明
      </Typography>
      
      <Box sx={{ bgcolor: 'grey.50', p: 2, borderRadius: 1 }}>
        <Typography variant="body2" paragraph>
          <strong>1. Wails 架构:</strong>
        </Typography>
        <Typography variant="body2" component="div" sx={{ ml: 2, mb: 2 }}>
          • 前端 (React) 运行在 WebView 中<br/>
          • Go 后端通过绑定函数暴露给前端<br/>
          • 前端调用绑定函数，Go 后端代理请求到 HTTPS API
        </Typography>
        
        <Typography variant="body2" paragraph>
          <strong>2. 调用流程:</strong>
        </Typography>
        <Typography variant="body2" component="div" sx={{ ml: 2, mb: 2 }}>
          React → Wails 绑定函数 → Go HTTP 客户端 → HTTPS API (localhost:8443)
        </Typography>
        
        <Typography variant="body2" paragraph>
          <strong>3. 优势:</strong>
        </Typography>
        <Typography variant="body2" component="div" sx={{ ml: 2 }}>
          • 绕过 WebView 的 HTTPS 限制<br/>
          • Go 可以处理自签名证书<br/>
          • 更好的错误处理和类型安全
        </Typography>
      </Box>
    </Box>
  );
};

export default TestWailsHTTPS;
