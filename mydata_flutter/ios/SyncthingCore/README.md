# Syncthing 进程内引擎（gomobile）

共用 Go 包 [`syncthing_core`](../syncthing_core)，供 **iOS + Android** 使用。

```bash
# Android AAR（Linux / macOS 均可，需 NDK）
make -C syncthing_core android

# iOS xcframework（需 macOS + Xcode）
make -C syncthing_core ios
```

桌面端仍使用系统 `syncthing` 二进制（见 `NativeService`），与本目录 **同一 Syncthing 源码树**（`../../syncthing`），但不走 gomobile。

原 `ios/SyncthingCore` 已迁至 `mydata_flutter/syncthing_core/`。
