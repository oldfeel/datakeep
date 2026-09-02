import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

/// Windows 进程辅助：不调用 tasklist/taskkill，避免闪控制台。
class WindowsProcessUtil {
  WindowsProcessUtil._();

  static const _processQueryLimited = 0x1000; // PROCESS_QUERY_LIMITED_INFORMATION
  static const _processTerminate = 0x0001; // PROCESS_TERMINATE

  /// 是否存在指定映像名的进程（如 syncthing.exe）。
  static bool hasImageName(String imageName) {
    if (kIsWeb || !Platform.isWindows) return false;
    return _pidsForImage(imageName).isNotEmpty;
  }

  /// 结束所有匹配映像名的进程；返回是否至少结束了一个。
  static bool killByImageName(String imageName) {
    if (kIsWeb || !Platform.isWindows) return false;
    var killed = false;
    for (final pid in _pidsForImage(imageName)) {
      final h = OpenProcess(_processTerminate, FALSE, pid);
      if (h == NULL) continue;
      try {
        if (TerminateProcess(h, 1) != FALSE) killed = true;
      } finally {
        CloseHandle(h);
      }
    }
    return killed;
  }

  static List<int> _pidsForImage(String imageName) {
    final target = imageName.toLowerCase();
    final out = <int>[];
    // 最多枚举 1024 个 PID
    final bytes = 1024 * 4;
    final pids = calloc<DWORD>(1024);
    final needed = calloc<DWORD>();
    try {
      if (EnumProcesses(pids.cast(), bytes, needed) == FALSE) return out;
      final count = (needed.value ~/ sizeOf<DWORD>()).clamp(0, 1024);
      final nameBuf = wsalloc(MAX_PATH);
      final sizePtr = calloc<DWORD>()..value = MAX_PATH;
      try {
        for (var i = 0; i < count; i++) {
          final pid = pids[i];
          if (pid == 0) continue;
          final h = OpenProcess(_processQueryLimited, FALSE, pid);
          if (h == NULL) continue;
          try {
            sizePtr.value = MAX_PATH;
            if (QueryFullProcessImageName(h, 0, nameBuf, sizePtr) == FALSE) {
              continue;
            }
            final path = nameBuf.toDartString();
            final base = path.split(RegExp(r'[\\/]')).last.toLowerCase();
            if (base == target) out.add(pid);
          } finally {
            CloseHandle(h);
          }
        }
      } finally {
        free(nameBuf);
        calloc.free(sizePtr);
      }
    } catch (e) {
      debugPrint('[win32] 枚举进程失败: $e');
    } finally {
      calloc.free(pids);
      calloc.free(needed);
    }
    return out;
  }
}
