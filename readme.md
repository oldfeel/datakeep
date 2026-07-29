# MyData - 跨平台文件同步应用

基于 Syncthing 的跨平台文件同步应用，桌面与移动端共用同一套 Flutter 代码。

## 功能特性

- **文件夹同步**：双向同步，实时变更同步到各设备
- **设备管理**：局域网发现、连接状态、共享与访问权限（同步 / 只读 / 隐藏）
- **文件浏览**：浏览本机与对端文件夹
- **多平台**：Linux / Windows / macOS / Android（Flutter）

## 技术架构

| 层级 | 技术 |
|---|---|
| 应用 UI | Flutter |
| 进程内 API | Dart shelf（HTTPS `:8443`） |
| 同步引擎 | Syncthing（本机 `127.0.0.1:8384`） |

### 项目结构

```
mydata/
├── mydata_flutter/          # Flutter 跨平台应用（主力）
│   ├── lib/                 # Dart UI + 进程内后端
│   ├── android/             # Android 工程（含 jniLibs/Syncthing）
│   └── backend/             # Go 后端旧版（已停维）
├── syncthing/               # Syncthing 源码（参考 + 交叉编译）
├── parse_email/             # 独立工具：eml → markdown
└── scripts/                 # 辅助脚本（如 AVD 启动）
```

## 快速开始

### 环境要求

- Flutter（stable）
- Android SDK / NDK（仅 Android）
- Go（仅编译 Syncthing 原生库时需要）

### 桌面调试

```bash
cd mydata_flutter
flutter pub get
flutter run -d linux
```

### Android 调试

```bash
cd mydata_flutter
./start_android.sh          # 必要时交叉编译 libsyncthing.so 并运行
# 或已有 jniLibs 时：
flutter run -d android
```

### Syncthing 源码编译（可选）

```bash
cd syncthing
/snap/go/current/bin/go run build.go -version v2.1.0
```

## API 约定

- 本机 MyData API：`https://localhost:8443`（自签名证书）
- 成功：`{"code": 0, "data": ...}`
- 失败：`{"code": 非0, "data": "错误信息"}`
- Syncthing REST：`http://127.0.0.1:8384`

更完整的开发约定见 [AGENTS.md](AGENTS.md)。

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE)。

## 致谢

- [Syncthing](https://syncthing.net/) — 文件同步引擎
- [Flutter](https://flutter.dev/) — 跨平台 UI 框架
