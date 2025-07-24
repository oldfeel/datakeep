# MyData - 跨平台文件同步应用

MyData 是一个基于 Syncthing 的跨平台文件同步应用，支持桌面端和移动端，提供直观的用户界面和强大的文件管理功能。

## 🚀 功能特性

### 📁 文件管理
- **文件夹同步**: 支持双向同步、仅发送、仅接收三种模式
- **实时同步**: 文件变更自动同步到所有设备
- **冲突解决**: 智能处理文件冲突，确保数据安全
- **版本控制**: 支持文件版本管理，可恢复历史版本

### 📱 多平台支持
- **桌面应用**: Windows、macOS、Linux (基于 Wails)
- **移动应用**: Android (React Native + Kotlin)
- **Web 界面**: 基于 React + Material-UI 的现代化界面

### 🔗 设备管理
- **设备发现**: 自动发现局域网内的其他设备
- **连接状态**: 实时显示设备连接状态和同步进度
- **共享管理**: 灵活的文件夹共享设置
- **权限控制**: 细粒度的访问权限管理

### 🌐 网络功能
- **局域网同步**: 优先使用局域网连接，速度快
- **远程访问**: 支持通过互联网远程访问文件
- **HTTPS 安全**: 所有通信采用 HTTPS 加密
- **API 接口**: 提供完整的 RESTful API

## 🛠 技术架构

### 技术栈
- **前端**: React + TypeScript + Material-UI (MUI)
- **桌面应用**: Wails (Go + Web)
- **Android 应用**: React Native + Kotlin + Ktor
- **后端 API**: Go + Fiber (RESTful API)
- **数据库**: SQLite + GORM
- **文件同步**: Syncthing 核心引擎

### 架构设计

#### 多重接口设计
- **Wails 接口**: 桌面应用特有功能（文件夹选择器、系统操作）
- **REST API**: 局域网设备访问和文件管理
- **Android HTTPS API**: Android 设备局域网访问

#### 项目结构
```
mydata/
├── api/                    # 后端 REST API 服务
│   ├── main.go            # 主服务文件
│   ├── handlers.go        # API 处理器
│   └── core.go            # 核心功能
├── client/                # Wails 桌面应用
│   ├── app.go             # Wails 后端
│   └── frontend/          # React 前端
├── MyDataApp/             # Android 应用
│   ├── src/
│   │   ├── screens/       # 页面组件
│   │   ├── components/    # UI 组件
│   │   └── services/      # API 服务
│   └── android/           # Android 原生代码
└── syncthing/             # Syncthing 源码（参考用）
```

## 🚀 快速开始

### 环境要求
- Go 1.19+
- Node.js 16+
- Android Studio (Android 开发)
- Wails CLI

### 安装依赖
```bash
# 安装 Wails CLI
go install github.com/wailsapp/wails/v2/cmd/wails@latest

# 安装前端依赖
cd client/frontend
npm install

# 安装 Android 依赖
cd MyDataApp
npm install
```

### 运行桌面应用
```bash
# 启动后端 API 服务
cd api
go build -o api main.go handlers.go core.go
./api

# 运行桌面应用
cd client
wails dev
```

### 运行 Android 应用
```bash
cd MyDataApp
npm run android
```

## 📖 开发指南

### API 接口规范
所有 API 响应遵循统一格式：

**成功响应：**
```json
{
  "code": 0,
  "data": {...}
}
```

**失败响应：**
```json
{
  "code": 1001,
  "data": "错误信息"
}
```

### 接口调用示例
```typescript
// Wails 接口（桌面功能）
import { SelectFolder } from '../../wailsjs/go/main/App';
const path = await SelectFolder();

// REST API（局域网访问）
const response = await fetch('http://localhost:8080/api/devices');
const devices = await response.json();
```

### 开发流程
1. 修改后端代码 → 重新编译 API
2. 修改前端代码 → Wails 自动热重载
3. 添加 Wails 接口 → 重新生成绑定
4. 修改 Android 代码 → 重新编译 APK

### 常用命令
```bash
# 重新编译 API 服务
cd api && go build -o api main.go handlers.go core.go && ./api

# 重新生成 Wails 绑定
cd client && wails generate module

# 构建 Android APK
cd MyDataApp && npm run build:android
```

## 🔧 配置说明

### 文件夹同步类型
- **发送和接收**: 双向同步，文件变更会同步到所有设备
- **仅发送**: 只向其他设备发送文件，不接收变更
- **仅接收**: 只接收其他设备的文件变更

### 设备连接
- **局域网优先**: 自动使用局域网连接，速度快
- **远程连接**: 支持通过互联网远程访问
- **安全加密**: 所有通信采用 HTTPS 加密

## 🤝 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开 Pull Request

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情。

## 🙏 致谢

- [Syncthing](https://syncthing.net/) - 强大的文件同步引擎
- [Wails](https://wails.io/) - 跨平台桌面应用框架
- [Material-UI](https://mui.com/) - React UI 组件库
- [React Native](https://reactnative.dev/) - 移动应用开发框架

## 📞 联系我们

如有问题或建议，请通过以下方式联系：
- 提交 Issue
- 发送邮件
- 参与讨论

---

**MyData** - 让文件同步更简单、更安全、更高效 🚀 