import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 原版 Syncthing Web GUI 地址（高级配置出口，不做 Flutter 全量复刻）
const String syncthingGuiUrl = 'http://127.0.0.1:8384';

/// 打开 Syncthing 管理页；桌面用系统浏览器，移动端提供说明与复制地址。
Future<void> openSyncthingGui(BuildContext context) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await _showMobileEscapeHatch(context);
    return;
  }

  var opened = false;
  try {
    if (Platform.isLinux) {
      opened = (await Process.run('xdg-open', [syncthingGuiUrl])).exitCode == 0;
    } else if (Platform.isMacOS) {
      opened = (await Process.run('open', [syncthingGuiUrl])).exitCode == 0;
    } else if (Platform.isWindows) {
      opened = (await Process.run(
            'cmd',
            ['/c', 'start', '', syncthingGuiUrl],
            runInShell: true,
          ))
              .exitCode ==
          0;
    }
  } catch (e) {
    debugPrint('打开 Syncthing 管理页失败: $e');
  }

  if (!context.mounted) return;
  if (opened) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已打开 Syncthing 管理页（高级配置）')),
    );
    return;
  }

  await Clipboard.setData(const ClipboardData(text: syncthingGuiUrl));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('无法自动打开浏览器，已复制地址：$syncthingGuiUrl'),
      duration: const Duration(seconds: 4),
    ),
  );
}

Future<void> _showMobileEscapeHatch(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('高级配置'),
      content: const Text(
        '忽略规则、限速、中继、版本控制等高级项请使用原版 Syncthing 管理页，'
        'MyData 不自建完整设置中心。\n\n'
        '本机地址：\n$syncthingGuiUrl\n\n'
        '可在同一设备的浏览器中打开（需 Syncthing 已运行）。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
        ElevatedButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: syncthingGuiUrl));
            if (ctx.mounted) {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制 Syncthing 管理页地址')),
              );
            }
          },
          child: const Text('复制地址'),
        ),
      ],
    ),
  );
}
