import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../features/devices/providers/device_provider.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/event_service.dart';
import 'device_detail_page.dart';
import 'folder_detail_page.dart';
import 'file_preview_page.dart';
import '../../shared/widgets/accept_pending_folder_dialog.dart';
import '../../shared/utils/open_syncthing_gui.dart';
import '../../shared/widgets/folder_edit_dialog.dart';
import '../../shared/constants/app_info.dart';
import '../../shared/widgets/app_logo.dart';
import '../../features/apps/screens/market_screen.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({super.key});

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

enum DesktopPage { home, deviceDetail, folderDetail, filePreview }

class _DesktopHomePageState extends State<DesktopHomePage> {
  DesktopPage _currentPage = DesktopPage.home;
  Device? _selectedDevice;
  Folder? _selectedFolder;
  /// 文件夹内当前浏览的相对路径（如 `照片`），预览返回后用于恢复
  String _folderBrowsePath = '';
  String? _previewFilePath;
  String _searchText = '';
  String _wifiName = '';
  int _notificationCount = 0;
  final List<_NotificationItem> _notifications = [];
  final Set<String> _shownPendingDevices = {};
  final Set<String> _shownPendingFolders = {};

  StreamSubscription<SyncthingEvent>? _eventSub;
  int _itemFinishedBurst = 0;
  Timer? _itemFinishedFlushTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().fetchDevices();
      context.read<FolderProvider>().fetchFolders();
      _fetchWifiInfo();
      _checkPendingDevices();
      _checkPendingFolders();
    });
    _eventSub = EventService().events.listen((event) {
      if (!mounted) return;
      String message;
      Color bgColor;
      switch (event.type) {
        case 'DeviceConnected':
          message = '设备 ${event.data['id'] ?? ''} 已连接';
          bgColor = Colors.green;
          context.read<DeviceProvider>().fetchDevices();
          break;
        case 'DeviceDisconnected':
          message = '设备 ${event.data['id'] ?? ''} 已断开';
          bgColor = Colors.orange;
          context.read<DeviceProvider>().fetchDevices();
          break;
        case 'PendingDevicesChanged':
          _handlePendingDevicesChanged(event);
          return;
        case 'PendingFoldersChanged':
          _handlePendingFoldersChanged(event);
          return;
        case 'StartupComplete':
        case 'FolderSummary':
        case 'FolderCompletion':
        case 'StateChanged':
          context.read<FolderProvider>().fetchFolders(silent: true);
          context.read<DeviceProvider>().fetchDevices(silent: true);
          return;
        case 'ItemFinished':
          // 大批量同步时每个文件都会触发，合并提示避免刷屏
          _itemFinishedBurst++;
          _itemFinishedFlushTimer?.cancel();
          _itemFinishedFlushTimer = Timer(const Duration(seconds: 2), () {
            if (!mounted) return;
            final n = _itemFinishedBurst;
            _itemFinishedBurst = 0;
            if (n <= 0) return;
            _addNotification(
              n == 1 ? '文件同步完成' : '已同步 $n 个文件',
              snackColor: Colors.green,
            );
          });
          return;
        case 'FolderErrors':
          message = '文件夹 ${event.data['folder'] ?? ''} 出现错误';
          bgColor = Colors.red;
          break;
        case 'ConfigSaved':
          message = '配置已保存';
          bgColor = Colors.blue;
          context.read<DeviceProvider>().fetchDevices(silent: true);
          context.read<FolderProvider>().fetchFolders(silent: true);
          return;
        default:
          return;
      }
      _addNotification(message, snackColor: bgColor);
    });
    EventService().start();
  }

  void _addNotification(String message, {Color? snackColor}) {
    if (!mounted) return;
    setState(() {
      _notificationCount++;
      _notifications.insert(0, _NotificationItem(message: message, time: DateTime.now()));
    });
    if (snackColor != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: snackColor, duration: const Duration(seconds: 3)),
      );
    }
  }

  Future<void> _fetchWifiInfo() async {
    try {
      final info = await ApiService.getWifiInfo();
      if (mounted) {
        setState(() {
          _wifiName = info['wifiName']?.toString() ?? '';
        });
      }
    } catch (_) {}
  }

  /// 检查 Syncthing 待确认设备（未知设备尝试连接时）
  Future<void> _checkPendingDevices() async {
    final pending = await ApiService.getPendingDevices();
    if (pending.isEmpty) return;

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

  Future<Set<String>> _knownDeviceNormIds() async {
    final ids = <String>{};
    try {
      for (final d in await ApiService.getDevices()) {
        ids.add(_normDeviceId(d.id));
      }
    } catch (_) {}
    return ids;
  }

  String _normDeviceId(String id) =>
      id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  bool _isKnownDevice(String deviceId, Set<String> knownIds) =>
      knownIds.contains(_normDeviceId(deviceId));

  void _handlePendingDevicesChanged(SyncthingEvent event) async {
    final added = event.data['added'];
    if (added is List) {
      final knownIds = await _knownDeviceNormIds();
      for (final item in added) {
        if (item is Map) {
          final deviceId = item['deviceID']?.toString() ?? '';
          if (deviceId.isEmpty || _isKnownDevice(deviceId, knownIds)) continue;
          final name = item['name']?.toString() ?? '';
          final address = item['address']?.toString() ?? '';
          final displayName = (name.isNotEmpty && name != deviceId) ? name : '未知设备';
          _addNotification('收到新设备连接请求: $displayName');
          _showPendingDeviceDialog(deviceId, name, address);
        }
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('忽略'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('接受'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    try {
      if (accepted == true) {
        await ApiService.acceptPendingDevice(deviceId: deviceId, name: displayName);
        if (mounted) {
          await context.read<DeviceProvider>().fetchDevices();
          _addNotification(
            '已接受设备 $displayName',
            snackColor: Colors.green,
          );
        }
      } else {
        await ApiService.dismissPendingDevice(
          deviceId,
          ignore: true,
          name: displayName,
          address: address,
        );
        if (mounted) {
          _addNotification('已忽略设备 $displayName');
        }
      }
    } catch (e) {
      if (mounted) {
        _addNotification('设备操作失败: $e', snackColor: Colors.red);
      }
    } finally {
      _shownPendingDevices.remove(deviceId);
    }
  }

  String _pendingFolderKey(String folderId, String deviceId) =>
      '${_normDeviceId(folderId)}|${_normDeviceId(deviceId)}';

  Future<void> _checkPendingFolders() async {
    final pending = await ApiService.getPendingFolders();
    if (pending.isEmpty) return;

    for (final entry in pending.entries) {
      final folderId = entry.key;
      final info = entry.value;
      if (info is! Map) continue;
      final offeredBy = info['offeredBy'];
      if (offeredBy is! Map) continue;
      for (final offer in offeredBy.entries) {
        final deviceId = offer.key.toString();
        var label = folderId;
        final folderInfo = offer.value;
        if (folderInfo is Map && folderInfo['label'] != null) {
          label = folderInfo['label'].toString();
        }
        await _showPendingFolderDialog(folderId: folderId, deviceId: deviceId, label: label);
      }
    }
  }

  void _handlePendingFoldersChanged(SyncthingEvent event) async {
    final removed = event.data['removed'];
    if (removed is List && removed.isNotEmpty && mounted) {
      await context.read<FolderProvider>().fetchFolders(silent: true);
    }

    final added = event.data['added'];
    if (added is List) {
      for (final item in added) {
        if (item is! Map) continue;
        final folderId = item['folderID']?.toString() ?? '';
        final deviceId = item['deviceID']?.toString() ?? '';
        if (folderId.isEmpty || deviceId.isEmpty) continue;
        final label = item['folderLabel']?.toString() ?? folderId;
        _addNotification('收到共享文件夹邀请: $label');
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
    final displayLabel = label.isNotEmpty ? label : folderId;
    String deviceName = deviceId;
    try {
      for (final d in await ApiService.getDevices()) {
        if (_normDeviceId(d.id) == _normDeviceId(deviceId)) {
          deviceName = d.displayName;
          break;
        }
      }
    } catch (_) {}

    final accepted = await showAcceptPendingFolderDialog(
      context: context,
      folderId: folderId,
      deviceName: deviceName,
      label: displayLabel,
    );

    if (!mounted) return;

    try {
      if (accepted?.accepted == true && accepted!.path != null) {
        await ApiService.acceptPendingFolder(
          folderId: folderId,
          deviceId: deviceId,
          path: accepted.path,
        );
        if (mounted) {
          await context.read<FolderProvider>().fetchFolders();
          _addNotification('已接受共享文件夹 $displayLabel', snackColor: Colors.green);
        }
      } else if (accepted?.accepted == false) {
        await ApiService.dismissPendingFolder(folderId: folderId, deviceId: deviceId);
        if (mounted) _addNotification('已忽略共享文件夹 $displayLabel');
      }
    } catch (e) {
      if (mounted) _addNotification('共享文件夹操作失败: $e', snackColor: Colors.red);
    } finally {
      _shownPendingFolders.remove(key);
    }
  }

  @override
  void dispose() {
    _itemFinishedFlushTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  void _selectDevice(Device device) {
    setState(() {
      _selectedDevice = device;
      _selectedFolder = null;
      _folderBrowsePath = '';
      _previewFilePath = null;
      _currentPage = DesktopPage.deviceDetail;
    });
  }

  void _selectFolder(Folder folder) {
    setState(() {
      _selectedFolder = folder;
      _folderBrowsePath = '';
      _previewFilePath = null;
      _currentPage = DesktopPage.folderDetail;
    });
  }

  void _previewFile(String path) {
    setState(() {
      // 记住文件所在子目录，预览返回后恢复
      final slash = path.lastIndexOf('/');
      _folderBrowsePath = slash >= 0 ? path.substring(0, slash) : '';
      _previewFilePath = path;
      _currentPage = DesktopPage.filePreview;
    });
  }

  void _navigateHome() {
    setState(() {
      _currentPage = DesktopPage.home;
      _selectedDevice = null;
      _selectedFolder = null;
      _folderBrowsePath = '';
      _previewFilePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildContent(context)),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 280,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildSidebarHeader(context),
          const Divider(height: 1),
          Expanded(child: _buildDeviceList(context)),
          _buildSidebarFooter(context),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppLogo(size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  kAppDisplayName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: const Icon(Icons.notifications_outlined, size: 20),
                    tooltip: '通知历史',
                    onPressed: () => _showNotificationHistory(context),
                  ),
                  if (_notificationCount > 0)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$_notificationCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.qr_code_2, size: 20),
                tooltip: '本机配对二维码',
                onPressed: () async {
                  try {
                    final id = await ApiService.getLocalDeviceId();
                    if (!context.mounted) return;
                    await LocalDeviceQrDialog.show(
                      context,
                      deviceId: id,
                      deviceName: '本机设备',
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('获取本机 ID 失败: $e')),
                      );
                    }
                  }
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.storefront_outlined, size: 20),
                tooltip: '应用市场',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MarketScreen()),
                  );
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.open_in_browser, size: 20),
                tooltip: '打开 Syncthing 管理页（高级配置）',
                onPressed: () => openSyncthingGui(context),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '刷新',
                onPressed: () {
                  context.read<DeviceProvider>().fetchDevices();
                  _fetchWifiInfo();
                },
              ),
            ],
          ),
          if (_wifiName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Row(
                children: [
                  Icon(Icons.wifi, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(_wifiName, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.devices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (provider.error != null && provider.devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 8),
                Text(provider.error!, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                TextButton(onPressed: () => provider.fetchDevices(), child: const Text('重试')),
              ],
            ),
          );
        }

        // 启动后默认选中本机设备
        if (_selectedDevice == null && provider.devices.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _selectedDevice != null) return;
            final local = provider.devices.firstWhere(
              (d) => d.isLocal,
              orElse: () => provider.devices.first,
            );
            _selectDevice(local);
          });
        }

        final devices = _searchText.isEmpty
            ? provider.devices
            : provider.devices.where((d) =>
                d.name.toLowerCase().contains(_searchText.toLowerCase()) ||
                d.id.toLowerCase().contains(_searchText.toLowerCase())).toList();

        return Column(
          children: [
            if (devices.isEmpty && _searchText.isNotEmpty)
              Expanded(child: Center(child: Text('未找到 "$_searchText"')))
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: devices.length + 1,
                  itemBuilder: (context, index) {
                    if (index == devices.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: OutlinedButton.icon(
                          onPressed: () => _showAddDeviceDialog(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加设备'),
                        ),
                      );
                    }
                    final device = devices[index];
                    final isSelected = _selectedDevice?.id == device.id;
                    return _buildDeviceTile(context, device, isSelected);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceTile(BuildContext context, Device device, bool isSelected) {
    final isLocal = device.isLocal;
    final bgColor = isSelected ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          dense: true,
          selected: isSelected,
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: isLocal
                ? Theme.of(context).colorScheme.primary
                : (device.connected ? Colors.green : Colors.grey),
            child: Icon(
              isLocal ? Icons.computer : (device.connected ? Icons.phone_android : Icons.devices),
              size: 16,
              color: Colors.white,
            ),
          ),
          title: Text(
            device.displayName,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            isLocal ? '本机设备' : (device.connected ? '在线' : '离线'),
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          onTap: () => _selectDevice(device),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '${context.watch<DeviceProvider>().devices.length} 个设备',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_currentPage) {
      case DesktopPage.home:
        return _buildWelcomePage(context);
      case DesktopPage.deviceDetail:
        if (_selectedDevice == null) return _buildWelcomePage(context);
        return DeviceDetailPage(
          key: ValueKey(_selectedDevice!.id),
          device: _selectedDevice!,
          onFolderTap: _selectFolder,
          onBack: _navigateHome,
        );
      case DesktopPage.folderDetail:
        if (_selectedDevice == null || _selectedFolder == null) {
          return _buildWelcomePage(context);
        }
        return FolderDetailPage(
          key: ValueKey('${_selectedDevice!.id}/${_selectedFolder!.id}/$_folderBrowsePath'),
          device: _selectedDevice!,
          folder: _selectedFolder!,
          initialPath: _folderBrowsePath,
          onFileTap: _previewFile,
          onPathChanged: (path) {
            _folderBrowsePath = path;
          },
          onBack: () => _selectDevice(_selectedDevice!),
        );
      case DesktopPage.filePreview:
        if (_selectedDevice == null || _selectedFolder == null || _previewFilePath == null) {
          return _buildWelcomePage(context);
        }
        return FilePreviewPage(
          device: _selectedDevice!,
          folder: _selectedFolder!,
          filePath: _previewFilePath!,
          onBack: () => setState(() {
            _currentPage = DesktopPage.folderDetail;
            _previewFilePath = null;
          }),
        );
    }
  }

  Widget _buildWelcomePage(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppBrandLogo(height: 96),
          const SizedBox(height: 24),
          Text(kAppDisplayName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 8),
          Text(
            '请从左侧选择一个设备',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _showNotificationHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Text('通知历史'),
            const Spacer(),
            if (_notifications.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    _notifications.clear();
                    _notificationCount = 0;
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('清空'),
              ),
          ],
        ),
        content: SizedBox(
          width: 500,
          height: 400,
          child: _notifications.isEmpty
              ? const Center(child: Text('暂无通知'))
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (_, i) {
                    final n = _notifications[i];
                    return ListTile(
                      dense: true,
                      title: Text(n.message, style: const TextStyle(fontSize: 14)),
                      trailing: Text(
                        '${n.time.hour}:${n.time.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭'))],
      ),
    );
  }

  void _showAddDeviceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const _AddDeviceDialog(),
    );
  }
}

class _NotificationItem {
  final String message;
  final DateTime time;
  _NotificationItem({required this.message, required this.time});
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog();

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _nameController = TextEditingController();
  final _manualIdController = TextEditingController();
  String? _selectedDeviceId;
  String? _idError;
  List<Map<String, String>> _discoveredDevices = [];
  bool _isLoadingDiscovery = true;
  bool _manualInput = false;

  @override
  void initState() {
    super.initState();
    _loadDiscoveredDevices();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _manualIdController.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoveredDevices() async {
    setState(() {
      _isLoadingDiscovery = true;
      _idError = null;
    });
    try {
      final provider = context.read<DeviceProvider>();
      await provider.fetchDevices();
      // 多次重试扫描局域网（Syncthing 本地发现需要几秒）
      final devices = await ApiService.getDiscoveredDevices(
        retries: 5,
        interval: const Duration(seconds: 3),
      );
      if (!mounted) return;
      setState(() {
        _discoveredDevices = devices;
        _isLoadingDiscovery = false;
        if (devices.isEmpty) {
          _manualInput = true;
        } else if (!_manualInput) {
          _selectedDeviceId = devices.first['id'];
          _applySelectedDevice(devices.first);
          _validate(_selectedDeviceId!);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingDiscovery = false;
          _manualInput = true;
        });
      }
    }
  }

  List<Map<String, String>> _availableDevices(DeviceProvider provider) {
    final existing = provider.devices
        .where((d) => !d.isLocal)
        .map((d) => d.id.replaceAll(RegExp(r'[\s-]'), ''))
        .toSet();
    return _discoveredDevices.where((d) {
      final clean = d['id']!.replaceAll(RegExp(r'[\s-]'), '');
      return !existing.contains(clean);
    }).toList();
  }

  String _discoveryStatusText(List<Map<String, String>> available) {
    if (_discoveredDevices.isEmpty) {
      return '未发现设备：请确认对方已启动文件管理且在同一 WiFi';
    }
    if (available.isEmpty) {
      return '已发现 ${_discoveredDevices.length} 个设备，均已添加';
    }
    return '手动输入模式';
  }

  void _applySelectedDevice(Map<String, String> device) {
    final id = device['id']!;
    final name = device['name']!;
    if (name != id && !name.contains('-')) {
      _nameController.text = name;
    }
  }

  String _deviceLabel(Map<String, String> device) {
    final id = device['id']!;
    final name = device['name']?.trim() ?? '';
    if (name.isNotEmpty && name != id && !name.contains('-')) return name;
    return id;
  }

  String? get _effectiveDeviceId =>
      _manualInput ? _manualIdController.text.trim() : _selectedDeviceId;

  void _validate(String raw) {
    final provider = context.read<DeviceProvider>();
    final existingIds = provider.devices.map((d) => d.id.replaceAll(RegExp(r'[\s-]'), '')).toSet();
    final clean = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (clean.isEmpty) { setState(() { _idError = null; }); return; }
    if (clean.length != 56) { setState(() { _idError = '设备 ID 长度必须为 56 位（8组，每组7个字符）'; }); return; }
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(clean)) { setState(() { _idError = '设备 ID 只能包含大写字母和数字'; }); return; }
    if (existingIds.contains(clean)) { setState(() { _idError = '该设备已存在'; }); return; }
    setState(() { _idError = null; });
  }

  Widget _buildDeviceIdField(DeviceProvider provider) {
    final available = _availableDevices(provider);

    if (_isLoadingDiscovery) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: '局域网设备',
          border: OutlineInputBorder(),
          helperText: '正在扫描局域网设备...',
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text('扫描中...', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    if (!_manualInput && available.isNotEmpty) {
      final currentId = available.any((d) => d['id'] == _selectedDeviceId)
          ? _selectedDeviceId!
          : available.first['id']!;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: currentId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '选择局域网设备',
                    border: const OutlineInputBorder(),
                    helperText: '已发现 ${available.length} 个设备',
                    errorText: _idError,
                  ),
                  items: available.map((d) {
                    final id = d['id']!;
                    return DropdownMenuItem(
                      value: id,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _deviceLabel(d),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (d['name'] != id)
                            Text(
                              id,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final device = available.firstWhere((d) => d['id'] == value);
                    setState(() {
                      _selectedDeviceId = value;
                      _applySelectedDevice(device);
                      _validate(value);
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新扫描',
                onPressed: _loadDiscoveredDevices,
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => setState(() => _manualInput = true),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('手动输入设备 ID'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _manualIdController,
          decoration: InputDecoration(
            labelText: '设备 ID',
            border: const OutlineInputBorder(),
            hintText: '请输入 56 位设备 ID',
            helperText: _discoveryStatusText(available),
            errorText: _idError,
            suffixIcon: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '重新扫描',
              onPressed: _loadDiscoveredDevices,
            ),
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          maxLength: 63,
          onChanged: _validate,
        ),
        if (available.isNotEmpty)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _manualInput = false;
                _selectedDeviceId = available.first['id'];
                _applySelectedDevice(available.first);
                _validate(_selectedDeviceId!);
              });
            },
            icon: const Icon(Icons.devices, size: 18),
            label: Text('从局域网设备列表选择（${available.length}）'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DeviceProvider>();
    final canSubmit = _idError == null && (_effectiveDeviceId?.isNotEmpty ?? false);

    return AlertDialog(
      title: const Text('添加设备'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDeviceIdField(provider),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '设备名称（可选）',
                  hintText: '如：我的手机',
                  border: OutlineInputBorder(),
                  helperText: '留空则使用设备通告的名称',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        ElevatedButton(
          onPressed: canSubmit
              ? () async {
                  final deviceId = _effectiveDeviceId!;
                  try {
                    await provider.addDevice(
                      deviceID: deviceId,
                      name: _nameController.text,
                    );
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已发送连接请求，等待对方确认接受'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                }
              : null,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
