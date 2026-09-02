import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../shared/constants/app_info.dart';

/// Windows 防火墙：检测本机 syncthing.exe 是否被入站阻止。
/// 使用 netsh（CREATE_NO_WINDOW），避免 PowerShell 闪控制台。
class WindowsFirewallService {
  WindowsFirewallService._();

  /// 是否存在「已启用的入站阻止」规则指向 [exePath]。
  static Future<bool> isSyncthingInboundBlocked(String exePath) async {
    if (kIsWeb || !Platform.isWindows) return false;
    final normalized = _normPath(exePath);
    if (normalized.isEmpty || !File(exePath).existsSync()) return false;

    try {
      final result = await Process.run(
        'netsh',
        const [
          'advfirewall',
          'firewall',
          'show',
          'rule',
          'name=all',
          'dir=in',
          'verbose',
        ],
      );
      if (result.exitCode != 0) {
        debugPrint('[firewall] netsh exit=${result.exitCode} stderr=${result.stderr}');
        return false;
      }
      return _parseBlocked(result.stdout.toString(), normalized);
    } catch (e) {
      debugPrint('[firewall] 检测失败: $e');
      return false;
    }
  }

  static String _normPath(String path) =>
      path.replaceAll('/', '\\').trim().toLowerCase();

  /// 解析 netsh verbose 输出：按空行分块，匹配 Program + Enabled + Action。
  static bool _parseBlocked(String raw, String targetPath) {
    var blocked = false;
    final blocks = raw.split(RegExp(r'\r?\n\r?\n'));
    for (final block in blocks) {
      final lines = block.split(RegExp(r'\r?\n'));
      String? program;
      String? enabled;
      String? action;
      for (final line in lines) {
        final idx = line.indexOf(':');
        if (idx <= 0) continue;
        final key = line.substring(0, idx).trim().toLowerCase();
        final val = line.substring(idx + 1).trim();
        if (key == 'program' || key == '应用程序' || key == '程式') {
          program = _normPath(val);
        } else if (key == 'enabled' || key == '已启用' || key == '啟用') {
          enabled = val.toLowerCase();
        } else if (key == 'action' || key == '操作' || key == '動作') {
          action = val.toLowerCase();
        }
      }
      if (program == null || program != targetPath) continue;
      final isOn = enabled == null ||
          enabled == 'yes' ||
          enabled == 'true' ||
          enabled == '是' ||
          enabled == '是的';
      if (!isOn) continue;
      if (action == 'block' || action == '阻止' || action == '封鎖') {
        blocked = true;
        break;
      }
    }
    return blocked;
  }

  /// 打开系统防火墙（允许应用）界面。
  static Future<void> openFirewallSettings() async {
    if (!Platform.isWindows) return;
    try {
      await Process.start(
        'control.exe',
        const ['firewall.cpl'],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      debugPrint('[firewall] 打开设置失败: $e');
    }
  }

  /// 弹窗/说明里用的显示名（与 exe VERSIONINFO 一致）。
  static String get displayName => kAppDisplayName;
}
