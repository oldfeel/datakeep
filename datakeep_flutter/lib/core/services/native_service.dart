import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../shared/utils/local_http_client.dart';
import '../backend/syncthing_api.dart';

/// Platform Channel 服务，用于与原生代码通信
/// 桌面端使用系统命令，移动端使用 Platform Channel
class NativeService {
  static const MethodChannel _channel = MethodChannel('site.datakeep/api');
  static bool _isDesktop = !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);
  static Future<bool>? _startDesktopInFlight;
  static DateTime? _lastForcedRestart;

  /// 启动 Syncthing 服务
  static Future<bool> startSyncthingService() async {
    if (_isDesktop) {
      // 桌面端：通过系统命令启动
      return await _startSyncthingDesktop();
    } else {
      // 移动端：使用 Platform Channel
      try {
        final result = await _channel.invokeMethod<bool>('startSyncthingService');
        return result ?? false;
      } on PlatformException catch (e) {
        debugPrint('启动 Syncthing 服务失败: ${e.message}');
        return false;
      }
    }
  }

  /// 确保 Syncthing 在运行（桌面端会在 API 不可用时自动重启）
  static Future<bool> ensureSyncthingRunning() async {
    if (_isDesktop) return _startSyncthingDesktop();
    return _isMobileSyncthingReady();
  }

  /// 移动端：API 可用且能读到本机 device ID（避免无 apikey 时误判 403 为就绪）
  static Future<bool> _isMobileSyncthingReady() async {
    try {
      SyncthingApi().reloadConfig();
      if (!await SyncthingApi().isRunning()) return false;
      final id = await SyncthingApi().getLocalDeviceId();
      return id != null && id.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 停止 Syncthing 服务
  static Future<bool> stopSyncthingService() async {
    if (_isDesktop) {
      // 桌面端：通过系统命令停止
      return await _stopSyncthingDesktop();
    } else {
      // 移动端：使用 Platform Channel
      try {
        final result = await _channel.invokeMethod<bool>('stopSyncthingService');
        return result ?? false;
      } on PlatformException catch (e) {
        debugPrint('停止 Syncthing 服务失败: ${e.message}');
        return false;
      }
    }
  }

  /// 停同步后彻底退出进程（Android 杀前台服务同进程）
  static Future<void> exitAppCompletely() async {
    try {
      await stopSyncthingService();
    } catch (e) {
      debugPrint('[exit] 停止 Syncthing 失败: $e');
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (_isDesktop) {
      exit(0);
    }
    try {
      await _channel.invokeMethod('exitApp');
    } catch (e) {
      debugPrint('[exit] exitApp channel 失败: $e，回退 dart exit');
      exit(0);
    }
  }

  /// 重启 Syncthing 服务（授予存储权限后调用）
  static Future<bool> restartSyncthingService() async {
    if (_isDesktop) return false;
    try {
      final result = await _channel.invokeMethod<bool>('restartSyncthingService');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('重启 Syncthing 服务失败: ${e.message}');
      return false;
    }
  }

  /// 获取服务状态
  static Future<String> getServiceStatus() async {
    if (_isDesktop) {
      // 桌面端：检查进程状态
      return await _getSyncthingStatusDesktop();
    } else {
      // 移动端：使用 Platform Channel
      try {
        final result = await _channel.invokeMethod<String>('getServiceStatus');
        return result ?? 'unknown';
      } on PlatformException catch (e) {
        debugPrint('获取服务状态失败: ${e.message}');
        return 'unknown';
      }
    }
  }

  /// 获取 API 基础 URL
  static Future<String> getApiBaseUrl() async {
    if (_isDesktop) {
      return 'https://localhost:8443/api';
    } else {
      return 'https://127.0.0.1:8443/api';
    }
  }

  /// 获取 Android Syncthing 配置路径与手机型号（一次 Platform Channel 调用）
  static Future<({String? path, String? deviceName})> getSyncthingBootstrap() async {
    if (_isDesktop) return (path: null, deviceName: null);
    try {
      final result = await _channel.invokeMethod('getSyncthingConfigPath');
      if (result is Map) {
        final path = result['path']?.toString();
        final deviceName = result['deviceName']?.toString();
        debugPrint('[NativeService] getSyncthingBootstrap => path=$path, deviceName=$deviceName');
        return (path: path, deviceName: deviceName);
      }
      if (result is String) {
        debugPrint('[NativeService] getSyncthingBootstrap (legacy) => path=$result');
        return (path: result, deviceName: null);
      }
    } catch (e, st) {
      debugPrint('[NativeService] getSyncthingBootstrap 失败: $e');
      debugPrint('$st');
    }
    return (path: null, deviceName: null);
  }

  /// @deprecated 请用 [getSyncthingBootstrap]
  static Future<String?> getSyncthingConfigPath() async {
    final boot = await getSyncthingBootstrap();
    return boot.path;
  }

  /// 获取 Android 默认设备名（手机型号）
  static Future<String?> getDefaultDeviceName() async {
    if (_isDesktop) return null;
    try {
      final result = await _channel.invokeMethod<String>('getDefaultDeviceName');
      debugPrint('[NativeService] getDefaultDeviceName => $result');
      return result;
    } catch (e, st) {
      // Hot Restart 不会重载 Kotlin，可能 MissingPluginException
      debugPrint('[NativeService] getDefaultDeviceName 失败: $e');
      debugPrint('$st');
      return null;
    }
  }

  /// 从 config.xml 读取本机设备名（Platform Channel 不可用时的回退）
  static String? readLocalDeviceNameFromConfig(String configPath) {
    try {
      final xml = File(configPath).readAsStringSync();
      final tag = RegExp(r'<device\s+([^>]+)>').firstMatch(xml);
      final attrs = tag?.group(1);
      if (attrs == null) return null;
      final name = RegExp(r'\bname="([^"]*)"').firstMatch(attrs)?.group(1)?.trim();
      debugPrint('[NativeService] config 本机设备名 => $name');
      if (name == null || name.isEmpty) return null;
      final lower = name.toLowerCase();
      if (lower == 'localhost' || lower == 'unknown') return null;
      return name;
    } catch (e) {
      debugPrint('[NativeService] 读取 config 设备名失败: $e');
      return null;
    }
  }

  // ========== 桌面端实现 ==========

  /// 桌面端：启动 Syncthing
  /// 桌面：启动系统 syncthing 二进制（移动端为 gomobile 进程内，见 syncthing_core）
  static Future<bool> _startSyncthingDesktop() async {
    final inFlight = _startDesktopInFlight;
    if (inFlight != null) return inFlight;
    final future = _startSyncthingDesktopImpl();
    _startDesktopInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_startDesktopInFlight, future)) {
        _startDesktopInFlight = null;
      }
    }
  }

  static Future<bool> _startSyncthingDesktopImpl() async {
    try {
      // 以 8384 API 为准判断是否在运行（不用 pgrep -f，会误匹配含 syncthing 字样的 shell 命令）
      if (await _isSyncthingApiReady()) {
        debugPrint('Syncthing 已在运行');
        return true;
      }

      // 进程存在但 API 不可用：先等待（配置重载 / Hot Restart 后常见，勿过早杀掉）
      if (await _hasSyncthingProcess()) {
        for (var i = 0; i < 25; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (await _isSyncthingApiReady()) {
            debugPrint('Syncthing 已就绪');
            return true;
          }
        }
        final last = _lastForcedRestart;
        if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
          debugPrint('Syncthing API 仍不可用，但刚重启过，不再强杀');
          return false;
        }
        debugPrint('Syncthing 进程存在但 API 长时间不可用，正在重启…');
        _lastForcedRestart = DateTime.now();
        await _stopSyncthingDesktop();
        await Future.delayed(const Duration(seconds: 1));
      }

      final syncthingPath = await _findSyncthingExecutable();
      if (syncthingPath == null) {
        debugPrint('未找到 Syncthing 可执行文件');
        debugPrint('请先编译：bash scripts/build_desktop_syncthing.sh（Windows 用 SYNCTHING_GOOS=windows）');
        return false;
      }

      final configPath = _syncthingConfigDir();
      final args = <String>[
        '-no-browser',
        '-no-restart',
        '-no-upgrade',
        '-home',
        configPath,
      ];

      // Windows：detached 会给控制台子系统程序弹出黑窗口；用 Hidden 启动。
      // 其它平台：detached，主进程退出后不带走子进程（退出钩子里再 stop）。
      if (Platform.isWindows) {
        await _startDetachedHiddenWindows(syncthingPath, args);
        debugPrint('已启动 Syncthing（无窗口）path=$syncthingPath');
      } else {
        final process = await Process.start(
          syncthingPath,
          args,
          mode: ProcessStartMode.detached,
        );
        debugPrint('已启动 Syncthing pid=${process.pid} path=$syncthingPath');
      }

      // 等待 API 就绪，最多 20 秒
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (await _isSyncthingApiReady()) {
          debugPrint('Syncthing 已启动并就绪');
          return true;
        }
      }

      debugPrint('Syncthing 启动超时，8384 API 仍不可用');
      return false;
    } catch (e) {
      debugPrint('启动 Syncthing 失败: $e');
      return false;
    }
  }

  /// 桌面端：停止 Syncthing
  static Future<bool> _stopSyncthingDesktop() async {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        // 精确匹配进程名，避免 pkill -f 误杀
        final result = await Process.run('pkill', ['-x', 'syncthing']);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('taskkill', ['/F', '/IM', 'syncthing.exe']);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('停止 Syncthing 失败: $e');
      return false;
    }
  }

  /// Windows：无控制台窗口地启动独立进程（避免 detached 弹黑窗）。
  static Future<void> _startDetachedHiddenWindows(
    String executable,
    List<String> args,
  ) async {
    String psQuote(String s) => "'${s.replaceAll("'", "''")}'";
    final argList = args.map(psQuote).join(',');
    final command =
        'Start-Process -FilePath ${psQuote(executable)} '
        '-ArgumentList @($argList) -WindowStyle Hidden';
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        command,
      ],
    );
    if (result.exitCode != 0) {
      final err = (result.stderr.toString().trim().isNotEmpty)
          ? result.stderr.toString().trim()
          : result.stdout.toString().trim();
      throw ProcessException(
        executable,
        args,
        err.isEmpty ? 'Start-Process 失败 (exit=${result.exitCode})' : err,
        result.exitCode,
      );
    }
  }

  static String _syncthingConfigDir() {
    if (Platform.isWindows) {
      // 与 Syncthing 默认 -home、SyncthingApi._findConfigPath 一致
      final local = Platform.environment['LOCALAPPDATA']?.trim();
      if (local != null && local.isNotEmpty) return '$local\\Syncthing';
      final profile = Platform.environment['USERPROFILE']?.trim();
      if (profile != null && profile.isNotEmpty) {
        return '$profile\\AppData\\Local\\Syncthing';
      }
      return 'Syncthing';
    }
    final homeDir = Platform.environment['HOME']?.trim();
    final home = (homeDir != null && homeDir.isNotEmpty)
        ? homeDir
        : (Platform.environment['USERPROFILE']?.trim() ?? '.');
    if (Platform.isMacOS) return '$home/Library/Application Support/Syncthing';
    return '$home/.config/syncthing';
  }

  /// 8384 API 是否可用（200/403 均表示 Syncthing 在监听）
  static Future<bool> _isSyncthingApiReady() async {
    try {
      final client = HttpClient();
      configureLocalHttpClient(client);
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:8384/rest/system/status'));
      final apiKey = _getApiKeyFromConfig();
      if (apiKey.isNotEmpty) {
        request.headers.set('X-API-Key', apiKey);
      }
      final response = await request.close().timeout(const Duration(seconds: 2));
      await response.drain();
      client.close();
      return response.statusCode == 200 || response.statusCode == 403;
    } catch (_) {
      return false;
    }
  }

  /// 是否存在 syncthing 进程（精确匹配进程名）
  static Future<bool> _hasSyncthingProcess() async {
    if (Platform.isLinux || Platform.isMacOS) {
      final result = await Process.run('pgrep', ['-x', 'syncthing']);
      return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
    }
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq syncthing.exe']);
      return result.stdout.toString().contains('syncthing.exe');
    }
    return false;
  }

  /// 桌面端：获取 Syncthing 状态
  static Future<String> _getSyncthingStatusDesktop() async {
    try {
      if (await _isSyncthingApiReady()) return 'running';
      if (await _hasSyncthingProcess()) return 'starting';
      return 'stopped';
    } catch (e) {
      debugPrint('获取 Syncthing 状态失败: $e');
      return 'unknown';
    }
  }

  /// 查找 Syncthing 可执行文件
  static Future<String?> _findSyncthingExecutable() async {
    final possiblePaths = <String>[];
    final name = Platform.isWindows ? 'syncthing.exe' : 'syncthing';

    // 1. 打包后的应用目录（Linux/Windows: data/bin；macOS: Resources/bin）
    final executablePath = Platform.resolvedExecutable;
    final executableDir = File(executablePath).parent;
    possiblePaths.addAll([
      '${executableDir.path}/../data/bin/$name',
      '${executableDir.path}/data/bin/$name',
      '${executableDir.path}/$name',
      if (Platform.isMacOS) '${executableDir.path}/../Resources/bin/$name',
    ]);

    // 2. 从可执行文件位置向上查找（开发/本地构建）
    var searchDir = executableDir;
    for (var i = 0; i < 10; i++) {
      possiblePaths.addAll([
        '${searchDir.path}/syncthing/bin/$name',
        '${searchDir.path}/bin/$name',
      ]);
      final parent = searchDir.parent;
      if (parent.path == searchDir.path) break;
      searchDir = parent;
    }

    // 3. macOS Homebrew（可选回退）
    if (Platform.isMacOS) {
      possiblePaths.addAll([
        '/opt/homebrew/bin/syncthing',
        '/usr/local/bin/syncthing',
      ]);
    }

    // 4. 从当前工作目录向上查找（flutter run 等场景）
    var currentDir = Directory.current;
    while (true) {
      possiblePaths.addAll([
        '${currentDir.path}/syncthing/bin/$name',
        '${currentDir.path}/bin/$name',
      ]);
      final parent = currentDir.parent;
      if (parent.path == currentDir.path) break;
      currentDir = parent;
    }

    for (final path in possiblePaths) {
      final file = File(path);
      if (await file.exists()) {
        debugPrint('找到 Syncthing 可执行文件: $path');
        return path;
      }
    }

    // 5. 系统 PATH
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('which', ['syncthing']);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim();
          if (path.isNotEmpty) {
            debugPrint('找到 Syncthing 可执行文件: $path');
            return path;
          }
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('where', ['syncthing.exe']);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
          if (path.isNotEmpty && await File(path).exists()) {
            debugPrint('找到 Syncthing 可执行文件: $path');
            return path;
          }
        }
      }
    } catch (e) {
      debugPrint('查找系统 Syncthing 失败: $e');
    }

    // 6. Windows 常见安装路径
    if (Platform.isWindows) {
      final commonPaths = [
        r'C:\Program Files\Syncthing\syncthing.exe',
        r'C:\Program Files (x86)\Syncthing\syncthing.exe',
      ];
      for (final path in commonPaths) {
        if (await File(path).exists()) {
          debugPrint('找到 Syncthing 可执行文件: $path');
          return path;
        }
      }
    }

    return null;
  }

  /// 从 config.xml 读取 Syncthing API Key
  static String _getApiKeyFromConfig() {
    try {
      final configFile = File('${_syncthingConfigDir()}/config.xml');
      if (!configFile.existsSync()) return '';
      final xml = configFile.readAsStringSync();
      final m = RegExp(r'<apikey>([^<]+)</apikey>').firstMatch(xml);
      return m?.group(1)?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  // ========== Backend 服务管理 ==========

  /// 启动 Backend 服务
  static Future<bool> startBackendService() async {
    if (_isDesktop) {
      // 桌面端：通过系统命令启动
      return await _startBackendDesktop();
    } else {
      // 移动端：Backend 在 AAR 中，由 Android Service 管理
      return true;
    }
  }

  /// 停止 Backend 服务
  static Future<bool> stopBackendService() async {
    if (_isDesktop) {
      // 桌面端：通过系统命令停止
      return await _stopBackendDesktop();
    } else {
      // 移动端：Backend 在 AAR 中，由 Android Service 管理
      return true;
    }
  }

  /// 获取 Backend 服务状态
  static Future<String> getBackendStatus() async {
    if (_isDesktop) {
      return await _getBackendStatusDesktop();
    } else {
      return 'running'; // Android 端由 Service 管理
    }
  }

  /// 桌面端：启动 Backend
  static Future<bool> _startBackendDesktop() async {
    try {
      // 先检查是否已经在运行
      final status = await _getBackendStatusDesktop();
      if (status == 'running') {
        debugPrint('Backend 已经在运行');
        return true;
      }

      // 查找 Backend 可执行文件
      final backendPath = await _findBackendExecutable();
      if (backendPath == null) {
        debugPrint('未找到 Backend 可执行文件');
        return false;
      }

      // 启动 Backend 进程（后台运行）
      final process = await Process.start(
        backendPath,
        [],
        mode: ProcessStartMode.detached,
      );

      // 等待一下，检查进程是否成功启动
      await Future.delayed(const Duration(seconds: 2));
      final newStatus = await _getBackendStatusDesktop();
      return newStatus == 'running';
    } catch (e) {
      debugPrint('启动 Backend 失败: $e');
      return false;
    }
  }

  /// 桌面端：停止 Backend
  static Future<bool> _stopBackendDesktop() async {
    try {
      // 查找 Backend 进程并终止
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('pkill', ['-f', 'datakeep_backend']);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('taskkill', ['/F', '/IM', 'datakeep_backend.exe']);
        return result.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('停止 Backend 失败: $e');
      return false;
    }
  }

  /// 桌面端：获取 Backend 状态
  static Future<String> _getBackendStatusDesktop() async {
    try {
      // 检查 API 是否可访问
      try {
        final client = HttpClient();
        configureLocalHttpClient(client, trustCertificate: (_, __) => true);
        client.connectionTimeout = const Duration(seconds: 2);
        final request = await client.getUrl(Uri.parse('https://localhost:8443/api/health'));
        final response = await request.close().timeout(const Duration(seconds: 2));
        await response.drain();
        client.close();
        if (response.statusCode == 200) {
          return 'running';
        }
      } catch (e) {
        // API 不可访问
        debugPrint('Backend API 检查失败: $e');
      }

      // 检查进程是否存在
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('pgrep', ['-f', 'datakeep_backend']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          return 'starting'; // 进程在运行但 API 不可访问
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq datakeep_backend.exe']);
        if (result.stdout.toString().contains('datakeep_backend.exe')) {
          return 'starting';
        }
      }
      return 'stopped';
    } catch (e) {
      debugPrint('获取 Backend 状态失败: $e');
      return 'unknown';
    }
  }

  /// 查找 Backend 可执行文件
  static Future<String?> _findBackendExecutable() async {
    // 1. 检查打包后的应用目录（data/bin/datakeep_backend）
    // 从可执行文件路径获取应用目录
    final executablePath = Platform.resolvedExecutable;
    final executableFile = File(executablePath);
    final executableDir = executableFile.parent;
    
    // Linux: 可执行文件在 bundle/ 目录，data 在同级目录
    // 尝试多个可能的路径
    final possiblePaths = <String>[];
    
    // 打包后的路径（根据 CMakeLists.txt，文件在 bundle/data/bin/datakeep_backend）
    // 可执行文件在 bundle/ 目录，data 在同级
    possiblePaths.addAll([
      '${executableDir.path}/../data/bin/datakeep_backend',  // bundle/../data/bin/
      '${executableDir.path}/data/bin/datakeep_backend',    // bundle/data/bin/
    ]);
    
    // 开发环境：从可执行文件位置向上查找项目根目录
    var searchDir = executableDir;
    for (int i = 0; i < 5; i++) {
      possiblePaths.add('${searchDir.path}/bin/datakeep_backend');
      searchDir = searchDir.parent;
      if (searchDir.path == searchDir.parent.path) break; // 到达根目录
    }

    for (final path in possiblePaths) {
      final file = File(path);
      if (await file.exists()) {
        debugPrint('找到 Backend 可执行文件: $path');
        return path;
      }
    }

    // 2. 从当前工作目录向上查找 bin/datakeep_backend
    var currentDir = Directory.current;
    var projectRoot = currentDir;
    
    while (true) {
      final backendBin = File('${projectRoot.path}/bin/datakeep_backend');
      if (await backendBin.exists()) {
        debugPrint('找到 Backend 可执行文件: ${backendBin.path}');
        return backendBin.path;
      }
      
      final parent = projectRoot.parent;
      if (parent.path == projectRoot.path) {
        break; // 到达根目录
      }
      projectRoot = parent;
    }

    debugPrint('未找到 Backend 可执行文件');
    debugPrint('可执行文件路径: $executablePath');
    debugPrint('可执行文件目录: ${executableDir.path}');
    debugPrint('当前工作目录: ${Directory.current.path}');
    return null;
  }
}

