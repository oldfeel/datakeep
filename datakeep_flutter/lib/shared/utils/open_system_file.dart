import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

/// 用系统应用打开本地文件
Future<String?> openSystemFile(String path) async {
  if (kIsWeb) return 'Web 不支持系统打开';
  try {
    if (Platform.isAndroid || Platform.isIOS) {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        return result.message;
      }
      return null;
    }
    if (Platform.isLinux) {
      final r = await Process.run('xdg-open', [path]);
      if (r.exitCode != 0) return r.stderr.toString();
      return null;
    }
    if (Platform.isMacOS) {
      final r = await Process.run('open', [path]);
      if (r.exitCode != 0) return r.stderr.toString();
      return null;
    }
    if (Platform.isWindows) {
      await Process.run('start', [path], runInShell: true);
      return null;
    }
    return '当前平台不支持系统打开';
  } catch (e) {
    return e.toString();
  }
}
