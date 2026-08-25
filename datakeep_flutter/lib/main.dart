import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'core/backend/backend_server.dart';
import 'core/backend/syncthing_api.dart';
import 'core/services/native_service.dart';

/// 保持引用，避免被 GC 后退出钩子失效
// ignore: unused_element
AppLifecycleListener? _desktopLifecycleListener;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (!kIsWeb &&
      (Platform.isLinux ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isAndroid ||
          Platform.isIOS)) {
    await _startPlatformServices();
  }

  if (!kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    _installDesktopShutdownHooks();
  }

  runApp(const DataKeepApp());
}

/// 桌面：关闭窗口 / 退出应用时停掉 detached 的 Syncthing
void _installDesktopShutdownHooks() {
  _desktopLifecycleListener = AppLifecycleListener(
    onExitRequested: () async {
      debugPrint('[shutdown] 退出前停止 Syncthing…');
      await NativeService.stopSyncthingService();
      return AppExitResponse.exit;
    },
  );

  Future<void> stopAndExit(ProcessSignal signal) async {
    debugPrint('[shutdown] 收到 $signal，停止 Syncthing…');
    await NativeService.stopSyncthingService();
    exit(0);
  }

  try {
    ProcessSignal.sigint.watch().listen(stopAndExit);
  } catch (e) {
    debugPrint('[shutdown] 无法监听 SIGINT: $e');
  }
  if (!Platform.isWindows) {
    try {
      ProcessSignal.sigterm.watch().listen(stopAndExit);
    } catch (e) {
      debugPrint('[shutdown] 无法监听 SIGTERM: $e');
    }
  }
}

Future<void> _startPlatformServices() async {
  try {
    if (Platform.isAndroid) {
      await _startAndroidServices();
    } else if (Platform.isIOS) {
      await _startIosServices();
    } else {
      await _startDesktopServices();
    }
  } catch (e, st) {
    debugPrint('[startup] 启动服务异常: $e');
    debugPrint('$st');
  }
}

/// iOS：gomobile 进程内 Syncthing + 进程内 shelf（见 ios/SyncthingCore）
Future<void> _startIosServices() async {
  debugPrint('[startup] iOS 启动流程开始');

  String? configPath;
  var deviceName = '';
  for (var i = 0; i < 10; i++) {
    final boot = await NativeService.getSyncthingBootstrap();
    configPath = boot.path;
    if (boot.deviceName != null && deviceName.isEmpty) {
      deviceName = boot.deviceName!;
    }
    debugPrint('[startup] iOS bootstrap 尝试 ${i + 1}/10 => path=$configPath');
    if (configPath != null) break;
    await Future.delayed(const Duration(milliseconds: 500));
  }

  SyncthingApi().init(
    configPath: configPath,
    defaultLocalDeviceName: deviceName,
  );

  if (!await SyncthingApi().isRunning()) {
    try {
      final started = await NativeService.startSyncthingService();
      debugPrint('[startup] iOS startSyncthingService => $started');
    } catch (e, st) {
      debugPrint('[startup] iOS startSyncthingService 失败: $e');
      debugPrint('$st');
    }
  } else {
    debugPrint('[startup] iOS Syncthing 已在运行，跳过 start');
  }

  if (deviceName.isEmpty) {
    deviceName = await NativeService.getDefaultDeviceName() ?? '';
  }
  if (deviceName.isEmpty && configPath != null) {
    deviceName = NativeService.readLocalDeviceNameFromConfig(configPath) ?? '';
  }

  try {
    final backend = BackendServer();
    await backend.start(
      syncthingConfigPath: configPath,
      defaultLocalDeviceName: deviceName,
    );
    debugPrint('[startup] Backend HTTPS 已启动 (iOS), config=$configPath');
  } catch (e, st) {
    debugPrint('[startup] Backend 启动失败: $e');
    debugPrint('$st');
    return;
  }

  if (deviceName.isNotEmpty) {
    try {
      for (var i = 0; i < 20; i++) {
        if (await SyncthingApi().isRunning()) {
          debugPrint('[startup] iOS Syncthing API 就绪 (${i + 1}/20)');
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      await SyncthingApi().ensureLocalDeviceName(deviceName);
    } catch (e, st) {
      debugPrint('[startup] iOS 写入本机设备名失败: $e');
      debugPrint('$st');
    }
  }
}

Future<void> _startAndroidServices() async {
  debugPrint('[startup] Android 启动流程开始');

  String? configPath;
  var deviceName = '';
  for (var i = 0; i < 20; i++) {
    final boot = await NativeService.getSyncthingBootstrap();
    configPath = boot.path;
    if (boot.deviceName != null && deviceName.isEmpty) {
      deviceName = boot.deviceName!;
    }
    debugPrint('[startup] bootstrap 尝试 ${i + 1}/20 => path=$configPath, deviceName=$deviceName');
    if (configPath != null && File(configPath).existsSync()) break;
    await Future.delayed(const Duration(seconds: 1));
  }

  SyncthingApi().init(configPath: configPath, defaultLocalDeviceName: deviceName);

  // 热重启时 Syncthing 可能仍在运行，避免重复启动导致进程冲突
  if (!await SyncthingApi().isRunning()) {
    try {
      final syncthingStarted = await NativeService.startSyncthingService();
      debugPrint('[startup] startSyncthingService => $syncthingStarted');
    } catch (e, st) {
      debugPrint('[startup] startSyncthingService 失败: $e');
      debugPrint('$st');
    }
  } else {
    debugPrint('[startup] Syncthing 已在运行，跳过 startSyncthingService');
  }

  if (deviceName.isEmpty) {
    final fromChannel = await NativeService.getDefaultDeviceName();
    if (fromChannel != null && fromChannel.isNotEmpty) {
      deviceName = fromChannel;
    }
  }
  if (deviceName.isEmpty && configPath != null) {
    deviceName = NativeService.readLocalDeviceNameFromConfig(configPath) ?? '';
    debugPrint('[startup] 从 config 回退 => $deviceName');
  }
  debugPrint('[startup] 本机目标设备名 => $deviceName');

  try {
    final backend = BackendServer();
    await backend.start(
      syncthingConfigPath: configPath,
      defaultLocalDeviceName: deviceName,
    );
    debugPrint('[startup] Backend HTTPS 已启动, config=$configPath');
  } catch (e, st) {
    debugPrint('[startup] Backend 启动失败: $e');
    debugPrint('$st');
    return;
  }

  if (deviceName.isNotEmpty) {
    try {
      for (var i = 0; i < 15; i++) {
        if (await NativeService.ensureSyncthingRunning()) {
          debugPrint('[startup] Syncthing API 就绪 (${i + 1}/15)');
          break;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      await SyncthingApi().ensureLocalDeviceName(deviceName);
      await SyncthingApi().ensureAndroidFoldersReady();
    } catch (e, st) {
      debugPrint('[startup] 写入本机设备名失败: $e');
      debugPrint('$st');
    }
  } else {
    debugPrint('[startup] 无设备名，跳过 Syncthing API 写入');
  }
}

Future<void> _startDesktopServices() async {
  debugPrint('[startup] 桌面端启动流程开始');
  final syncthingOk = await NativeService.startSyncthingService();
  debugPrint('[startup] Syncthing 就绪 => $syncthingOk');
  final backend = BackendServer();
  await backend.start();
  debugPrint('[startup] Backend HTTPS 已启动');
  if (syncthingOk) {
    await SyncthingApi().ensureOverwriteRemoteDeviceNamesOnConnect();
  }
}
