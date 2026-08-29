import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/discovered_devices_store.dart';
import '../../features/devices/providers/device_provider.dart';

enum DiscoveredDevicePromptAction { add, ignore, later }

Future<void> showDiscoveredDevicePrompt(
  BuildContext context,
  DiscoveredDevice device,
) async {
  final action = await showDialog<DiscoveredDevicePromptAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新设备'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('局域网发现设备「${device.displayName}」。要添加到本机吗？'),
          const SizedBox(height: 12),
          Text('设备 ID', style: Theme.of(ctx).textTheme.labelMedium),
          SelectableText(
            device.deviceId,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (device.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('地址: ${device.address}', style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DiscoveredDevicePromptAction.later),
          child: const Text('稍后'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DiscoveredDevicePromptAction.ignore),
          child: const Text('忽略'),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.of(ctx).pop(DiscoveredDevicePromptAction.add),
          child: const Text('添加'),
        ),
      ],
    ),
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case DiscoveredDevicePromptAction.later:
      break;
    case DiscoveredDevicePromptAction.ignore:
      await context.read<DiscoveredDevicesStore>().ignore(device.deviceId);
      break;
    case DiscoveredDevicePromptAction.add:
      final name =
          device.displayName == device.deviceId ? '' : device.displayName;
      try {
        await context.read<DeviceProvider>().addDevice(
              deviceID: device.deviceId,
              name: name,
            );
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('设备已添加'),
            content: const Text(
              '已添加到本机。请确认对方设备也添加了本机，才能建立连接。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('好'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red),
        );
      }
  }
}

/// 发现未添加设备时弹出确认框（每个 ID 本会话只弹一次）
class DiscoveredDevicePromptHost extends StatefulWidget {
  const DiscoveredDevicePromptHost({super.key});

  @override
  State<DiscoveredDevicePromptHost> createState() =>
      _DiscoveredDevicePromptHostState();
}

class _DiscoveredDevicePromptHostState extends State<DiscoveredDevicePromptHost> {
  final Set<String> _shown = {};
  bool _dialogOpen = false;

  @override
  Widget build(BuildContext context) {
    final configured = context.watch<DeviceProvider>().devices.map((d) => d.id);
    final items = context.watch<DiscoveredDevicesStore>().available(configured);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow(items));
    return const SizedBox.shrink();
  }

  Future<void> _maybeShow(List<DiscoveredDevice> items) async {
    if (!mounted || _dialogOpen) return;
    for (final device in items) {
      final key = normDeviceId(device.deviceId);
      if (_shown.contains(key)) continue;
      _shown.add(key);
      _dialogOpen = true;
      await showDiscoveredDevicePrompt(context, device);
      _dialogOpen = false;
      break;
    }
  }
}
