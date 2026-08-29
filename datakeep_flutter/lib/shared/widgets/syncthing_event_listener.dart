import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/event_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/app_notification_store.dart';
import '../../core/services/discovered_devices_store.dart';
import '../../core/models/app_notification.dart';
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
  final Set<String> _shownPendingFolders = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDiscovery();
      _checkPendingFolders();
    });
    EventService().start();
    _eventSub = EventService().events.listen(_onEvent);
    debugPrint('[pending] SyncthingEventListener 已启动');
    _pendingPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _refreshDiscovery();
        _checkPendingFolders();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshDiscovery();
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

  void _notify(
    AppNotificationCategory category,
    String title, {
    Color? snackColor,
  }) {
    if (!mounted) return;
    context.read<AppNotificationStore>().add(category: category, title: title);
    if (snackColor != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(title),
          backgroundColor: snackColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _onEvent(SyncthingEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'DeviceDiscovered':
      case 'PendingDevicesChanged':
        context.read<DiscoveredDevicesStore>().ingestEvent(event);
        break;
      case 'PendingFoldersChanged':
        _handlePendingFoldersChanged(event);
        break;
      case 'DeviceConnected':
        context.read<DeviceProvider>().fetchDevices(silent: true);
        _notify(
          AppNotificationCategory.device,
          '设备 ${event.data['id'] ?? ''} 已连接',
        );
        break;
      case 'DeviceDisconnected':
        context.read<DeviceProvider>().fetchDevices(silent: true);
        _refreshDiscovery();
        _notify(
          AppNotificationCategory.device,
          '设备 ${event.data['id'] ?? ''} 已断开',
        );
        break;
      case 'ItemFinished':
        context.read<AppNotificationStore>().noteItemFinished();
        break;
      case 'FolderErrors':
        _notify(
          AppNotificationCategory.sync,
          '文件夹 ${event.data['folder'] ?? ''} 出现错误',
          snackColor: Colors.red,
        );
        break;
      case 'ConfigSaved':
        _notify(AppNotificationCategory.system, '配置已保存');
        _refreshFoldersAfterSyncthingReady();
        _refreshDiscovery();
        break;
      case 'StartupComplete':
      case 'FolderSummary':
      case 'FolderCompletion':
      case 'StateChanged':
        _refreshFoldersAfterSyncthingReady();
        break;
    }
  }

  DateTime? _lastFolderRefreshAt;

  /// Syncthing 启动完成或文件夹状态变化后刷新列表（节流）
  void _refreshFoldersAfterSyncthingReady() {
    final now = DateTime.now();
    if (_lastFolderRefreshAt != null &&
        now.difference(_lastFolderRefreshAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastFolderRefreshAt = now;
    if (!mounted) return;
    final folderProvider = context.read<FolderProvider>();
    final deviceId = folderProvider.loadedDeviceId;
    final known = deviceId != null &&
        context.read<DeviceProvider>().devices.any((d) => d.id == deviceId);
    if (known) {
      folderProvider.fetchDeviceFolders(deviceId, silent: true);
    } else {
      folderProvider.cancelRetries();
      folderProvider.fetchFolders(silent: true);
    }
    context.read<DeviceProvider>().fetchDevices(silent: true);
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

  Future<void> _refreshDiscovery() async {
    if (!mounted) return;
    await context.read<DiscoveredDevicesStore>().refresh();
  }

  /// 本机是否已有该 folderId（仅用于提示文案；不因已存在而跳过邀请）
  Future<String?> _localFolderPathIfAny(String folderId) async {
    try {
      final localId = await ApiService.getLocalDeviceId();
      final folders = await ApiService.getDeviceFolders(localId);
      for (final f in folders) {
        if (f.id == folderId) return f.path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _checkPendingFolders() async {
    final pending = await ApiService.getPendingFolders();
    if (!mounted) return;

    debugPrint('[pending] 轮询: ${pending.length} 个待接受文件夹');
    if (pending.isEmpty) return;

    for (final entry in pending.entries) {
      final folderId = entry.key;
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
        // Syncthing 仍放在 pending 即表示尚未与对端完成共享（即使本机已有同 id 的 Default Folder）
        final existingPath = await _localFolderPathIfAny(folderId);
        if (existingPath != null) {
          debugPrint('[pending] 文件夹 $folderId 本机已有，仍需确认加入对端设备');
        }
        await _showPendingFolderDialog(
          folderId: folderId,
          deviceId: deviceId,
          label: label,
          existingPath: existingPath,
        );
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
        final label = item['folderLabel']?.toString() ?? folderId;
        final existingPath = await _localFolderPathIfAny(folderId);
        _notify(
          AppNotificationCategory.device,
          existingPath != null
              ? '收到共享邀请（本机已有同名文件夹）: $label'
              : '收到共享文件夹邀请: $label',
        );
        _showPendingFolderDialog(
          folderId: folderId,
          deviceId: deviceId,
          label: label,
          existingPath: existingPath,
        );
      }
    } else {
      _checkPendingFolders();
    }
  }

  Future<void> _showPendingFolderDialog({
    required String folderId,
    required String deviceId,
    required String label,
    String? existingPath,
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
      existingPath: existingPath,
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
          _notify(
            AppNotificationCategory.device,
            msg,
            snackColor: Colors.green,
          );
        }
      } else if (result?.accepted == false) {
        await ApiService.dismissPendingFolder(folderId: folderId, deviceId: deviceId);
        if (mounted) {
          _notify(
            AppNotificationCategory.device,
            '已忽略共享文件夹 $displayLabel',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _notify(
          AppNotificationCategory.device,
          '共享文件夹操作失败: $e',
          snackColor: Colors.red,
        );
      }
    } finally {
      _shownPendingFolders.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
