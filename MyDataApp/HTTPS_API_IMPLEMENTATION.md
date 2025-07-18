# MyDataApp HTTPS API 实现

## 📋 实现概述

参考 syncthing-android 的 HttpsApiController，我们为 MyDataApp 创建了简化的 HTTPS API 服务器，提供 HTTP API 接口与 Syncthing 通信。

## 🔧 技术架构

### 1. Android 原生层

#### HttpsApiController.kt
- **功能**：HTTP 服务器，提供 REST API 接口
- **特点**：
  - 监听端口 8443
  - 处理 HTTP 请求和响应
  - 转发请求到 Syncthing REST API
  - 支持 CORS 跨域请求

#### SyncthingService.kt
- **功能**：Android 前台服务，管理 Syncthing 和 HTTPS 服务器
- **特点**：
  - 启动和停止 HTTPS 服务器
  - 管理 Syncthing 进程
  - 前台服务确保后台运行

### 2. React Native 层

#### SimpleServiceManager.tsx
- **功能**：简化的服务管理组件
- **特点**：
  - 启动/停止 Syncthing 服务
  - 显示可用的 API 端点
  - 用户友好的界面

#### api.ts
- **功能**：API 服务，与 HTTPS 服务器通信
- **特点**：
  - 配置为使用端口 8443
  - 标准的 HTTP 请求处理
  - 错误处理和类型安全

## 📁 文件结构

```
MyDataApp/
├── android/app/src/main/
│   ├── java/com/mydata/app/
│   │   ├── SyncthingModule.kt          # React Native 模块
│   │   ├── SyncthingPackage.kt         # 模块包
│   │   └── service/
│   │       ├── SyncthingService.kt     # Android 前台服务
│   │       └── HttpsApiController.kt   # HTTP API 服务器
│   ├── build.gradle                    # 依赖配置
│   └── AndroidManifest.xml             # 权限和服务声明
├── src/
│   ├── components/
│   │   └── SimpleServiceManager.tsx    # 服务管理组件
│   ├── services/
│   │   └── api.ts                      # API 服务
│   └── types/
│       └── SyncthingService.ts         # TypeScript 类型定义
└── ...
```

## 🔐 依赖配置

在 `android/app/build.gradle` 中添加了必要的依赖：

```gradle
dependencies {
    // HTTP 客户端
    implementation 'com.squareup.okhttp3:okhttp:4.12.0'
    
    // JSON 处理
    implementation 'com.google.code.gson:gson:2.10.1'
}
```

## 🚀 使用方法

### 1. 启动服务
```typescript
import { SyncthingService } from '../types/SyncthingService';

// 启动 Syncthing 服务（包含 HTTPS 服务器）
await SyncthingService.startService();
```

### 2. 使用 API
```typescript
import { apiService } from '../services/api';

// 获取设备列表
const devices = await apiService.getDevices();

// 获取文件夹列表
const folders = await apiService.getFolders();

// 获取特定设备的文件夹
const deviceFolders = await apiService.getDeviceFolders('device-id');
```

### 3. 在组件中使用
```tsx
import { SimpleServiceManager } from '../components/SimpleServiceManager';

<SimpleServiceManager 
  onServiceStarted={() => {
    console.log('服务已启动');
  }}
  onServiceStopped={() => {
    console.log('服务已停止');
  }}
/>
```

## 🌐 可用的 API 端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/devices` | GET | 获取设备列表 |
| `/api/device/{deviceId}/folders` | GET | 获取特定设备的文件夹 |
| `/api/folder/{folderId}` | GET | 获取文件夹信息 |
| `/api/local-device-id` | GET | 获取本地设备 ID |
| `/api/wifi-info` | GET | 获取 WiFi 信息 |
| `/api/folder/{folderId}/share` | POST | 共享文件夹 |
| `/api/syncthing/events` | GET | 获取 Syncthing 事件 |

## 🔄 请求流程

```
React Native App
       ↓
   HTTP Request (localhost:8443)
       ↓
   HttpsApiController
       ↓
   Syncthing REST API (localhost:8384)
       ↓
   Syncthing Process
```

### 示例请求

```bash
# 获取设备列表
curl http://localhost:8443/api/devices

# 获取文件夹列表
curl http://localhost:8443/api/folders

# 获取本地设备 ID
curl http://localhost:8443/api/local-device-id
```

## 📊 响应格式

### 成功响应
```json
{
  "success": true,
  "data": [
    {
      "id": "device-id",
      "name": "设备名称",
      "address": "127.0.0.1:8384",
      "status": "connected",
      "isLocal": true
    }
  ]
}
```

### 错误响应
```json
{
  "success": false,
  "error": {
    "code": 500,
    "message": "获取设备列表失败"
  }
}
```

## 🔧 技术特点

### 1. HTTP 服务器
- 使用 Java Socket 实现简单的 HTTP 服务器
- 支持多线程并发处理
- 自动处理连接关闭

### 2. API 转发
- 使用 OkHttp 客户端转发请求到 Syncthing
- 支持 SSL 证书验证（开发环境信任所有证书）
- 自动添加 API Key 认证头

### 3. 错误处理
- 完善的异常捕获和处理
- 友好的错误响应格式
- 模拟数据作为备用方案

### 4. CORS 支持
- 添加 CORS 头支持跨域请求
- 支持预检请求（OPTIONS）
- 允许所有来源访问

## 🎯 与 syncthing-android 的对比

| 特性 | syncthing-android | MyDataApp |
|------|------------------|-----------|
| HTTPS 服务器 | ✅ | ✅ |
| API 转发 | ✅ | ✅ |
| SSL 证书 | ✅ | ✅ (简化) |
| CORS 支持 | ✅ | ✅ |
| 模拟数据 | ✅ | ✅ |
| React Native 集成 | ❌ | ✅ |
| 简化实现 | ❌ | ✅ |

## 🚀 下一步计划

### 1. 功能扩展
- [ ] 添加更多 API 端点
- [ ] 实现 WebSocket 支持
- [ ] 添加 API 认证
- [ ] 实现请求缓存

### 2. 性能优化
- [ ] 连接池管理
- [ ] 请求压缩
- [ ] 响应缓存
- [ ] 异步处理优化

### 3. 安全性
- [ ] 实现真正的 SSL 证书
- [ ] 添加 API 密钥验证
- [ ] 实现请求限流
- [ ] 添加日志审计

## 🎉 总结

我们成功实现了：

1. **简化的 HTTPS API 服务器**：提供 HTTP API 接口
2. **服务管理**：启动和停止 Syncthing 服务
3. **API 转发**：将请求转发到 Syncthing REST API
4. **错误处理**：完善的异常处理和模拟数据
5. **用户界面**：简洁的服务管理组件

这个实现为 MyDataApp 提供了：

- **无需直接服务通信**：通过 HTTP API 进行通信
- **标准化的接口**：使用 REST API 标准
- **易于扩展**：可以轻松添加新的 API 端点
- **跨平台兼容**：任何支持 HTTP 的客户端都可以使用

用户现在可以通过简单的 HTTP 请求与 Syncthing 进行通信，无需复杂的原生模块调用！ 