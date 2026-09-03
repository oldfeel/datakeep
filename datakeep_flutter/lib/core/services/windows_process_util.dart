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
  // CREATE_NO_WINDOW | DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
  static const _createFlags = 0x08000000 | 0x00000008 | 0x00000200;

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

  /// 无控制台、不继承句柄地启动进程（适用于 GUI/CUI）。
  /// 返回 PID；失败返回 null。
  static int? startDetachedHidden(String executable, List<String> args) {
    if (kIsWeb || !Platform.isWindows) return null;

    final cmd = StringBuffer()
      ..write('"')
      ..write(executable)
      ..write('"');
    for (final a in args) {
      cmd.write(' ');
      final needQuote = a.contains(' ') || a.contains('\t') || a.isEmpty;
      if (needQuote) {
        cmd
          ..write('"')
          ..write(a.replaceAll('"', r'\"'))
          ..write('"');
      } else {
        cmd.write(a);
      }
    }

    final exePtr = executable.toNativeUtf16();
    final cmdPtr = cmd.toString().toNativeUtf16();
    final si = calloc<STARTUPINFO>();
    final pi = calloc<PROCESS_INFORMATION>();
    try {
      si.ref.cb = sizeOf<STARTUPINFO>();
      si.ref.dwFlags = STARTF_USESHOWWINDOW;
      si.ref.wShowWindow = SW_HIDE;

      final ok = CreateProcess(
        exePtr,
        cmdPtr,
        nullptr,
        nullptr,
        FALSE,
        _createFlags,
        nullptr,
        nullptr,
        si,
        pi,
      );
      if (ok == FALSE) {
        debugPrint('[win32] CreateProcess 失败 err=${GetLastError()}');
        return null;
      }
      final pid = pi.ref.dwProcessId;
      CloseHandle(pi.ref.hThread);
      CloseHandle(pi.ref.hProcess);
      return pid;
    } catch (e) {
      debugPrint('[win32] CreateProcess 异常: $e');
      return null;
    } finally {
      free(exePtr);
      free(cmdPtr);
      calloc.free(si);
      calloc.free(pi);
    }
  }

  static List<int> _pidsForImage(String imageName) {
    final target = imageName.toLowerCase();
    final out = <int>[];
    const maxPids = 1024;
    final bytes = maxPids * 4;
    final pids = calloc<DWORD>(maxPids);
    final needed = calloc<DWORD>();
    try {
      if (EnumProcesses(pids.cast(), bytes, needed) == FALSE) return out;
      final count = (needed.value ~/ sizeOf<DWORD>()).clamp(0, maxPids);
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
