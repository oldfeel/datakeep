# Syncthing 事件监听功能

## 概述

本项目实现了对 Syncthing 事件的实时监听功能，通过 HTTP 长轮询方式获取 Syncthing 的事件流，并在前端进行实时处理和显示。

## 架构设计

### 双服务架构

项目采用双服务架构来解决跨域问题：

1. **Syncthing 服务** (`http://127.0.0.1:8384`)
   - 提供原始的事件 API
   - 需要 API Key 认证
   - 存在跨域限制

2. **代理 API 服务** (`http://localhost:8080`)
   - 提供代理接口转发请求到 Syncthing
   - 解决跨域问题
   - 统一认证管理

### 事件监听流程

```
前端 React 应用
    ↓ (HTTP 请求)
代理 API 服务 (8080端口)
    ↓ (转发请求)
Syncthing 服务 (8384端口)
    ↓ (事件流)
代理 API 服务
    ↓ (JSON 响应)
前端 React 应用
```

## 实现细节

### 1. 后端代理接口

在 `api/handlers.go` 中实现了 `syncthingEventsProxyHandler` 函数：

```go
func syncthingEventsProxyHandler(c *fiber.Ctx) error {
    // 获取查询参数
    since := c.Query("since", "0")
    timeout := c.Query("timeout", "60")
    
    // 构建 syncthing API URL
    syncthingURL := "http://127.0.0.1:8384/rest/events"
    
    // 添加 API Key 认证
    apiKey := getApiKeyFromConfig()
    if apiKey != "" {
        req.Header.Set("X-API-Key", apiKey)
    }
    
    // 转发请求并返回响应
    // ...
}
```

### 2. 前端事件服务

在 `App.tsx` 中实现了 `SyncthingEventService` 类：

```typescript
class SyncthingEventService {
  constructor(private baseUrl: string = 'http://localhost:8080') { }
  
  // 使用代理接口轮询事件
  private async pollEvents() {
    const response = await fetch(`${this.baseUrl}/api/syncthing/events?since=${this.lastEventId}&timeout=60`);
    // 处理事件...
  }
}
```

## 支持的事件类型

系统支持以下 Syncthing 事件类型：

- `Starting` - 服务启动
- `StartupComplete` - 启动完成
- `DeviceConnected` - 设备连接
- `DeviceDisconnected` - 设备断开
- `DeviceDiscovered` - 设备发现
- `StateChanged` - 状态改变
- `ItemFinished` - 文件同步完成
- `FolderErrors` - 文件夹错误
- `Failure` - 系统错误

## 配置说明

### API Key 配置

系统会自动从 Syncthing 的配置文件中读取 API Key：

1. **Linux/macOS**: `~/.config/syncthing/config.xml`
2. **Windows**: `%APPDATA%\Syncthing\config.xml`
3. **Android**: `/data/data/com.nutomic.syncthingandroid/files/config.xml`

### 端口配置

- **Syncthing 服务**: 8384 端口（默认）
- **代理 API 服务**: 8080 端口（默认）

## 使用方法

### 1. 启动服务

```bash
# 启动 Syncthing 服务
syncthing

# 启动代理 API 服务
cd api
go run .

# 启动前端应用
cd client/frontend
npm run dev
```

### 2. 前端集成

```typescript
// 创建事件服务实例
const eventService = new SyncthingEventService();

// 添加事件监听器
eventService.addEventListener('DeviceConnected', (event) => {
  console.log('设备已连接:', event.data);
});

// 启动事件监听
eventService.start();
```

### 3. 事件处理

系统会自动处理以下事件：

- **设备连接/断开**: 自动刷新设备列表
- **文件同步**: 显示同步进度通知
- **错误事件**: 显示错误通知
- **状态变化**: 更新界面状态

## 调试功能

### 1. 连接状态指示器

界面右上角显示事件连接状态：
- 🟢 绿色: 事件已连接
- 🔴 红色: 事件未连接

### 2. 测试连接按钮

点击"测试连接"按钮可以手动测试事件监听功能。

### 3. 控制台日志

所有事件都会在浏览器控制台中输出详细日志。

### 4. 事件通知

重要事件会以通知形式显示在界面右上角。

## 故障排除

### 1. 403 Forbidden 错误

**问题**: 访问 Syncthing API 时出现 403 错误

**解决方案**:
- 检查 API Key 是否正确配置
- 确认 Syncthing 服务正在运行
- 验证配置文件路径是否正确

### 2. 跨域错误

**问题**: 浏览器阻止跨域请求

**解决方案**:
- 使用代理接口（已实现）
- 确保前端访问的是代理服务地址

### 3. 连接超时

**问题**: 事件监听连接超时

**解决方案**:
- 检查网络连接
- 确认 Syncthing 服务可访问
- 查看控制台错误日志

### 4. 事件不更新

**问题**: 界面没有显示最新事件

**解决方案**:
- 检查事件监听器是否正确注册
- 确认事件类型匹配
- 查看控制台日志

## 性能优化

### 1. 长轮询优化

- 使用 60 秒超时减少请求频率
- 实现指数退避重连机制
- 支持事件过滤减少数据传输

### 2. 内存管理

- 及时清理事件监听器
- 限制通知数量避免内存泄漏
- 使用 WeakMap 优化事件存储

### 3. 网络优化

- 支持连接池复用
- 实现请求缓存机制
- 压缩传输数据

## 扩展功能

### 1. 事件过滤

可以添加事件类型过滤功能：

```typescript
// 只监听特定事件类型
eventService.addEventListener('DeviceConnected', handleDeviceEvent);
eventService.addEventListener('ItemFinished', handleSyncEvent);
```

### 2. 事件持久化

可以将重要事件保存到本地存储：

```typescript
// 保存事件到 localStorage
const saveEvent = (event: SyncthingEvent) => {
  const events = JSON.parse(localStorage.getItem('syncthing_events') || '[]');
  events.push({ ...event, timestamp: Date.now() });
  localStorage.setItem('syncthing_events', JSON.stringify(events.slice(-100)));
};
```

### 3. 事件统计

可以实现事件统计和分析功能：

```typescript
// 统计事件类型
const eventStats = new Map<string, number>();
const updateStats = (event: SyncthingEvent) => {
  const count = eventStats.get(event.type) || 0;
  eventStats.set(event.type, count + 1);
};
```

## 总结

通过代理接口的方式，我们成功解决了 Syncthing API 的跨域问题，实现了稳定可靠的事件监听功能。该方案具有以下优势：

1. **解决跨域问题**: 通过后端代理避免浏览器跨域限制
2. **统一认证**: 在代理层统一处理 API Key 认证
3. **易于维护**: 前端代码简洁，后端逻辑集中
4. **可扩展性**: 支持添加更多代理接口和功能
5. **稳定性**: 实现了重连机制和错误处理

该实现为 Syncthing 事件监听提供了一个完整的解决方案，可以满足实时监控和通知的需求。 