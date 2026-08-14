# DataKeep Flutter

DataKeep 是一个基于 Flutter 开发的跨平台文件同步应用，支持桌面端、移动端和 Web 端。

## 功能特性

- 📁 **文件夹管理**: 添加、编辑、删除同步文件夹
- 📱 **设备管理**: 管理多设备同步
- 🔄 **实时同步**: 监控文件变化并自动同步
- 🌐 **跨平台支持**: 桌面 / Android / iOS；移动端 Syncthing 为共用 gomobile 引擎（`syncthing_core`），桌面用系统 syncthing
- 🔗 **文件分享**: 系统分享面板发到微信 / 邮件等（本机文件）
- 📄 **文件预览**: 图片/音视频/文本/PDF；未知类型与大文件走系统打开（不做应用内文档编辑）
- 🎨 **现代化 UI**: 基于 Material Design 3 的优雅界面
- 🔒 **安全可靠**: 支持加密传输和权限管理

## 技术架构

- **前端**: Flutter + Dart
- **状态管理**: Provider
- **网络请求**: HTTP
- **本地存储**: SharedPreferences
- **文件操作**: PathProvider + FilePicker
- **主题**: Material Design 3

## 开发环境要求

- Flutter SDK 3.9.0+
- Dart SDK 3.9.0+
- Android Studio / VS Code
- Git

## 快速开始

### 1. 克隆项目

```bash
git clone <repository-url>
cd datakeep_flutter
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 运行应用

```bash
# 桌面端 (Linux)
flutter run -d linux

# 桌面端 (Windows)
flutter run -d windows

# 桌面端 (macOS)
flutter run -d macos

# Web 端
flutter run -d chrome

# Android 端
flutter run -d android

# iOS 端
flutter run -d ios
```

## 项目结构

```
lib/
├── core/                    # 核心功能
│   ├── models/             # 数据模型
│   ├── services/           # API 服务
│   └── utils/              # 工具函数
├── features/               # 功能模块
│   ├── folders/            # 文件夹管理
│   ├── devices/            # 设备管理
│   └── sync/               # 同步功能
├── shared/                 # 共享组件
│   ├── widgets/            # 通用组件
│   ├── themes/             # 主题配置
│   └── constants/          # 常量定义
└── platform/               # 平台特定代码
    ├── mobile/             # 移动端特定
    ├── desktop/            # 桌面端特定
    └── web/                # Web端特定
```

## 构建发布版本

### 桌面端

```bash
# Linux
flutter build linux

# Windows
flutter build windows

# macOS
flutter build macos
```

### 移动端

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

### Web 端

```bash
flutter build web
```

## 配置说明

### 后端 API 配置

在 `lib/core/services/api_service.dart` 中配置后端服务地址：

```dart
static const String baseUrl = 'http://localhost:8080/api';
```

### 主题配置

在 `lib/shared/themes/app_theme.dart` 中自定义应用主题。

## 开发指南

### 添加新功能

1. 在 `features/` 目录下创建新的功能模块
2. 创建对应的 Provider 进行状态管理
3. 创建 UI 组件和屏幕
4. 更新路由配置

### 代码规范

- 使用中文注释和用户界面文本
- 遵循 Flutter 官方代码规范
- 使用 Provider 进行状态管理
- 实现适当的错误处理和加载状态

## 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

## 许可证

本项目采用 MIT 许可证。

## 联系方式

- 开发者: oldfeel
- 邮箱: hyt5926@163.com

## 更新日志

### v1.0.0
- 初始版本发布
- 支持基本的文件夹和设备管理
- 实现跨平台 UI 框架
