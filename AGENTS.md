# AGENTS.md — MyData

跨平台文件同步应用（基于 Syncthing）。Dart 后端（shelf）+ Flutter 前端。

**长期维护方向**：桌面 + 移动均使用 `mydata_flutter/`（同一套 Flutter 代码）。
`mydata_flutter/backend/`（Go 后端旧版）已停维，仅作参考。

## 产品定位（功能取舍）

**不追求与原版 Syncthing Web GUI 功能对等。** MyData 是引擎之上的轻量客户端，面向日常「加设备、加文件夹、看文件、管共享」；深度配置继续交给 Syncthing 原版 Web UI（`http://127.0.0.1:8384`）或手改 `config.xml`。

### 原则

1. 只做「没有 UI 就严重影响日常使用」的能力
2. MyData 特有能力（peer 只读浏览、文件夹 ACL：同步/只读/隐藏）优先于追平原版设置页
3. 高级能力：应用内提供「打开 Syncthing 管理页」出口，而不是在 Flutter 里 1:1 复刻

### 若补功能时的优先级（基础能力已落地）

1. ~~忽略规则（简单文本编辑）~~ — 文件夹编辑「忽略」页
2. ~~文件夹类型：双向 / 仅发送 / 仅接收~~ — 文件夹编辑「同步」页
3. ~~暂停文件夹、手动扫描~~ — 同上
4. ~~失败/冲突文件的基础提示~~ — 文件夹编辑「问题」页
5. ~~本机设备 ID 二维码展示~~ — 本机设备信息 / 侧栏 / 抽屉
6. ~~多媒体预览打磨~~ — 流式预览、PDF/系统打开、邻图滑动、统一分发
7. ~~对外分享（无公网 IP）~~ — S3 兼容上传 + 预签名链接（成本优先七牛）
8. iOS Syncthing 进程内引擎 — Go 薄封装 + `make -C ios/SyncthingCore` 产出 xcframework；`./start_ios.sh` 一键构建并运行（参考 sushitrain）

### 明确不做

- **应用内文档编辑**（Office / Markdown 富编辑）：仅「系统打开」；外部修改后靠 Syncthing 扫描同步
- 完整 Settings、Versioning 细配置、Override/Revert、Advanced 配置编辑器等（交给原版 GUI / config）
- frp/ngrok 内置、把家中目录永久挂公网

### 长期不做（交给原版 GUI / config）

- 完整 Settings（GUI/连接/中继/NAT/主题/语言/使用报告）
- 全套 Versioning 四种模式的细配置
- Override/Revert、Global Changes、完整 transfer 明细
- Advanced 配置编辑器、升级/关机对话框、完整日志查看器

## 仓库结构

| 目录 | 说明 |
|---|---|
| `mydata_flutter/` | **Flutter 跨平台应用** — 桌面 + Android 主力；iOS 脚手架已就绪（引擎待编） |
| `mydata_flutter/ios/SyncthingCore/` | iOS gomobile 引擎说明（参考 sushitrain） |
| `mydata_flutter/lib/core/backend/` | Dart 后端 API（shelf HTTPS `:8443`，替代 Go backend） |
| `mydata_flutter/backend/` | Go 后端旧版（已停维，参考用） |
| `syncthing/` | Syncthing 源码（参考 + 交叉编译用） |
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
