# Cursor 项目设定

## 项目架构

### 技术栈
- **前端**: React + TypeScript + Material-UI (MUI)
- **桌面应用**: Wails (Go + Web)
- **后端 API**: Go + Fiber (RESTful API)
- **数据库**: SQLite + GORM

### 架构设计

#### 1. 双重接口设计
- **Wails 接口**: 用于桌面应用特有功能
  - 文件夹选择器 (`SelectFolder`)
  - 系统级操作
  - 本地文件访问
- **REST API (localhost:8080)**: 用于局域网设备访问
  - 设备管理 (`/api/devices`)
  - 文件夹管理 (`/api/device/:deviceId/folders`)
  - 文件浏览 (`/api/folder/:folderId`)
  - Syncthing 代理接口

#### 2. 文件结构
```
mydata/
├── api/                    # 后端 REST API 服务
│   ├── main.go            # 主服务文件
│   ├── handlers.go        # API 处理器
│   └── core.go            # 核心功能
├── client/                # Wails 桌面应用
│   ├── app.go             # Wails 后端
│   └── frontend/          # React 前端
│       └── src/
│           ├── pages/
│           │   ├── App.tsx           # 主应用页面
│           │   └── DeviceDetail.tsx  # 设备详情页面
│           └── wailsjs/              # Wails 生成的绑定
└── syncthing/             # Syncthing 源码（参考用）
```

## 重要设定

### 1. 接口使用原则
- **桌面应用功能** → 使用 Wails 接口
- **局域网访问** → 使用 REST API (localhost:8080)
- **文件选择器** → 使用 Wails 的 `SelectFolder()`
- **设备列表** → 使用 REST API `/api/devices`

### 2. 文件夹管理功能
- **添加文件夹**: 支持 Wails 文件夹选择器
- **编辑文件夹**: 支持修改名称、路径、类型等
- **删除文件夹**: 带确认对话框，自动刷新状态
- **共享设置**: 显示已共享/未共享设备列表，支持勾选管理

### 3. 设备管理
- **设备列表**: 从 REST API 获取
- **设备状态**: 显示连接状态、设备名称
- **共享管理**: 支持添加/移除设备共享

### 4. 状态管理
- **前端状态**: React useState + useEffect
- **后端状态**: 内存变量 + 数据库
- **同步机制**: 删除后自动重新加载，确保状态一致

### 5. 错误处理
- **API 错误**: 显示 Snackbar 提示
- **删除失败**: 自动刷新页面
- **加载失败**: 显示错误信息

## 开发注意事项

### 1. 接口调用
```typescript
// Wails 接口（桌面功能）
import { SelectFolder } from '../../wailsjs/go/main/App';
const path = await SelectFolder();

// REST API（局域网访问）
const response = await fetch('http://localhost:8080/api/devices');
```

### 2. 状态更新
- 删除操作后需要重新加载数据
- 共享设置变化时实时更新状态
- 使用 useEffect 监听状态变化

### 3. 用户体验
- 使用 Material-UI 组件保持一致性
- 提供加载状态和错误提示
- 重要操作需要确认对话框

### 4. 调试信息
- 后端有详细的日志输出
- 前端有 console.log 调试信息
- API 调用有错误处理和状态码检查

## 常用命令

### 编译和运行
```bash
# 编译后端 API
cd api
go build -o api main.go handlers.go core.go
./api

# 运行 Wails 应用
cd client
wails dev

# 重新生成 Wails 绑定
wails generate module
```

### 重新编译和启动服务
```bash
# 重新编译 API 服务（修改代码后需要）
cd api && go build -o api main.go handlers.go core.go

# 启动 API 服务
./api

# 或者一步完成编译和启动
cd api && go build -o api main.go handlers.go core.go && ./api
```

## 开发注意事项

### 1. 接口调用
```typescript
// Wails 接口（桌面功能）
import { SelectFolder } from '../../wailsjs/go/main/App';
const path = await SelectFolder();

// REST API（局域网访问）
const response = await fetch('http://localhost:8080/api/devices');
```

### 2. 状态更新
- 删除操作后需要重新加载数据
- 共享设置变化时实时更新状态
- 使用 useEffect 监听状态变化

### 3. 用户体验
- 使用 Material-UI 组件保持一致性
- 提供加载状态和错误提示
- 重要操作需要确认对话框

### 4. 调试信息
- 后端有详细的日志输出
- 前端有 console.log 调试信息
- API 调用有错误处理和状态码检查

### 5. Cursor 使用规则
- **不要自动编译/重启服务**：修改代码后，用户会手动编译和重启
- **主动修改代码**：根据用户需求直接修改代码文件
- **避免运行终端命令**：除非用户明确要求

### 开发流程
1. 修改后端代码 → 重新编译 API
2. 修改前端代码 → Wails 自动热重载
3. 添加 Wails 接口 → 重新生成绑定

## 参考资源
- Syncthing GUI 源码: `syncthing/gui/` (用于参考 UI 设计)
- Wails 文档: https://wails.io/docs/
- Material-UI 文档: https://mui.com/ 