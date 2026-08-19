# AGENTS.md — DataKeep

跨平台文件同步应用（基于 Syncthing）。Dart 后端（shelf）+ Flutter 前端。

**长期维护方向**：桌面 + 移动均使用 `datakeep_flutter/`（同一套 Flutter 代码）。
`datakeep_flutter/backend/`（Go 后端旧版）已停维，仅作参考。

## 产品定位（功能取舍）

**不追求与原版 Syncthing Web GUI 功能对等。** DataKeep 是引擎之上的轻量客户端，面向日常「加设备、加文件夹、看文件、管共享」；深度配置继续交给 Syncthing 原版 Web UI（`http://127.0.0.1:8384`）或手改 `config.xml`。

### 原则

1. 只做「没有 UI 就严重影响日常使用」的能力
2. DataKeep 特有能力（peer 只读浏览、文件夹 ACL：同步/只读/隐藏）优先于追平原版设置页
3. 高级能力：应用内提供「打开 Syncthing 管理页」出口，而不是在 Flutter 里 1:1 复刻

### 若补功能时的优先级（基础能力已落地）

1. ~~忽略规则（简单文本编辑）~~ — 文件夹编辑「忽略」页
2. ~~文件夹类型：双向 / 仅发送 / 仅接收~~ — 文件夹编辑「同步」页
3. ~~暂停文件夹、手动扫描~~ — 同上
4. ~~失败/冲突文件的基础提示~~ — 文件夹编辑「问题」页
5. ~~本机设备 ID 二维码展示~~ — 本机设备信息 / 侧栏 / 抽屉
6. ~~多媒体预览打磨~~ — 流式预览、PDF/系统打开、邻图滑动、统一分发
7. ~~对外分享~~ — 系统分享（微信/邮件等）；不做公网直链/网盘 API
8. ~~移动端 Syncthing 进程内引擎~~ — 共用 `syncthing_core`（gomobile：iOS xcframework + Android AAR）；桌面编译 `bin/syncthing`（见 `scripts/build_desktop_syncthing.sh`）

应用市场（`datakeep-market`）市场应用包仍在服务器本机 `STORAGE_DIR`；**客户端安装包**经 GitHub Release + BT/磁力分发（`sync-github` 拉 GitHub 写链并生成 `.torrent`；家宽 PC 用 qBittorrent 做种加速国内用户）。

### 代码双推（可选）

本机可将 `origin` 同时 push 到 GitHub 与 Gitee（**仅代码镜像**，安装包不走 Gitee Release）：

```bash
git remote set-url --add --push origin git@github.com:oldfeel/datakeep.git
git remote set-url --add --push origin git@gitee.com:yuncommunity/datakeep.git
```


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
| `datakeep_flutter/` | **Flutter 跨平台应用** — 桌面 + Android 主力；iOS 可用 |
| `datakeep_flutter/syncthing_core/` | **共用** gomobile Syncthing 引擎（iOS + Android） |
| `datakeep_flutter/lib/core/backend/` | Dart 后端 API（shelf HTTPS `:8443`，替代 Go backend） |
| `datakeep_flutter/backend/` | Go 后端旧版（已停维，参考用） |
| `docs/app-package-spec.md` | 应用包规范（开放协议） |
| `examples/hello-app/` | 示例应用 |
| `syncthing/` | Syncthing 源码（供 syncthing_core replace） |
| `scripts/start_avd.sh` | Android 模拟器启动脚本 |

应用市场 **服务端 / 管理后台** 在私有仓库 [oldfeel/datakeep-market](https://github.com/oldfeel/datakeep-market)（`market_server`、`market_admin`）。本仓 Flutter 仅保留可配置 API 基址的市场客户端。

## 开发命令

```bash
# Flutter 桌面调试（backend 进程内 shelf；Syncthing 需先编译到 bin/syncthing）
cd datakeep_flutter && ./start_desktop.sh
# macOS 专用：./start_macos.sh
# 仅编译 Syncthing：bash scripts/build_desktop_syncthing.sh

# Android：先 gomobile AAR，再跑（或 ./start_android.sh）
cd datakeep_flutter && make -C syncthing_core android && flutter run -d android

# iOS（需 Mac）
cd datakeep_flutter && ./start_ios.sh

# Flutter 依赖安装
cd datakeep_flutter && flutter pub get

# Syncthing 源码树（desktop 或其它工具若需独立二进制）
cd syncthing && /snap/go/current/bin/go run build.go -version v2.1.0

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

- **后端已改为纯 Dart**（shelf），不再需要 Go 编译工具链和 air（移动端 Syncthing 引擎仍需 Go + gomobile）
- **Syncthing 编译坑**：`syncthing/` 不是独立 git 仓库，`go run build.go` 会取 datakeep 的 git hash 作为版本号导致启动失败。必须传 `-version v2.1.0`
- 移动端引擎：`make -C datakeep_flutter/syncthing_core android|ios`（共用 Go；勿再依赖 jniLibs `libsyncthing.so`）
- `parse_email/` 独立于主项目，读取 `mail.eml` → 输出 `chat.md`
- **Go snap 权限问题**：系统 `go` 命令来自 snap 且权限受限，使用 `/snap/go/current/bin/go` 直接调用二进制
