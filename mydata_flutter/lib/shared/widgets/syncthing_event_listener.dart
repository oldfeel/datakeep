import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/event_service.dart';
import '../../core/services/api_service.dart';
import '../../features/devices/providers/device_provider.dart';
import '../../features/folders/providers/folder_provider.dart';
import 'accept_pending_folder_dialog.dart';

/// 监听 Syncthing 事件，处理待确认设备与待接受共享文件夹（移动端使用）
class SyncthingEventListener extends StatefulWidget {
  final Widget child;

  const SyncthingEventListener({super.key, required this.child});

  @override
  State<SyncthingEventListener> createState() => _SyncthingEventListenerState();
}

class _SyncthingEventListenerState extends State<SyncthingEventListener>
    with WidgetsBindingObserver {
  StreamSubscription<SyncthingEvent>? _eventSub;
  Timer? _pendingPollTimer;
  final Set<String> _shownPendingDevices = {};
  final Set<String> _shownPendingFolders = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingDevices();
      _checkPendingFolders();
    });
    EventService().start();
    _eventSub = EventService().events.listen(_onEvent);
    debugPrint('[pending] SyncthingEventListener 已启动');
    // 兜底：避免热重启跳过重放事件、或设备短暂离线时漏通知
    _pendingPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) {
        _checkPendingFolders();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _checkPendingDevices();
      _checkPendingFolders();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingPollTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  void _onEvent(SyncthingEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'PendingDevicesChanged':
        _handlePendingDevicesChanged(event);
        break;
      case 'PendingFoldersChanged':
        _handlePendingFoldersChanged(event);
        break;
      case 'DeviceConnected':
        context.read<DeviceProvider>().fetchDevices(silent: true);
        break;
    }
  }

  String _normDeviceId(String id) =>
      id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  String _pendingFolderKey(String folderId, String deviceId) =>
      '${_normDeviceId(folderId)}|${_normDeviceId(deviceId)}';

  String _deviceDisplayName(String deviceId) {
    final provider = context.read<DeviceProvider>();
    for (final d in provider.devices) {
      if (_normDeviceId(d.id) == _normDeviceId(deviceId)) {
        return d.displayName;
      }
    }
    return deviceId;
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<Set<String>> _knownDeviceNormIds() async {
    final ids = <String>{};
    try {
      for (final d in await ApiService.getDevices()) {
        ids.add(_normDeviceId(d.id));
      }
    } catch (_) {}
    return ids;
  }

  bool _isKnownDevice(String deviceId, Set<String> knownIds) =>
      knownIds.contains(_normDeviceId(deviceId));

  Future<void> _checkPendingDevices() async {
    final pending = await ApiService.getPendingDevices();
    if (pending.isEmpty || !mounted) return;

    final knownIds = await _knownDeviceNormIds();
    for (final entry in pending.entries) {
      final deviceId = entry.key;
      if (_isKnownDevice(deviceId, knownIds)) continue;
      final info = entry.value;
      if (info is! Map) continue;
      await _showPendingDeviceDialog(
        deviceId,
        info['name']?.toString() ?? deviceId,
        info['address']?.toString() ?? '',
      );
    }
  }

  void _handlePendingDevicesChanged(SyncthingEvent event) async {
    final added = event.data['added'];
    if (added is List) {
      final knownIds = await _knownDeviceNormIds();
      for (final item in added) {
        if (item is! Map) continue;
        final deviceId = item['deviceID']?.toString() ?? '';
        if (deviceId.isEmpty || _isKnownDevice(deviceId, knownIds)) continue;
        final name = item['name']?.toString() ?? '';
        final address = item['address']?.toString() ?? '';
        final displayName = (name.isNotEmpty && name != deviceId) ? name : '未知设备';
        _showSnack('收到新设备连接请求: $displayName');
        _showPendingDeviceDialog(deviceId, name, address);
      }
    } else {
      _checkPendingDevices();
    }
  }

  Future<void> _showPendingDeviceDialog(String deviceId, String name, String address) async {
    if (deviceId.isEmpty || _shownPendingDevices.contains(deviceId)) return;
    _shownPendingDevices.add(deviceId);

    if (!mounted) return;
    final displayName = (name.isNotEmpty && name != deviceId) ? name : '未知设备';

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('新设备请求连接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('设备 "$displayName" 请求与本机建立连接。'),
            const SizedBox(height: 12),
            Text('设备 ID', style: Theme.of(ctx).textTheme.labelMedium),
            SelectableText(deviceId, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('地址: $address', style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('拒绝')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('接受')),
        ],
      ),
    );

    if (!mounted) return;

    try {
      if (accepted == true) {
        await ApiService.acceptPendingDevice(deviceId: deviceId, name: displayName);
        if (mounted) {
          await context.read<DeviceProvider>().fetchDevices();
          _showSnack('已接受设备 $displayName', color: Colors.green);
        }
      } else {
        await ApiService.dismissPendingDevice(deviceId);
        if (mounted) _showSnack('已拒绝设备 $displayName');
      }
    } catch (e) {
      if (mounted) _showSnack('设备操作失败: $e', color: Colors.red);
    } finally {
      _shownPendingDevices.remove(deviceId);
    }
  }

  Future<bool> _isFolderConfiguredLocally(String folderId) async {
    try {
      final localId = await ApiService.getLocalDeviceId();
      final folders = await ApiService.getDeviceFolders(localId);
      return folders.any((f) => f.id == folderId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkPendingFolders() async {
    final pending = await ApiService.getPendingFolders();
    if (!mounted) return;

    debugPrint('[pending] 轮询: ${pending.length} 个待接受文件夹');
    if (pending.isEmpty) return;

    for (final entry in pending.entries) {
      final folderId = entry.key;
      if (await _isFolderConfiguredLocally(folderId)) {
        debugPrint('[pending] 文件夹 $folderId 已配置，跳过通知');
        continue;
      }
      final info = entry.value;
      if (info is! Map) continue;
      final offeredBy = info['offeredBy'];
      if (offeredBy is! Map) continue;
      for (final offer in offeredBy.entries) {
        final deviceId = offer.key.toString();
        final folderInfo = offer.value;
        var label = folderId;
        if (folderInfo is Map && folderInfo['label'] != null) {
          label = folderInfo['label'].toString();
        }
        await _showPendingFolderDialog(folderId: folderId, deviceId: deviceId, label: label);
      }
    }
  }

  void _handlePendingFoldersChanged(SyncthingEvent event) async {
    debugPrint('[pending] PendingFoldersChanged: ${event.data}');
    final removed = event.data['removed'];
    if (removed is List && removed.isNotEmpty && mounted) {
      try {
        final localId = await ApiService.getLocalDeviceId();
        await context.read<FolderProvider>().fetchDeviceFolders(localId, silent: true);
      } catch (_) {}
    }

    final added = event.data['added'];
    if (added is List) {
      for (final item in added) {
        if (item is! Map) continue;
        final folderId = item['folderID']?.toString() ?? '';
        final deviceId = item['deviceID']?.toString() ?? '';
        if (folderId.isEmpty || deviceId.isEmpty) continue;
        if (await _isFolderConfiguredLocally(folderId)) continue;
        final label = item['folderLabel']?.toString() ?? folderId;
        _showSnack('收到共享文件夹邀请: $label');
        _showPendingFolderDialog(folderId: folderId, deviceId: deviceId, label: label);
      }
    } else {
      _checkPendingFolders();
    }
  }

  Future<void> _showPendingFolderDialog({
    required String folderId,
    required String deviceId,
    required String label,
  }) async {
    final key = _pendingFolderKey(folderId, deviceId);
    if (_shownPendingFolders.contains(key)) return;
    _shownPendingFolders.add(key);

    if (!mounted) return;
    final deviceName = _deviceDisplayName(deviceId);
    final displayLabel = label.isNotEmpty ? label : folderId;

    final result = await showAcceptPendingFolderDialog(
      context: context,
      folderId: folderId,
      deviceName: deviceName,
      label: displayLabel,
    );

    if (!mounted) return;

    try {
      if (result?.accepted == true && result!.path != null) {
        final acceptResult = await ApiService.acceptPendingFolder(
          folderId: folderId,
          deviceId: deviceId,
          path: result.path,
        );
        if (mounted) {
          final localId = await ApiService.getLocalDeviceId();
          await context.read<FolderProvider>().fetchDeviceFolders(localId, silent: true);
          final msg = acceptResult['message']?.toString() ?? '已接受共享文件夹';
          _showSnack(msg, color: Colors.green);
        }
      } else if (result?.accepted == false) {
        await ApiService.dismissPendingFolder(folderId: folderId, deviceId: deviceId);
        if (mounted) _showSnack('已忽略共享文件夹 $displayLabel');
      }
    } catch (e) {
      if (mounted) _showSnack('共享文件夹操作失败: $e', color: Colors.red);
    } finally {
      _shownPendingFolders.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
