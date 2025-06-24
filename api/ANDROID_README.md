# MyData API Android 版本

本项目将 MyData API 编译为 Android 可执行文件，并集成到 Syncthing Android 项目中，参考 Syncthing Android 的实现方式。

## 架构说明

### 工作原理
1. **编译阶段**：将 Go 代码编译为 Android 可执行的 `.so` 文件
2. **集成阶段**：将 `.so` 文件和 Java 服务类集成到 syncthing-android 项目
3. **运行阶段**：Syncthing Android 应用启动 MyDataApiService，执行 `.so` 文件作为独立进程
4. **通信方式**：通过 HTTP 请求与 API 进程通信

### 文件结构
```
mydata/
├── api/                           # 原始 API 代码
│   ├── main.go                    # API 主程序
│   ├── main_android.go            # Android 版本入口
│   ├── android_build/             # Android 构建工具
│   │   └── main.go                # 构建脚本（可直接运行）
│   └── ANDROID_README.md          # 本文档
└── syncthing-android/            # Syncthing Android 项目
    └── app/src/main/
        ├── jniLibs/              # 编译后的 .so 文件
        │   ├── arm64-v8a/
        │   │   └── libmydata-api.so
        │   ├── armeabi/
        │   ├── x86/
        │   └── x86_64/
        └── java/com/nutomic/syncthingandroid/service/
            └── MyDataApiService.java  # API 服务类
```

## 环境要求

### 必需工具
- Go 1.21+
- Android NDK
- Android SDK
- gomobile

### 环境变量
```bash
# 设置 Android NDK 路径
export ANDROID_NDK_HOME=/path/to/android-ndk

# 或者设置 Android SDK 和 NDK 版本
export ANDROID_HOME=/path/to/android-sdk
export NDK_VERSION=25.1.8937393
```

## 构建步骤

### 1. 构建 .so 文件

现在有两种方式构建：

#### 方式一：使用 gomobile（推荐）
```bash
# 安装 gomobile
go install golang.org/x/mobile/cmd/gomobile@latest

# 直接运行构建脚本
cd api/android_build
go run main.go
```

#### 方式二：使用 NDK
```bash
# 设置环境变量
export ANDROID_NDK_HOME=/path/to/your/ndk
# 或者
export ANDROID_HOME=/path/to/your/android/sdk
export NDK_VERSION=25.1.8937393

# 直接运行构建脚本
cd api/android_build
go run main.go
```

构建脚本会自动：
- 检测可用的构建工具（gomobile 或 NDK）
- 为所有支持的架构（arm, arm64, x86, x86_64）构建 .so 文件
- 将编译结果放置到 `../syncthing-android/app/src/main/jniLibs/` 目录

### 2. 构建 Android 版本

在 `syncthing-android` 目录中构建：

```bash
cd syncthing-android
./gradlew assembleDebug
```

### 3. 安装和测试

```bash
# 安装到设备
adb install app/build/outputs/apk/debug/app-debug.apk

# 查看日志
adb logcat | grep -E "(MyDataApi|mydata)"
```

### 4. 构建输出
构建完成后，会在以下目录生成 `.so` 文件：
- `syncthing-android/app/src/main/jniLibs/arm64-v8a/libmydata-api.so`
- `syncthing-android/app/src/main/jniLibs/armeabi/libmydata-api.so`
- `syncthing-android/app/src/main/jniLibs/x86/libmydata-api.so`
- `syncthing-android/app/src/main/jniLibs/x86_64/libmydata-api.so`

## Syncthing Android 项目集成

### 1. 添加权限
在 `syncthing-android/app/src/main/AndroidManifest.xml` 中添加：
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

### 2. 注册服务
在 `syncthing-android/app/src/main/AndroidManifest.xml` 中添加：
```xml
<service
    android:name=".service.MyDataApiService"
    android:enabled="true"
    android:exported="false" />
```

### 3. 启动服务
在 Syncthing Android 应用启动时启动 MyData API 服务：
```java
// 在 SyncthingService 或其他合适的地方启动
Intent intent = new Intent(this, MyDataApiService.class);
startService(intent);
```

### 4. 调用 API
```java
// 检查服务状态
String healthUrl = "http://localhost:8080/health";
// 获取设备列表
String devicesUrl = "http://localhost:8080/api/devices";
// 获取文件夹文件
String filesUrl = "http://localhost:8080/api/folder/{folderId}";
```

## 配置说明

### Android 特定配置
- **数据目录**：`/data/data/com.mydata.app/files/`
- **数据库文件**：`mydata.db`
- **Syncthing 配置**：`/data/data/com.nutomic.syncthingandroid/files/config.xml`
- **API 端口**：`8080`

### 环境变量
- `ANDROID_DATA`：应用数据目录
- `TMPDIR`：临时文件目录

## 优势

### 1. 隔离性
- API 作为独立进程运行
- 崩溃不会影响 Android 应用
- 便于进程管理和监控

### 2. 兼容性
- 直接使用 Go 原生代码
- 无需 JNI 接口
- 跨平台兼容性好

### 3. 维护性
- 代码复用性高
- 升级只需替换 `.so` 文件
- 调试和日志管理方便

### 4. 性能
- 原生 Go 代码性能优异
- 减少 JNI 调用开销
- 内存使用效率高

## 注意事项

### 1. 权限管理
- Android 10+ 需要适配分区存储
- 确保应用有足够权限访问文件系统

### 2. 网络配置
- API 服务绑定到 localhost
- 确保防火墙允许本地连接

### 3. 进程管理
- 服务使用 START_STICKY 确保重启
- 正确处理进程生命周期

### 4. 调试
- 使用 `adb logcat` 查看日志
- 监控进程状态和资源使用

## 故障排除

### 常见问题

1. **构建失败**
   - 检查 NDK 路径是否正确
   - 确认 Go 版本兼容性
   - 验证环境变量设置

2. **运行时错误**
   - 检查文件权限
   - 确认端口是否被占用
   - 查看详细错误日志

3. **性能问题**
   - 监控内存使用
   - 检查 CPU 占用
   - 优化数据库查询

## 参考资源

- [Syncthing Android 源码](https://github.com/syncthing/syncthing-android)
- [Go Mobile 文档](https://pkg.go.dev/golang.org/x/mobile)
- [Android NDK 文档](https://developer.android.com/ndk) 