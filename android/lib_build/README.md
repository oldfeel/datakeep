# Syncthing Android 库构建工具

这个工具用于将 Syncthing 编译为 Android 库（AAR）。它是用 Go 语言重写的 `build-syncthing.py` 脚本。

## 环境要求

- Go 1.21 或更高版本
- Android NDK
- Android SDK
- 已克隆的 Syncthing 源代码（位于 `syncthing-android/syncthing` 目录）

## 环境变量

需要设置以下环境变量之一：

1. `ANDROID_NDK_HOME`：直接指定 NDK 路径
2. 或者同时设置：
   - `ANDROID_HOME`：Android SDK 路径
   - `NDK_VERSION`：NDK 版本号

## 使用方法

1. 确保 Syncthing 源代码位于正确位置：
   ```
   syncthing-android/
   ├── syncthing/          # Syncthing 源代码
   └── lib_build/          # 本工具
   ```

2. 进入 lib_build 目录：
   ```bash
   cd syncthing-android/lib_build
   ```

3. 运行构建：
   ```bash
   go run main.go
   ```

构建完成后，编译好的库文件将被放置在 `app/src/main/jniLibs/` 目录下，按架构分类。

## 支持的架构

- arm (armeabi)
- arm64 (arm64-v8a)
- x86
- x86_64

## 支持的平台

- Windows
- Linux
- macOS 