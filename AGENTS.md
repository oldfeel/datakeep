# AGENTS.md — MyData

跨平台文件同步应用（基于 Syncthing）。Dart 后端（shelf）+ Flutter 前端。

**长期维护方向**：桌面 `mydata_flutter/`（Flutter）+ 移动 `mydata_flutter/`（Flutter，同一套代码）。
`client/`（Wails 桌面 + Go 后端原始版）、`mydata_flutter/backend/`（Go 后端旧版）和 `app/`（React Native）已停维。

## 仓库结构

| 目录 | 说明 |
|---|---|
| `mydata_flutter/` | **Flutter 跨平台应用** — 桌面 + Android 主力 |
| `mydata_flutter/lib/core/backend/` | Dart 后端 API（shelf HTTPS `:8443`，替代 Go backend） |
| `mydata_flutter/backend/` | Go 后端旧版（已停维，参考用） |
| `client/` | Wails 桌面应用（已停维，参考用） |
| `client/backend/` | Go 后端原始版（已停维，参考用） |
| `app/` | React Native 移动端（已停维，参考用） |
| `app/lib_build/` | Android Syncthing 原生库交叉编译工具 |
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

# Syncthing 编译
cd syncthing && /snap/go/current/bin/go run build.go

# Android Syncthing 原生库交叉编译
cd app/lib_build && /snap/go/current/bin/go run main.go

# Android 模拟器
scripts/start_avd.sh <AVD名称>
```

## API 设计

- **桌面 & Android HTTPS**: `localhost:8443`（自签名证书，Flutter HttpClient 自行放行）
- **后端使用 Dart shelf**，在 Flutter 进程内运行，无需独立进程
- **响应格式**: 成功 `{"code": 0, "data": ...}` / 失败 `{"code": 非0, "data": "错误信息"}`
- **Syncthing API**: `localhost:8384`，API Key 从 `config.xml` 读取
- 设备 `deviceID == "local"` 表示本机特殊处理

## 重要约定

- 中文注释和用户界面文本
- 自签名证书自动生成在 `certs/cert.pem` 和 `certs/key.pem`（运行目录下）
- SQLite DB: 桌面端 `mydata_flutter/mydata.db`，移动端 `$MYDATA_DATA_DIR/mydata.db`
- Syncthing config.xml 查找优先级：
  Linux: `~/.local/state/syncthing/config.xml` → `~/.config/syncthing/config.xml`
  Android 回退: `/data/data/com.nutomic.syncthingandroid/files/config.xml`
- Flutter 进程内启动 shelf HTTPS 服务器，桌面端在 `main.dart` 中自动启动

## 注意点

- **后端已改为纯 Dart**（shelf），不再需要 Go 编译工具链和 air
- `app/lib_build/main.go` 硬编码了 NDK 路径 `/home/oldfeel/Android/Sdk/ndk/29.0.13846066` 和 Syncthing 版本 `v1.28.1-mydata`
- `parse_email/` 独立于主项目，读取 `mail.eml` → 输出 `chat.md`
- 根目录 `readme.md` 描述的项目结构与实际目录不一致，以代码为准
