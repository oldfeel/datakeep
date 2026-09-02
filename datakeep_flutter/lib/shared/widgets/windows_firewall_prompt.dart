import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/native_service.dart';
import '../../core/services/windows_firewall_service.dart';
import '../../shared/constants/app_info.dart';

/// 本会话是否已弹过（避免反复打扰）
bool _firewallPromptShownThisSession = false;

/// Syncthing 被防火墙阻止时提示用户放行（仅 Windows）。
Future<void> maybeShowWindowsFirewallPrompt(BuildContext context) async {
  if (kIsWeb || !Platform.isWindows) return;
  if (_firewallPromptShownThisSession) return;
  if (!context.mounted) return;

  final exe = await NativeService.findSyncthingExecutablePath();
  if (exe == null || exe.isEmpty) return;

  final blocked = await WindowsFirewallService.isSyncthingInboundBlocked(exe);
  if (!blocked) return;

  final prefs = await SharedPreferences.getInstance();
  final ackKey = 'firewall_block_ack:${exe.toLowerCase()}';
  if (prefs.getBool(ackKey) == true) return;

  if (!context.mounted) return;
  _firewallPromptShownThisSession = true;

  final openSettings = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      title: const Text('需要允许局域网权限'),
      content: Text(
        'Windows 防火墙正在阻止「$kAppDisplayName」，局域网将无法发现其他设备。\n\n'
        '请在「允许应用通过防火墙」中找到「$kAppDisplayName」（或 syncthing.exe），'
        '勾选「专用」和「公用」，然后完全退出并重新打开本应用。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('稍后'),
        ),
        TextButton(
          onPressed: () async {
            final p = await SharedPreferences.getInstance();
            await p.setBool(ackKey, true);
            if (ctx.mounted) Navigator.pop(ctx, false);
          },
          child: const Text('不再提醒'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('打开防火墙设置'),
        ),
      ],
    ),
  );

  if (openSettings == true) {
    await WindowsFirewallService.openFirewallSettings();
  }
}
