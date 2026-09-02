import 'dart:io';

import 'package:flutter/foundation.dart';

/// Windows 防火墙：检测本机 syncthing.exe 是否被入站阻止。
class WindowsFirewallService {
  WindowsFirewallService._();

  /// 是否存在「已启用的入站阻止」规则指向 [exePath]。
  static Future<bool> isSyncthingInboundBlocked(String exePath) async {
    if (kIsWeb || !Platform.isWindows) return false;
    final normalized = _normPath(exePath);
    if (normalized.isEmpty || !File(exePath).existsSync()) return false;

    try {
      // Process.run 默认不继承控制台，带 CREATE_NO_WINDOW，避免闪黑窗。
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          _psCheckScript(normalized),
        ],
      );
      final out = result.stdout.toString().trim();
      if (out == 'BLOCKED') return true;
      if (out == 'OK' || out == 'NONE') return false;
      debugPrint('[firewall] 未知输出: $out stderr=${result.stderr}');
      return false;
    } catch (e) {
      debugPrint('[firewall] 检测失败: $e');
      return false;
    }
  }

  static String _normPath(String path) =>
      path.replaceAll('/', '\\').trim().toLowerCase();

  static String _psCheckScript(String normalizedPath) {
    // 返回 BLOCKED / OK / NONE
    final escaped = normalizedPath.replaceAll("'", "''");
    return '''
\$target = '$escaped'
\$blocked = \$false
\$allowed = \$false
Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | ForEach-Object {
  \$rule = \$_
  if (\$rule.Enabled -ne 'True') { return }
  \$app = \$rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
  if (-not \$app -or -not \$app.Program) { return }
  \$prog = ([string]\$app.Program).Replace('/','\\').Trim().ToLowerInvariant()
  if (\$prog -ne \$target) { return }
  if (\$rule.Action -eq 'Block') { \$blocked = \$true }
  if (\$rule.Action -eq 'Allow') { \$allowed = \$true }
}
if (\$blocked) { 'BLOCKED' }
elseif (\$allowed) { 'OK' }
else { 'NONE' }
''';
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
}
