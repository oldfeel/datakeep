# API 配置说明

## 双服务架构

本项目使用双服务架构，分别处理不同的功能：

### 1. 原有 API 服务
- **地址**: `http://localhost:8080/`
- **用途**: 设备列表、用户界面、应用核心功能
- **接口示例**:
  - `GET /api/devices` - 获取设备列表
  - `GET /api/folders` - 获取文件夹列表
  - 其他应用相关的 API 接口

### 2. Syncthing 事件服务
- **地址**: `http://127.0.0.1:8384/`
- **用途**: 实时事件监听（syncthing 默认端口）
- **接口示例**:
  - `GET /rest/events` - 事件流接口
  - `GET /rest/system/connections` - 连接状态
  - `GET /rest/system/status` - 系统状态

## 配置说明

### 在代码中的使用

```typescript
// 事件监听服务 - 使用 syncthing 端口 8384
const eventService = new SyncthingEventService('http://127.0.0.1:8384');

// 设备列表加载 - 使用原有 API 端口 8080
const loadDevices = async () => {
  const resp = await fetch('http://localhost:8080/api/devices');
  // ...
};
```

### 端口说明

- **8080 端口**: 应用的主要 API 服务
- **8384 端口**: syncthing 的默认 Web 界面端口

## 启动要求

### 1. 启动原有 API 服务
```bash
# 在 api 目录下启动服务
cd api
go run .
# 服务将在 http://localhost:8080 启动
```

### 2. 启动 Syncthing
```bash
# 启动 syncthing 服务
syncthing
# 或者使用配置文件启动
syncthing -config=/path/to/config
# syncthing 将在 http://127.0.0.1:8384 启动
```

### 3. 启动前端应用
```bash
# 在 client/frontend 目录下启动
cd client/frontend
npm run dev
# 前端应用将启动并连接到两个后端服务
```

## 网络配置

### CORS 配置

确保两个服务都允许跨域请求：

#### 原有 API 服务 (8080)
```go
// 在 Go 服务中添加 CORS 中间件
func enableCORS(w http.ResponseWriter) {
    w.Header().Set("Access-Control-Allow-Origin", "*")
    w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
}
```

#### Syncthing 服务 (8384)
Syncthing 默认允许跨域请求，但可以通过配置文件调整：

```xml
<!-- 在 syncthing 配置文件中 -->
<configuration>
    <gui>
        <address>127.0.0.1:8384</address>
        <allowExternalConnections>true</allowExternalConnections>
    </gui>
</configuration>
```

## 故障排除

### 1. 端口冲突
如果端口被占用，可以修改配置：

**原有 API 服务**:
```go
// 修改端口配置
port := ":8081" // 改为其他可用端口
```

**Syncthing 服务**:
```xml
<!-- 在配置文件中修改端口 -->
<gui>
    <address>127.0.0.1:8385</address>
</gui>
```

### 2. 连接失败
检查以下项目：
- 两个服务是否都已启动
- 端口是否正确
- 防火墙设置
- 网络连接

### 3. 事件监听失败
- 确认 syncthing 正在运行
- 检查 `http://127.0.0.1:8384` 是否可以访问
- 查看浏览器控制台的错误信息

## 开发环境配置

### 环境变量
可以设置环境变量来配置不同的地址：

```bash
# 设置 API 服务地址
export API_BASE_URL=http://localhost:8080

# 设置 syncthing 地址
export SYNCTHING_BASE_URL=http://127.0.0.1:8384
```

### 配置文件
创建配置文件来管理不同的环境：

```typescript
// config.ts
export const config = {
  api: {
    baseUrl: process.env.API_BASE_URL || 'http://localhost:8080',
  },
  syncthing: {
    baseUrl: process.env.SYNCTHING_BASE_URL || 'http://127.0.0.1:8384',
  },
};
```

## 生产环境部署

在生产环境中，建议：

1. **使用反向代理**（如 nginx）统一管理两个服务
2. **配置 SSL 证书**确保安全连接
3. **设置适当的 CORS 策略**
4. **监控服务状态**确保高可用性

### Nginx 配置示例
```nginx
server {
    listen 80;
    server_name your-domain.com;

    # 代理到原有 API 服务
    location /api/ {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # 代理到 syncthing 服务
    location /syncthing/ {
        proxy_pass http://127.0.0.1:8384/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    # 前端静态文件
    location / {
        root /path/to/frontend/dist;
        try_files $uri $uri/ /index.html;
    }
}
``` 