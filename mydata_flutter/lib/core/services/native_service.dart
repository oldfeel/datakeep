import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform Channel 服务，用于与原生代码通信
/// 桌面端使用系统命令，移动端使用 Platform Channel
class NativeService {
  static const MethodChannel _channel = MethodChannel('tech.shupi.mydata/api');
  static bool _isDesktop = !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

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
      // 桌面端：使用 client 后端的 API 地址
      return 'https://localhost:8443/api';
    } else {
      // 移动端：使用 Platform Channel
      try {
        final result = await _channel.invokeMethod<String>('getApiBaseUrl');
        return result ?? 'http://localhost:8080/api';
      } on PlatformException catch (e) {
        debugPrint('获取 API URL 失败: ${e.message}');
        return 'https://localhost:8443/api';
      }
    }
  }

  // ========== 桌面端实现 ==========

  /// 桌面端：启动 Syncthing
  static Future<bool> _startSyncthingDesktop() async {
    try {
      // 先检查是否已经在运行
      final status = await _getSyncthingStatusDesktop();
      if (status == 'running' || status == 'active') {
        debugPrint('Syncthing 已经在运行');
        return true;
      }

      // 查找 Syncthing 可执行文件
      final syncthingPath = await _findSyncthingExecutable();
      if (syncthingPath == null) {
        debugPrint('未找到 Syncthing 可执行文件');
        return false;
      }

      // 获取配置目录
      final homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final configPath = Platform.isWindows
          ? '$homeDir\\AppData\\Local\\Syncthing'
          : Platform.isMacOS
              ? '$homeDir/Library/Application Support/Syncthing'
              : '$homeDir/.config/syncthing';

      // 启动 Syncthing 进程（后台运行）
      final process = await Process.start(
        syncthingPath,
        [
          '-no-browser',
          '-no-restart',
          '-home',
          configPath,
        ],
        mode: ProcessStartMode.detached,
      );

      // 等待一下，检查进程是否成功启动
      await Future.delayed(const Duration(seconds: 1));
      final newStatus = await _getSyncthingStatusDesktop();
      return newStatus == 'running' || newStatus == 'active';
    } catch (e) {
      debugPrint('启动 Syncthing 失败: $e');
      return false;
    }
  }

  /// 桌面端：停止 Syncthing
  static Future<bool> _stopSyncthingDesktop() async {
    try {
      // 查找 Syncthing 进程并终止
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('pkill', ['-f', 'syncthing']);
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

  /// 桌面端：获取 Syncthing 状态
  static Future<String> _getSyncthingStatusDesktop() async {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        // 使用 pgrep 检查进程
        final result = await Process.run('pgrep', ['-f', 'syncthing']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          // 检查 API 是否可访问
          try {
            final client = HttpClient();
            client.connectionTimeout = const Duration(seconds: 2);
            final request = await client.getUrl(Uri.parse('http://127.0.0.1:8384/rest/system/status'));
            final apiKey = _getApiKeyFromConfig();
            if (apiKey.isNotEmpty) {
              request.headers.set('X-API-Key', apiKey);
            }
            final response = await request.close().timeout(const Duration(seconds: 2));
            await response.drain();
            client.close();
            if (response.statusCode == 200) {
              return 'running';
            }
          } catch (e) {
            // API 不可访问，但进程在运行
            debugPrint('Syncthing API 检查失败: $e');
            return 'starting';
          }
          return 'running';
        }
      } else if (Platform.isWindows) {
        // Windows: 使用 tasklist
        final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq syncthing.exe']);
        if (result.stdout.toString().contains('syncthing.exe')) {
          return 'running';
        }
      }
      return 'stopped';
    } catch (e) {
      debugPrint('获取 Syncthing 状态失败: $e');
      return 'unknown';
    }
  }

  /// 查找 Syncthing 可执行文件
  static Future<String?> _findSyncthingExecutable() async {
    // 1. 检查项目根目录下的 syncthing/bin/syncthing
    // 从当前工作目录向上查找项目根目录
    var currentDir = Directory.current;
    var projectRoot = currentDir;
    
    // 向上查找包含 syncthing 目录的目录
    while (true) {
      final syncthingDir = Directory('${projectRoot.path}/syncthing');
      final syncthingBin = File('${syncthingDir.path}/bin/syncthing');
      
      if (await syncthingBin.exists()) {
        return syncthingBin.path;
      }
      
      final parent = projectRoot.parent;
      if (parent.path == projectRoot.path) {
        break; // 到达根目录
      }
      projectRoot = parent;
    }

    // 2. 检查系统 PATH 中的 syncthing
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('which', ['syncthing']);
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim();
          if (path.isNotEmpty) {
            return path;
          }
        }
      }
    } catch (e) {
      // which 命令可能不存在
      debugPrint('which 命令执行失败: $e');
    }

    // 3. Windows: 检查常见安装路径
    if (Platform.isWindows) {
      final commonPaths = [
        r'C:\Program Files\Syncthing\syncthing.exe',
        r'C:\Program Files (x86)\Syncthing\syncthing.exe',
      ];
      for (final path in commonPaths) {
        if (await File(path).exists()) {
          return path;
        }
      }
    }

    return null;
  }

  /// 从配置文件获取 API Key（简化版，实际应该读取配置文件）
  static String _getApiKeyFromConfig() {
    // TODO: 实际应该从配置文件读取
    // 这里返回空字符串，让 Syncthing 使用默认认证
    return '';
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
        final result = await Process.run('pkill', ['-f', 'mydata_backend']);
        return result.exitCode == 0;
      } else if (Platform.isWindows) {
        final result = await Process.run('taskkill', ['/F', '/IM', 'mydata_backend.exe']);
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
        client.badCertificateCallback = (cert, host, port) => true; // 允许自签名证书
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
        final result = await Process.run('pgrep', ['-f', 'mydata_backend']);
        if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
          return 'starting'; // 进程在运行但 API 不可访问
        }
      } else if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq mydata_backend.exe']);
        if (result.stdout.toString().contains('mydata_backend.exe')) {
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
    // 1. 检查打包后的应用目录（data/bin/mydata_backend）
    // 从可执行文件路径获取应用目录
    final executablePath = Platform.resolvedExecutable;
    final executableFile = File(executablePath);
    final executableDir = executableFile.parent;
    
    // Linux: 可执行文件在 bundle/ 目录，data 在同级目录
    // 尝试多个可能的路径
    final possiblePaths = <String>[];
    
    // 打包后的路径（根据 CMakeLists.txt，文件在 bundle/data/bin/mydata_backend）
    // 可执行文件在 bundle/ 目录，data 在同级
    possiblePaths.addAll([
      '${executableDir.path}/../data/bin/mydata_backend',  // bundle/../data/bin/
      '${executableDir.path}/data/bin/mydata_backend',    // bundle/data/bin/
    ]);
    
    // 开发环境：从可执行文件位置向上查找项目根目录
    var searchDir = executableDir;
    for (int i = 0; i < 5; i++) {
      possiblePaths.add('${searchDir.path}/bin/mydata_backend');
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

    // 2. 从当前工作目录向上查找 bin/mydata_backend
    var currentDir = Directory.current;
    var projectRoot = currentDir;
    
    while (true) {
      final backendBin = File('${projectRoot.path}/bin/mydata_backend');
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

