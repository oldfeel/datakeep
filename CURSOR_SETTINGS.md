# Cursor 项目设定

开发约定以根目录 [AGENTS.md](AGENTS.md) 为准。

## 技术栈

- **应用**：Flutter（桌面 + Android，`mydata_flutter/`）
- **进程内 API**：Dart shelf（HTTPS `:8443`）
- **同步引擎**：Syncthing（`127.0.0.1:8384`）

## 常用命令

```bash
cd mydata_flutter && flutter run -d linux
cd mydata_flutter && flutter run -d android
cd mydata_flutter && ./start_android.sh   # 交叉编译 libsyncthing.so 并运行
```

## 说明

旧版 `client/`（Wails）与 `app/`（React Native）已从仓库移除；历史可在 git 中找回。
