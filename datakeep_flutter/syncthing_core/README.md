# DataKeep SyncthingCore（gomobile 共用引擎）

进程内 Syncthing 薄封装，对齐 [sushitrain](https://github.com/pixelspark/sushitrain) 思路：

| 产物 | 命令 | 使用方 |
|------|------|--------|
| `android/app/libs/syncthingcore.aar` | `make android` | Android 前台服务内调用 |
| `build/DataKeepSyncthing.xcframework` | `make ios`（需 Mac） | iOS CocoaPods `DataKeepSyncthing` |

Go API：`NewClient(home, files)` → `Start` / `Stop` / `IsRunning` / `DeviceID` …

**桌面**：不使用 gomobile；继续 `NativeService` 启动系统 `syncthing`。若日后要进程内嵌入，可对同一 `client.go` 做 `c-shared` + `dart:ffi`，与 gomobile 并行。

## 构建

```bash
# NDK（Android）
export ANDROID_HOME=$HOME/Android/Sdk
# 可选：export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/<version>

cd datakeep_flutter/syncthing_core
make android   # 或 make ios
```

国内网络建议设置代理与 `GOPROXY`。

## 许可证

- Syncthing：MPL-2.0（仓库 `syncthing/`）
- 本目录薄封装为自写实现
