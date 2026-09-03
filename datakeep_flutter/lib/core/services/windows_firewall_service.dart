import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../../shared/constants/app_info.dart';

/// Windows 防火墙：从注册表读取规则，避免 netsh/PowerShell 闪控制台。
class WindowsFirewallService {
  WindowsFirewallService._();

  static const _rulesKey =
      r'SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules';

  /// 是否存在「已启用的入站阻止」规则指向 [exePath]。
  static Future<bool> isSyncthingInboundBlocked(String exePath) async {
    if (kIsWeb || !Platform.isWindows) return false;
    final normalized = _normPath(exePath);
    if (normalized.isEmpty || !File(exePath).existsSync()) return false;

    try {
      return _registryHasInboundBlock(normalized);
    } catch (e) {
      debugPrint('[firewall] 检测失败: $e');
      return false;
    }
  }

  static String _normPath(String path) =>
      path.replaceAll('/', '\\').trim().toLowerCase();

  static bool _registryHasInboundBlock(String targetPath) {
    final phKey = calloc<IntPtr>();
    final keyPath = _rulesKey.toNativeUtf16();
    try {
      final open = RegOpenKeyEx(
        HKEY_LOCAL_MACHINE,
        keyPath,
        0,
        KEY_READ,
        phKey,
      );
      if (open != ERROR_SUCCESS) {
        debugPrint('[firewall] RegOpenKeyEx=$open');
        return false;
      }
      final hKey = phKey.value;
      try {
        final nameBuf = wsalloc(512);
        final nameLen = calloc<Uint32>();
        final type = calloc<Uint32>();
        final dataLen = calloc<Uint32>();
        // 规则串通常 < 4KB
        final dataBuf = calloc<Uint8>(8192);
        try {
          for (var i = 0; ; i++) {
            nameLen.value = 512;
            dataLen.value = 8192;
            final rc = RegEnumValue(
              hKey,
              i,
              nameBuf,
              nameLen,
              nullptr,
              type,
              dataBuf,
              dataLen,
            );
            if (rc == ERROR_NO_MORE_ITEMS) break;
            if (rc != ERROR_SUCCESS) continue;
            if (type.value != REG_SZ && type.value != REG_EXPAND_SZ) continue;

            final raw = dataBuf.cast<Utf16>().toDartString();
            if (_ruleIsInboundBlockFor(raw, targetPath)) return true;
          }
        } finally {
          free(nameBuf);
          calloc.free(nameLen);
          calloc.free(type);
          calloc.free(dataLen);
          calloc.free(dataBuf);
        }
      } finally {
        RegCloseKey(hKey);
      }
    } finally {
      calloc.free(phKey);
      free(keyPath);
    }
    return false;
  }

  /// FirewallRules 值形如：`v2.32|Action=Block|Active=TRUE|Dir=In|App=C:\...\syncthing.exe|...`
  static bool _ruleIsInboundBlockFor(String rule, String targetPath) {
    final fields = <String, String>{};
    for (final part in rule.split('|')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      fields[part.substring(0, idx).toLowerCase()] =
          part.substring(idx + 1).trim();
    }

    final active = (fields['active'] ?? '').toLowerCase();
    if (active != 'true' && active != 'yes') return false;

    final dir = (fields['dir'] ?? '').toLowerCase();
    if (dir != 'in' && dir != 'inbound') return false;

    final action = (fields['action'] ?? '').toLowerCase();
    if (action != 'block') return false;

    final app = fields['app'] ?? fields['application'] ?? '';
    if (app.isEmpty) return false;
    return _normPath(app) == targetPath;
  }

  /// 打开系统防火墙（允许应用）界面。
  static Future<void> openFirewallSettings() async {
    if (!Platform.isWindows) return;
    try {
      final op = 'open'.toNativeUtf16();
      final file = 'firewall.cpl'.toNativeUtf16();
      try {
        ShellExecute(NULL, op, file, nullptr, nullptr, SW_SHOWNORMAL);
      } finally {
        free(op);
        free(file);
      }
    } catch (e) {
      debugPrint('[firewall] 打开设置失败: $e');
    }
  }

  /// 弹窗/说明里用的显示名（与 exe VERSIONINFO 一致）。
  static String get displayName => kAppDisplayName;
}
