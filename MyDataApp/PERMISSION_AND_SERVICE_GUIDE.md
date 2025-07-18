# MyDataApp 权限和服务启动指南

## 功能概述

MyDataApp 在启动时会自动请求必要权限，并在权限授予后自动启动 Syncthing 服务和 HTTPS API 服务器。

## 权限管理

### 自动请求的权限

应用启动时会自动请求以下权限：

1. **通知权限** (`POST_NOTIFICATIONS`)
   - Android 13+ (API 33+) 需要
   - 用于显示 Syncthing 服务的前台通知

2. **存储权限** (`READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`)
   - 用于访问和同步文件
   - 所有 Android 版本都需要

### 权限请求流程

1. **应用启动** → `MainActivity.onCreate()`
2. **检查权限** → `checkAndRequestPermissions()`
3. **显示权限对话框** → 用户选择允许/拒绝
4. **权限回调** → `permissionLauncher`
5. **启动服务** → 如果所有权限都授予

## 服务启动

### Syncthing 服务

- **服务类**: `com.mydata.app.service.SyncthingService`
- **启动方式**: 前台服务 (`startForegroundService`)
- **功能**: 运行 Syncthing 原生二进制文件

### HTTPS API 服务器

- **服务类**: `com.mydata.app.service.HttpsApiController`
- **端口**: 8443
- **功能**: 提供 REST API 接口

### 服务启动流程

1. **权限授予** → 自动触发服务启动
2. **启动 Syncthing 服务** → `startSyncthingService()`
3. **启动 HTTPS 服务器** → 在 Syncthing 服务中自动启动
4. **显示通知** → 前台服务通知

## 用户界面

### 权限状态显示

应用界面会显示：
- **权限状态**: 通知权限、存储权限的授予状态
- **服务状态**: Syncthing 服务、HTTPS API 的运行状态
- **状态颜色**: 
  - 绿色 ✓: 正常
  - 红色 ✗: 错误/未授予
  - 橙色: 启动中

### 状态更新

- 权限状态在应用启动时检查
- 服务状态通过回调函数更新
- 实时显示当前系统状态

## 技术实现

### MainActivity.kt

```kotlin
// 权限请求
private val permissionLauncher = registerForActivityResult(
    ActivityResultContracts.RequestMultiplePermissions()
) { permissions ->
    val allGranted = permissions.entries.all { it.value }
    if (allGranted) {
        startSyncthingService()
    }
}

// 服务启动
private fun startSyncthingService() {
    val intent = Intent(this, SyncthingService::class.java).apply {
        action = SyncthingService.ACTION_START
    }
    startForegroundService(intent)
}
```

### 权限检查

```kotlin
private fun checkAndRequestPermissions() {
    val permissionsToRequest = mutableListOf<String>()
    
    for (permission in requiredPermissions) {
        if (ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED) {
            permissionsToRequest.add(permission)
        }
    }
    
    if (permissionsToRequest.isEmpty()) {
        startSyncthingService()
    } else {
        permissionLauncher.launch(permissionsToRequest.toTypedArray())
    }
}
```

## 使用说明

### 首次启动

1. 打开 MyDataApp
2. 系统会弹出权限请求对话框
3. 点击"允许"授予所有权限
4. 应用会自动启动 Syncthing 服务
5. 界面显示服务运行状态

### 权限被拒绝

如果用户拒绝了某些权限：
- 应用仍可正常运行
- 但某些功能可能受限
- 可以在系统设置中手动授予权限

### 服务状态

- **运行中**: Syncthing 和 HTTPS API 都正常运行
- **启动中**: 服务正在启动
- **已停止**: 服务未运行
- **错误**: 服务启动失败

## 故障排除

### 权限问题

1. **权限被拒绝**
   - 进入系统设置 → 应用 → MyDataApp → 权限
   - 手动授予所需权限

2. **权限请求不显示**
   - 检查 Android 版本是否支持
   - 重启应用

### 服务问题

1. **服务启动失败**
   - 检查 logcat 日志
   - 确认 Syncthing 二进制文件存在
   - 检查端口是否被占用

2. **HTTPS API 无法访问**
   - 确认服务正在运行
   - 检查端口 8443 是否可访问
   - 验证证书配置

## 日志查看

使用以下命令查看详细日志：

```bash
# 查看应用日志
adb logcat | grep -E "(MainActivity|SyncthingService|HttpsApiController)"

# 查看权限相关日志
adb logcat | grep "MainActivity"

# 查看服务相关日志
adb logcat | grep "SyncthingService"
```

## 注意事项

1. **Android 版本兼容性**
   - 通知权限仅在 Android 13+ 请求
   - 存储权限在所有版本都请求

2. **前台服务**
   - 使用前台服务确保 Syncthing 不被系统杀死
   - 显示持久通知

3. **权限持久化**
   - 权限状态不会持久化存储
   - 每次启动都会检查权限

4. **服务重启**
   - 应用重启时会自动重启服务
   - 系统重启后需要手动启动应用 