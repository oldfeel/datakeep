# iOS Syncthing 引擎（参考 sushitrain）

本目录为 **gomobile 编译的 Syncthing 进程内库**（`MyDataSyncthing.xcframework`），架构对齐
[pixelspark/sushitrain](https://github.com/pixelspark/sushitrain) 的 `SushitrainCore`：

- Go 侧嵌入仓库内 `syncthing/`，暴露薄 `Client` API（gomobile 不支持复杂 slice）
- Swift `AppDelegate` 经 MethodChannel `tech.shupi.mydata/api` 对接 Flutter
- 配置目录：Application Support/syncthing
- 同步数据：Documents/sync/…（Files App 可见）
- **前台可用、后台尽力**；不对齐 Android 前台服务

## 构建（需 macOS + Xcode + Go）

国内网络建议先开代理，例如：

```bash
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897
export GOPROXY=https://proxy.golang.org,direct
```

```bash
cd mydata_flutter/ios/SyncthingCore
make build
# 产出：build/MyDataSyncthing.xcframework
```

`pod install` / `flutter run` 时若缺少 xcframework，Podfile 会自动调用 `make build`。

也可一键：

```bash
cd mydata_flutter && ./start_ios.sh
```

## API（Swift）

```swift
import MyDataSyncthing
let client = MdstNewClient(homePath, filesPath)
client?.setDeviceName(UIDevice.current.name)
try client?.start()
client?.isRunning()
client?.stop()
```

## 许可证

- Syncthing：MPL-2.0（本仓库 `syncthing/`）
- 本目录薄封装为自写同构实现；若日后直接复制 sushitrain 源文件，需保留其 MPL-2.0 文件级声明
