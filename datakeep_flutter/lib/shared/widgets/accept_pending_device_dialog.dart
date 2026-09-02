import 'package:flutter/material.dart';

/// 接受待确认设备（对端已添加本机、本机尚未配置对端）
Future<bool?> showAcceptPendingDeviceDialog({
  required BuildContext context,
  required String deviceId,
  required String name,
  String address = '',
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('新设备请求'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备「${name.isNotEmpty ? name : deviceId}」请求与本机配对。要添加吗？'),
          const SizedBox(height: 12),
          Text('设备 ID', style: Theme.of(ctx).textTheme.labelMedium),
          SelectableText(
            deviceId,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('地址: $address', style: Theme.of(ctx).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(
            '若你曾删除过该设备，添加后双方才能重新连接。',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('忽略'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('添加'),
        ),
      ],
    ),
  );
}
