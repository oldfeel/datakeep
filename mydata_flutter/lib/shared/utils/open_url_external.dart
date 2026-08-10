import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开 URL（桌面优先 xdg-open/open/start，避免 url_launcher 通道异常）
Future<bool> openUrlExternal(String url) async {
  if (kIsWeb) {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('openUrlExternal web: $e');
      return false;
    }
  }

  try {
    if (Platform.isLinux) {
      return (await Process.run('xdg-open', [url])).exitCode == 0;
    }
    if (Platform.isMacOS) {
      return (await Process.run('open', [url])).exitCode == 0;
    }
    if (Platform.isWindows) {
      return (await Process.run(
            'cmd',
            ['/c', 'start', '', url],
            runInShell: true,
          ))
              .exitCode ==
          0;
    }
    // Android / iOS
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openUrlExternal: $e');
    // 桌面再兜底试一次 url_launcher
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      try {
        return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (e2) {
        debugPrint('openUrlExternal fallback: $e2');
      }
    }
    return false;
  }
}
