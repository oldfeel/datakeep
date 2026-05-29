import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'app.dart';
import 'core/backend/backend_server.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    try {
      // 启动 Dart 后端
      final backend = BackendServer();
      await backend.start();
      debugPrint('Dart Backend 服务启动成功');

      // 启动 Syncthing
      await _startSyncthing();
    } catch (e) {
      debugPrint('启动服务时出错: $e');
    }
  }

  runApp(const MyDataApp());
}

Future<void> _startSyncthing() async {
  // 检查是否已在运行
  try {
    final pgrep = await Process.run('pgrep', ['-f', 'syncthing']);
    if (pgrep.exitCode == 0 && pgrep.stdout.toString().trim().isNotEmpty) {
      debugPrint('Syncthing 已在运行');
      return;
    }
  } catch (_) {}

  // 查找 syncthing 可执行文件
  final candidates = [
    '/home/oldfeel/git/mydata/syncthing/bin/syncthing',
    '${Platform.environment['HOME'] ?? ''}/.local/bin/syncthing',
    '/usr/local/bin/syncthing',
    '/usr/bin/syncthing',
  ];

  String? syncthingPath;
  for (final p in candidates) {
    if (File(p).existsSync()) {
      syncthingPath = p;
      break;
    }
  }

  if (syncthingPath == null) {
    // 尝试通过 which 查找
    try {
      final result = await Process.run('which', ['syncthing']);
      if (result.exitCode == 0) {
        syncthingPath = result.stdout.toString().trim();
      }
    } catch (_) {}
  }

  if (syncthingPath == null || syncthingPath.isEmpty) {
    debugPrint('未找到 Syncthing 可执行文件，请先编译: cd syncthing && go run build.go');
    return;
  }

  final homeDir = Platform.environment['HOME'] ?? '.';
  final configPath = '$homeDir/.config/syncthing';

  try {
    await Process.start(syncthingPath, ['-no-browser', '-no-restart', '-home', configPath],
        mode: ProcessStartMode.detached);
    debugPrint('Syncthing 已启动');
  } catch (e) {
    debugPrint('启动 Syncthing 失败: $e');
  }
}
