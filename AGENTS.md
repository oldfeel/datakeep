# AGENTS.md — MyData

跨平台文件同步应用（基于 Syncthing）。Dart 后端（shelf）+ Flutter 前端。

**长期维护方向**：桌面 + 移动均使用 `mydata_flutter/`（同一套 Flutter 代码）。
`mydata_flutter/backend/`（Go 后端旧版）已停维，仅作参考。

## 仓库结构

| 目录 | 说明 |
|---|---|
| `mydata_flutter/` | **Flutter 跨平台应用** — 桌面 + Android 主力 |
| `mydata_flutter/lib/core/backend/` | Dart 后端 API（shelf HTTPS `:8443`，替代 Go backend） |
| `mydata_flutter/backend/` | Go 后端旧版（已停维，参考用） |
| `syncthing/` | Syncthing 源码（参考 + 交叉编译用） |
| `parse_email/` | 独立工具：eml → markdown 转换 |
| `scripts/start_avd.sh` | Android 模拟器启动脚本 |

## 开发命令

```bash
# Flutter 桌面调试（backend 由 Flutter 进程内启动，无需 air）
cd mydata_flutter && flutter run -d linux

# Flutter Android 调试
cd mydata_flutter && flutter run -d android

# Flutter 依赖安装
cd mydata_flutter && flutter pub get

# Syncthing 编译（必须指定版本，否则 git describe 会取错 hash）
cd syncthing && /snap/go/current/bin/go run build.go -version v2.1.0

# Android Syncthing 原生库交叉编译（写入 jniLibs）
cd mydata_flutter && ./start_android.sh

# Android 模拟器
scripts/start_avd.sh <AVD名称>
```

## API 设计

- **桌面 & Android HTTPS**: `localhost:8443`（自签名证书，Flutter HttpClient 自行放行）
- **后端使用 Dart shelf**，在 Flutter 进程内运行，无需独立进程
- **响应格式**: 成功 `{"code": 0, "data": ...}` / 失败 `{"code": 非0, "data": "错误信息"}`
- **Syncthing API**: `http://127.0.0.1:8384`（HTTP，非 HTTPS），API Key 从 `config.xml` 读取
- 设备 `deviceID == "local"` 表示本机特殊处理

## 重要约定

- 中文注释和用户界面文本
- 自签名证书自动生成在 `certs/cert.pem` 和 `certs/key.pem`（运行目录下）
- Syncthing config.xml 查找优先级：
  Linux: `~/.config/syncthing/config.xml` → `~/.local/state/syncthing/config.xml`
- Flutter 进程内启动 shelf HTTPS 服务器，桌面端在 `main.dart` 中自动启动
- **Flutter 后端无数据库**（SQLite），所有文件浏览代理到 Syncthing API

## 注意点

- **后端已改为纯 Dart**（shelf），不再需要 Go 编译工具链和 air
- **Syncthing 编译坑**：`syncthing/` 不是独立 git 仓库，`go run build.go` 会取 mydata 的 git hash 作为版本号导致启动失败。必须传 `-version v2.1.0`
- Android 原生库由 `mydata_flutter/start_android.sh` 交叉编译（版本如 `v1.28.1-mydata`）
- `parse_email/` 独立于主项目，读取 `mail.eml` → 输出 `chat.md`
- **Go snap 权限问题**：系统 `go` 命令来自 snap 且权限受限，使用 `/snap/go/current/bin/go` 直接调用二进制
