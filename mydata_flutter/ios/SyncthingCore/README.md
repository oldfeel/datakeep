# iOS Syncthing 引擎（参考 sushitrain）

本目录用于放置 **gomobile 编译的 Syncthing 进程内库**（`xcframework`），架构对齐
[pixelspark/sushitrain](https://github.com/pixelspark/sushitrain) 的 `SushitrainCore`：

- Go 侧嵌入 Syncthing，暴露薄 `Client` API（gomobile 不支持复杂 slice）
- Swift `AppDelegate` 经 MethodChannel `tech.shupi.mydata/api` 对接 Flutter
- 配置目录：Application Support/syncthing
- 同步数据：Documents（Files App 可见）
- **前台可用、后台尽力**；不对齐 Android 前台服务

## 构建（需 macOS + Xcode + Go）

```bash
# 示例：对照 sushitrain 的 SushitrainCore/Makefile
# gomobile bind -target=ios -o build/MyDataSyncthing.xcframework ./...
```

当前仓库仅保留 Flutter 侧启动路径与 MethodChannel 桩；完整引擎在具备 Mac 环境后编入。

许可证注意：若直接复制 sushitrain 源文件，需保留 MPL-2.0 文件级声明；更稳妥是自写同构封装。
