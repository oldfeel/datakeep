# DataKeep

跨平台文件同步客户端，基于 [Syncthing](https://syncthing.net/) 引擎。桌面与移动端共用同一套 Flutter 代码（`datakeep_flutter/`）。

**定位**：面向日常的「加设备、加文件夹、看文件、管共享」；**不**复刻原版 Syncthing Web GUI 的全部设置。深度配置请用应用内「打开 Syncthing 管理页」（`http://127.0.0.1:8384`）或编辑 `config.xml`。功能取舍见 [AGENTS.md](AGENTS.md)。

## 下载

| 渠道 | 说明 |
|------|------|
| [GitHub Releases](https://github.com/oldfeel/datakeep/releases) | Linux / Windows / macOS / Android 安装包 |
| [datakeep.site](https://datakeep.site/) | 官网下载页（含 BT 磁力链） |

发版与官网同步：`./scripts/release.sh`（详见脚本内 `--help`）。

## 功能概览

- **文件夹同步**：双向 / 仅发送 / 仅接收；忽略规则、暂停、手动扫描
- **设备与共享**：局域网发现；文件夹 ACL（同步 / 只读 / 隐藏）
- **文件浏览**：本机与对端只读浏览；图片/视频/音频/文本/PDF 预览；列表缩略图
- **对外分享**：系统分享（微信、邮件等），发送本机文件
- **应用市场客户端**：可配置市场 API；服务端在私有仓 [datakeep-market](https://github.com/oldfeel/datakeep-market)

## 技术架构

| 层级 | 技术 |
|------|------|
| UI | Flutter（Material 3） |
| 进程内 API | Dart [shelf](https://pub.dev/packages/shelf)（HTTPS `:8443`） |
| 同步引擎 | Syncthing（`127.0.0.1:8384`） |
| 移动端引擎 | `syncthing_core`（gomobile AAR / xcframework） |
| 桌面引擎 | 捆绑 `bin/syncthing`（或系统已安装的 Syncthing） |

## 仓库结构

```
datakeep/
├── datakeep_flutter/           # Flutter 应用（主力）
│   ├── lib/core/backend/       # 进程内 Dart 后端（shelf）
│   ├── syncthing_core/         # 移动端共用 Syncthing 引擎
│   └── backend/                # 旧 Go 后端（已停维，仅供参考）
├── syncthing/                  # Syncthing 源码（编译桌面二进制 / gomobile replace）
├── scripts/                    # 构建、发版、模拟器等脚本
├── docs/                       # 文档（如应用包规范）
└── examples/                   # 示例应用
```

## 快速开始

### 环境

- Flutter stable
- 桌面：系统依赖见 `datakeep_flutter/scripts/linux_media_deps.sh`（Linux 音视频）
- Android：SDK / NDK；需先编译 `syncthing_core` AAR
- 编译 Syncthing / gomobile 时需 Go（见 [AGENTS.md](AGENTS.md)）

### 桌面（推荐）

```bash
cd datakeep_flutter
./start_desktop.sh          # 自动处理 Syncthing 与依赖
# macOS：./start_macos.sh
```

### Android

```bash
cd datakeep_flutter
./start_android.sh          # 编译 syncthing_core + 运行
```

### 仅编译桌面 Syncthing

```bash
bash scripts/build_desktop_syncthing.sh
```

## API 约定（摘要）

- DataKeep：`https://localhost:8443`（自签名证书）
- 响应：`{"code": 0, "data": ...}` 成功 / `{"code": 非0, "data": "..."}` 失败
- Syncthing REST：`http://127.0.0.1:8384`（由 Dart 后端代理，前端不直连）

完整开发命令、目录说明与踩坑见 **[AGENTS.md](AGENTS.md)**。Flutter 子项目说明见 [datakeep_flutter/README.md](datakeep_flutter/README.md)。

## 许可证

本项目采用 [Mozilla Public License 2.0](LICENSE)（MPL-2.0），与所捆绑/引用的 [Syncthing](https://syncthing.net/) 一致。若分发含 Syncthing 引擎的二进制，须遵守 MPL-2.0 对对应源码的提供义务。

## 致谢

- [Syncthing](https://syncthing.net/) — 同步引擎
- [Flutter](https://flutter.dev/) — 跨平台 UI
