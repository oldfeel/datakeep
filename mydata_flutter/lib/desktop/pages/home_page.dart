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
  String? _previewFilePath;
  String _searchText = '';
  String _wifiName = '';
  int _notificationCount = 0;
  final List<_NotificationItem> _notifications = [];

  StreamSubscription<SyncthingEvent>? _eventSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().fetchDevices();
      context.read<FolderProvider>().fetchFolders();
      _fetchWifiInfo();
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
        case 'ItemFinished':
          message = '文件同步完成: ${event.data['item'] ?? ''}';
          bgColor = Colors.green;
          break;
        case 'FolderErrors':
          message = '文件夹 ${event.data['folder'] ?? ''} 出现错误';
          bgColor = Colors.red;
          break;
        case 'ConfigSaved':
          message = '配置已保存';
          bgColor = Colors.blue;
          break;
        default:
          return;
      }
      setState(() {
        _notificationCount++;
        _notifications.insert(0, _NotificationItem(message: message, time: DateTime.now()));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: bgColor, duration: const Duration(seconds: 3)),
      );
    });
    EventService().start();
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

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _selectDevice(Device device) {
    setState(() {
      _selectedDevice = device;
      _selectedFolder = null;
      _previewFilePath = null;
      _currentPage = DesktopPage.deviceDetail;
    });
  }

  void _selectFolder(Folder folder) {
    setState(() {
      _selectedFolder = folder;
      _previewFilePath = null;
      _currentPage = DesktopPage.folderDetail;
    });
  }

  void _previewFile(String path) {
    setState(() {
      _previewFilePath = path;
      _currentPage = DesktopPage.filePreview;
    });
  }

  void _navigateHome() {
    setState(() {
      _currentPage = DesktopPage.home;
      _selectedDevice = null;
      _selectedFolder = null;
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
              Icon(Icons.sync, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text('MyData', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              )),
              const Spacer(),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, size: 20),
                    tooltip: '通知历史',
                    onPressed: () => _showNotificationHistory(context),
                  ),
                  if (_notificationCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$_notificationCount',
                          style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
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
            device.name,
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
          device: _selectedDevice!,
          onFolderTap: _selectFolder,
          onBack: _navigateHome,
        );
      case DesktopPage.folderDetail:
        if (_selectedDevice == null || _selectedFolder == null) {
          return _buildWelcomePage(context);
        }
        return FolderDetailPage(
          device: _selectedDevice!,
          folder: _selectedFolder!,
          onFileTap: _previewFile,
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
          Icon(Icons.sync, size: 80, color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
          const SizedBox(height: 24),
          Text('MyData', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String? _idError;
  List<String> _discoveredDevices = [];
  bool _isLoadingDiscovery = true;

  @override
  void initState() {
    super.initState();
    _loadDiscoveredDevices();
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadDiscoveredDevices() async {
    try {
      final devices = await ApiService.getDiscoveredDeviceIds();
      if (mounted) setState(() { _discoveredDevices = devices; _isLoadingDiscovery = false; });
    } catch (_) {
      if (mounted) setState(() { _isLoadingDiscovery = false; });
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DeviceProvider>();

    return AlertDialog(
      title: const Text('添加设备'),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Autocomplete<String>(
                optionsBuilder: (textEditingValue) {
                  if (textEditingValue.text.isEmpty) return _discoveredDevices;
                  return _discoveredDevices.where((d) =>
                      d.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                },
                onSelected: (selection) {
                  _idController.text = selection;
                  _validate(selection);
                },
                fieldViewBuilder: (_, textEditingController, focusNode, onSubmitted) {
                  return TextField(
                    controller: _idController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: '设备 ID',
                      hintText: '选择或输入设备 ID',
                      helperText: _discoveredDevices.isNotEmpty
                          ? '已发现 ${_discoveredDevices.length} 个设备，可下拉选择'
                          : '请输入 56 位设备 ID',
                      errorText: _idError,
                      suffixIcon: _isLoadingDiscovery
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                    maxLength: 63,
                    onChanged: _validate,
                  );
                },
              ),
              if (_discoveredDevices.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('附近的设备：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                ..._discoveredDevices.map((deviceId) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: OutlinedButton(
                    onPressed: () {
                      _idController.text = deviceId;
                      _validate(deviceId);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: const Size(0, 32),
                      textStyle: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    child: Text(deviceId, overflow: TextOverflow.ellipsis),
                  ),
                )),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '设备名称（可选）',
                  hintText: '如：我的手机',
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
          onPressed: _idError == null && _idController.text.isNotEmpty
              ? () async {
                  try {
                    await provider.addDevice(
                      deviceID: _idController.text,
                      name: _nameController.text,
                    );
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('设备添加成功'), backgroundColor: Colors.green),
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
