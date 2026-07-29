# Cursor 项目设定

开发约定以根目录 [AGENTS.md](AGENTS.md) 为准（含**产品定位与功能取舍**）。

## 技术栈

- **应用**：Flutter（桌面 + Android，`mydata_flutter/`）
- **进程内 API**：Dart shelf（HTTPS `:8443`）
- **同步引擎**：Syncthing（`127.0.0.1:8384`）

## 产品原则（摘要）

- 不做原版 Syncthing GUI 全量对等
- 补功能优先：忽略规则 → 文件夹类型 → 暂停/扫描 → 冲突提示 → 本机二维码
- 高级配置：打开 Syncthing 管理页，而非自建完整设置中心

## 常用命令

```bash
cd mydata_flutter && flutter run -d linux
cd mydata_flutter && flutter run -d android
cd mydata_flutter && ./start_android.sh   # 交叉编译 libsyncthing.so 并运行
```

## 说明

旧版 `client/`（Wails）与 `app/`（React Native）已从仓库移除；历史可在 git 中找回。
