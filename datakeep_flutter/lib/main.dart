import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';
import 'core/backend/backend_server.dart';
import 'core/backend/syncthing_api.dart';
import 'core/services/native_service.dart';
import 'core/services/syncthing_lifecycle.dart';

/// 保持引用，避免被 GC 后退出钩子失效
// ignore: unused_element
AppLifecycleListener? _desktopLifecycleListener;
// ignore: unused_element
Timer? _parentWatchTimer;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (!kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

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

/// 桌面：关闭窗口 / 退出应用 / 终端挂断时停掉 detached 的 Syncthing
void _installDesktopShutdownHooks() {
  var stopping = false;

  Future<void> stopSyncthingOnce(String reason) async {
    if (stopping) return;
    stopping = true;
    _parentWatchTimer?.cancel();
    debugPrint('[shutdown] $reason，停止 Syncthing…');
    try {
      await NativeService.stopSyncthingService();
    } catch (e) {
      debugPrint('[shutdown] 停止 Syncthing 失败: $e');
    }
  }

  Future<void> shutdownAndExit(String reason) async {
    await stopSyncthingOnce(reason);
    // 确保原因进终端（debugPrint 在 exit 前可能被丢掉）
    stderr.writeln('[shutdown] 退出: $reason');
    exit(0);
  }

  _desktopLifecycleListener = AppLifecycleListener(
    onExitRequested: () async {
      await stopSyncthingOnce('退出前');
      return AppExitResponse.exit;
    },
    onDetach: () {
      unawaited(stopSyncthingOnce('onDetach'));
    },
  );

  try {
    ProcessSignal.sigint.watch().listen((s) => unawaited(shutdownAndExit('收到 $s')));
  } catch (e) {
    debugPrint('[shutdown] 无法监听 SIGINT: $e');
  }
  if (!Platform.isWindows) {
    try {
      ProcessSignal.sigterm.watch().listen((s) => unawaited(shutdownAndExit('收到 $s')));
    } catch (e) {
      debugPrint('[shutdown] 无法监听 SIGTERM: $e');
    }
    try {
      // 终端关闭常发 SIGHUP；但 CEF/子进程等也可能误发。
      // 仅当已成孤儿（父进程已不在）时才退出，避免开发中误杀。
      ProcessSignal.sighup.watch().listen((s) {
        final ppid = _readLinuxPpid();
        final parentAlive =
            ppid != null && ppid > 1 && Directory('/proc/$ppid').existsSync();
        if (parentAlive) {
          debugPrint('[shutdown] 忽略 SIGHUP（父进程 pid=$ppid 仍在）');
          return;
        }
        unawaited(shutdownAndExit('收到 $s（父进程已退出）'));
      });
    } catch (e) {
      debugPrint('[shutdown] 无法监听 SIGHUP: $e');
    }
  }

  // flutter run -d linux：关终端时常只杀掉 flutter tools，应用窗口成孤儿。
  // 监视启动时的父进程，父进程消失则自行退出并停 Syncthing。
  _watchLaunchParent(shutdownAndExit);
}

/// Linux：读 /proc；父进程退出后自动 shutdown（适配裸 flutter run）
void _watchLaunchParent(Future<void> Function(String reason) shutdownAndExit) {
  if (!Platform.isLinux) return;
  final launchPpid = _readLinuxPpid();
  if (launchPpid == null || launchPpid <= 1) {
    debugPrint('[shutdown] 跳过父进程监视 (ppid=$launchPpid)');
    return;
  }
  debugPrint('[shutdown] 监视父进程 pid=$launchPpid（flutter run / 终端退出时自动关闭）');
  var miss = 0;
  _parentWatchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    // 连续两次确认父进程不在，避免 /proc 瞬时不可见误杀
    final alive = Directory('/proc/$launchPpid').existsSync();
    if (alive) {
      miss = 0;
      return;
    }
    miss++;
    if (miss < 2) return;
    _parentWatchTimer?.cancel();
    unawaited(shutdownAndExit('父进程 $launchPpid 已退出'));
  });
}

int? _readLinuxPpid() {
  try {
    for (final line in File('/proc/self/status').readAsLinesSync()) {
      if (line.startsWith('PPid:')) {
        return int.tryParse(line.substring(5).trim());
      }
    }
  } catch (e) {
    debugPrint('[shutdown] 读取 PPid 失败: $e');
  }
  return null;
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
  try {
    await SyncthingApi().ensureAndroidFoldersReady();
  } catch (e, st) {
    debugPrint('[startup] iOS 确保默认文件夹失败: $e');
    debugPrint('$st');
  }
  SyncthingLifecycle.instance.markReady();
}

Future<void> _startAndroidServices() async {
  debugPrint('[startup] Android 启动流程开始');

  final boot = await NativeService.getSyncthingBootstrap();
  var configPath = boot.path;
  var deviceName = boot.deviceName ?? '';
  debugPrint('[startup] bootstrap => path=$configPath, deviceName=$deviceName');

  SyncthingApi().init(configPath: configPath, defaultLocalDeviceName: deviceName);

  // 先启动引擎；首次安装时 config.xml 由 SyncthingService 异步创建，不能先等文件再启动
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

  // 等待 config 落盘 + API 带 apikey 可用（修复冷启动 discovery 空列表）
  for (var i = 0; i < 45; i++) {
    if (configPath != null && File(configPath).existsSync()) {
      SyncthingApi().reloadConfig();
      if (await SyncthingApi().isRunning()) {
        final myId = await SyncthingApi().getLocalDeviceId();
        if (myId != null && myId.isNotEmpty) {
          debugPrint('[startup] Syncthing API 就绪 (${i + 1}/45) myID=$myId');
          break;
        }
      }
    }
    if (i == 44) {
      debugPrint('[startup] Syncthing API 等待超时，Backend 仍将尝试启动');
    }
    await Future.delayed(const Duration(seconds: 1));
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
      await SyncthingApi().ensureLocalDeviceName(deviceName);
    } catch (e, st) {
      debugPrint('[startup] 写入本机设备名失败: $e');
      debugPrint('$st');
    }
  } else {
    debugPrint('[startup] 无设备名，跳过 Syncthing API 写入设备名');
  }

  try {
    await SyncthingApi().ensureAndroidFoldersReady();
  } catch (e, st) {
    debugPrint('[startup] 确保默认文件夹失败: $e');
    debugPrint('$st');
  }

  SyncthingLifecycle.instance.markReady();
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
  SyncthingLifecycle.instance.markReady();
}
