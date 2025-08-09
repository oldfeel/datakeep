# MyDataApp Syncthing 前台服务实现

## 📋 实现概述

参考 syncthing-android 的实现，我们为 MyDataApp 创建了完整的 Android 前台服务来运行 Syncthing。

## 🔧 技术架构

### 1. Android 原生层

#### SyncthingService.kt
- **功能**：Android 前台服务，运行 Syncthing 原生二进制文件
- **特点**：
  - 前台服务，确保在后台持续运行
  - 状态管理（INIT, STARTING, ACTIVE, STOPPING, STOPPED, ERROR）
  - 通知管理，显示服务状态
  - 生命周期管理

#### SyncthingModule.kt
- **功能**：React Native 原生模块，桥接 JavaScript 和 Android 服务
- **特点**：
  - 服务绑定和解绑
  - 事件发送到 React Native
  - 异步操作处理

#### SyncthingPackage.kt
- **功能**：React Native 模块包，注册 SyncthingModule

### 2. React Native 层

#### SyncthingService.ts
- **功能**：TypeScript 类型定义和服务接口
- **特点**：
  - 类型安全的 API 接口
  - 事件监听器管理
  - 异步操作封装

#### SyncthingServiceManager.tsx
- **功能**：React 组件，提供用户界面管理服务
- **特点**：
  - 实时状态显示
  - 启动/停止/重启服务
  - 状态指示器和加载状态

## 📁 文件结构

```
MyDataApp/
├── android/app/src/main/
│   ├── java/com/mydata/app/
│   │   ├── SyncthingModule.kt          # React Native 模块
│   │   ├── SyncthingPackage.kt         # 模块包
│   │   └── service/
│   │       └── SyncthingService.kt     # Android 前台服务
│   ├── res/drawable/
│   │   └── ic_notification.xml         # 通知图标
│   └── AndroidManifest.xml             # 权限和服务声明
├── src/
│   ├── components/
│   │   └── SyncthingServiceManager.tsx # 服务管理组件
│   └── types/
│       └── SyncthingService.ts         # TypeScript 类型定义
└── ...
```

## 🔐 权限配置

在 `AndroidManifest.xml` 中添加了必要的权限：

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

## 🚀 使用方法

### 1. 启动服务
```typescript
import { SyncthingService } from '../types/SyncthingService';

// 启动 Syncthing 服务
await SyncthingService.startService();
```

### 2. 停止服务
```typescript
// 停止 Syncthing 服务
await SyncthingService.stopService();
```

### 3. 获取状态
```typescript
// 获取服务状态
const status = await SyncthingService.getServiceStatus();
console.log('服务状态:', status.state);
console.log('是否运行:', status.isRunning);
```

### 4. 事件监听
```typescript
// 监听服务连接事件
const listener = SyncthingService.addEventListener('onServiceConnected', () => {
  console.log('服务已连接');
});

// 清理监听器
listener.remove();
```

### 5. 在组件中使用
```tsx
import { SyncthingServiceManager } from '../components/SyncthingServiceManager';

<SyncthingServiceManager 
  onStatusChange={(status) => {
    console.log('状态变化:', status);
  }}
/>
```

## 🔄 服务状态流程

```
INIT → STARTING → ACTIVE → STOPPING → STOPPED
  ↓        ↓         ↓         ↓
ERROR ←───────────────┴─────────────┘
```

### 状态说明
- **INIT**: 服务初始化
- **STARTING**: 正在启动 Syncthing
- **ACTIVE**: Syncthing 正在运行
- **STOPPING**: 正在停止 Syncthing
- **STOPPED**: 服务已停止
- **ERROR**: 发生错误

## 🎯 与 syncthing-android 的对比

| 特性 | syncthing-android | MyDataApp |
|------|------------------|-----------|
| 前台服务 | ✅ | ✅ |
| 状态管理 | ✅ | ✅ |
| 通知管理 | ✅ | ✅ |
| React Native 集成 | ❌ | ✅ |
| TypeScript 支持 | ❌ | ✅ |
| 组件化 UI | ❌ | ✅ |
| 事件系统 | ✅ | ✅ |

## 🔧 技术特点

### 1. 前台服务
- 使用 `startForeground()` 确保服务不被系统杀死
- 创建通知渠道和持久通知
- 支持 Android 8.0+ 的前台服务类型

### 2. 服务绑定
- 使用 `ServiceConnection` 绑定服务
- 支持服务状态实时同步
- 自动处理服务断开重连

### 3. 事件系统
- 使用 `DeviceEventManagerModule` 发送事件
- 支持 TypeScript 类型安全的事件监听
- 自动清理事件监听器

### 4. 错误处理
- 完善的异常捕获和处理
- 用户友好的错误提示
- 服务状态错误恢复

## 🚀 下一步计划

### 1. 功能扩展
- [ ] 添加服务自动启动
- [ ] 实现服务配置管理
- [ ] 添加日志查看功能
- [ ] 实现服务健康检查

### 2. 性能优化
- [ ] 优化服务启动时间
- [ ] 减少内存占用
- [ ] 优化事件传递效率

### 3. 用户体验
- [ ] 添加服务状态动画
- [ ] 实现服务配置界面
- [ ] 添加服务统计信息

## 🎉 总结

我们成功实现了：

1. **完整的 Android 前台服务**：确保 Syncthing 在后台持续运行
2. **React Native 集成**：提供类型安全的 JavaScript API
3. **用户友好的界面**：直观的服务管理组件
4. **健壮的错误处理**：完善的异常处理和状态管理
5. **事件驱动架构**：实时状态同步和事件通知

这个实现为 MyDataApp 提供了强大的 Syncthing 服务管理能力，用户可以轻松启动、停止和管理 Syncthing 服务！ 