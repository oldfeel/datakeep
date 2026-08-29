import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../../../core/models/device.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/discovered_devices_store.dart';
import 'device_detail_screen.dart';
import 'qr_scanner_screen.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    
    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        title: const Text('设备管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              DevicesScreen.showAddDeviceDialog(context);
            },
            tooltip: '添加设备',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<DeviceProvider>().fetchDevices();
            },
          ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, deviceProvider, child) {
          if (deviceProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (deviceProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '加载失败',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    deviceProvider.error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      deviceProvider.clearError();
                      deviceProvider.fetchDevices();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          // 桌面端使用网格布局，移动端使用列表布局
          if (isDesktop) {
            return _buildDesktopLayout(context, deviceProvider);
          } else {
            return _buildMobileLayout(context, deviceProvider);
          }
        },
      ),
    );
  }

  // 桌面端网格布局
  Widget _buildDesktopLayout(BuildContext context, DeviceProvider deviceProvider) {
    return Column(
      children: [
        // 桌面端标题栏
        Container(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                '设备管理',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  DevicesScreen.showAddDeviceDialog(context);
                },
                icon: const Icon(Icons.add),
                label: const Text('添加设备'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  context.read<DeviceProvider>().fetchDevices();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        // 网格布局
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.5,
            ),
            itemCount: deviceProvider.devices.length,
            itemBuilder: (context, index) {
              final device = deviceProvider.devices[index];
              return _buildDesktopDeviceCard(context, device);
            },
          ),
        ),
      ],
    );
  }

  // 移动端列表布局
  Widget _buildMobileLayout(BuildContext context, DeviceProvider deviceProvider) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: deviceProvider.devices.length,
      itemBuilder: (context, index) {
        final device = deviceProvider.devices[index];
        return _buildMobileDeviceCard(context, device);
      },
    );
  }

  // 桌面端设备卡片
  Widget _buildDesktopDeviceCard(BuildContext context, Device device) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DeviceDetailScreen(deviceId: device.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部：图标和名称
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getDeviceTypeColor(device.type),
                    radius: 24,
                    child: Icon(
                      _getDeviceTypeIcon(device.type),
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              device.displayName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (device.isLocal) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '本地',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '类型: ${_getDeviceTypeName(device.type)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // 状态信息
              Row(
                children: [
                  Icon(
                    _getStatusIcon(device.status),
                    size: 20,
                    color: _getStatusColor(device.status),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getStatusText(device.status),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _getStatusColor(device.status),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '版本: ${device.version}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 其他信息
              Text(
                '最后在线: ${device.lastSeen != null ? _formatDateTime(device.lastSeen!) : '未知'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (device.folders.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '同步文件夹: ${device.folders.length} 个',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 移动端设备卡片
  Widget _buildMobileDeviceCard(BuildContext context, Device device) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getDeviceTypeColor(device.type),
          child: Icon(
            _getDeviceTypeIcon(device.type),
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Text(
              device.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (device.isLocal) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '本地',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '类型: ${_getDeviceTypeName(device.type)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  _getStatusIcon(device.status),
                  size: 16,
                  color: _getStatusColor(device.status),
                ),
                const SizedBox(width: 4),
                Text(
                  _getStatusText(device.status),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                Text(
                  '版本: ${device.version}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '最后在线: ${device.lastSeen != null ? _formatDateTime(device.lastSeen!) : '未知'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (device.folders.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '同步文件夹: ${device.folders.length} 个',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DeviceDetailScreen(deviceId: device.id),
            ),
          );
        },
      ),
    );
  }

  Color _getDeviceTypeColor(String type) {
    switch (type) {
      case 'desktop':
        return Colors.blue;
      case 'mobile':
        return Colors.green;
      case 'server':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getDeviceTypeIcon(String type) {
    switch (type) {
      case 'desktop':
        return Icons.desktop_windows;
      case 'mobile':
        return Icons.phone_android;
      case 'server':
        return Icons.dns;
      default:
        return Icons.devices;
    }
  }

  String _getDeviceTypeName(String type) {
    switch (type) {
      case 'desktop':
        return '桌面设备';
      case 'mobile':
        return '移动设备';
      case 'server':
        return '服务器';
      default:
        return '未知设备';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'offline':
        return Colors.grey;
      case 'syncing':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'online':
        return Icons.circle;
      case 'offline':
        return Icons.circle_outlined;
      case 'syncing':
        return Icons.sync;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'online':
        return '在线';
      case 'offline':
        return '离线';
      case 'syncing':
        return '同步中';
      default:
        return '未知状态';
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} 天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} 小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} 分钟前';
    } else {
      return '刚刚';
    }
  }

  static void showAddDeviceDialog(BuildContext context) {
    final deviceProvider = context.read<DeviceProvider>();
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    showDialog(
      context: context,
      builder: (dialogContext) => _AddDeviceDialog(
        deviceProvider: deviceProvider,
        isMobile: isMobile,
      ),
    );
  }
}

// 添加设备对话框组件
class _AddDeviceDialog extends StatefulWidget {
  final DeviceProvider deviceProvider;
  final bool isMobile;

  const _AddDeviceDialog({
    required this.deviceProvider,
    required this.isMobile,
  });

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
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDiscoveredDevices();
    });
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
      // 先刷新已配置设备，避免列表未加载时误判「未发现设备」
      await widget.deviceProvider.fetchDevices(silent: true);
      // Syncthing 局域网通告约 30s 一轮；冷启动需更长等待
      final devices = await ApiService.getDiscoveredDevices(
        retries: 20,
        interval: const Duration(seconds: 3),
        onUpdate: (partial) {
          if (!mounted || partial.isEmpty) return;
          setState(() {
            _discoveredDevices = partial;
            if (!_manualInput) {
              final available = _availableDevices();
              if (available.isNotEmpty) {
                _selectedDeviceId = available.first['id'];
                _applySelectedDevice(available.first);
                _validate(_selectedDeviceId!);
              }
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _discoveredDevices = devices;
        _isLoadingDiscovery = false;
        if (devices.isEmpty) {
          _manualInput = true;
        } else if (!_manualInput) {
          final available = _availableDevices();
          if (available.isNotEmpty) {
            _selectedDeviceId = available.first['id'];
            _applySelectedDevice(available.first);
            _validate(_selectedDeviceId!);
          } else {
            _manualInput = true;
          }
        }
      });
    } catch (e) {
      debugPrint('加载发现的设备失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingDiscovery = false;
          _manualInput = true;
        });
      }
    }
  }

  List<Map<String, String>> _availableDevices() {
    final existing = widget.deviceProvider.devices
        .where((d) => !d.isLocal)
        .map((d) => d.id.replaceAll(RegExp(r'[\s-]'), ''))
        .toSet();
    final ignored = context.read<DiscoveredDevicesStore>().ignoredNormIds;
    return _discoveredDevices.where((d) {
      final clean = d['id']!.replaceAll(RegExp(r'[\s-]'), '');
      return !existing.contains(clean) && !ignored.contains(clean);
    }).toList();
  }

  String _discoveryStatusText(List<Map<String, String>> available) {
    if (_discoveredDevices.isEmpty) {
      return '未发现设备：请确认对方已启动数据管理且在同一 WiFi';
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
    final existingIds = widget.deviceProvider.devices
        .map((d) => d.id.replaceAll(RegExp(r'[\s-]'), ''))
        .toSet();
    final clean = raw.replaceAll(RegExp(r'[\s-]'), '');
    if (clean.isEmpty) {
      setState(() => _idError = null);
      return;
    }
    if (clean.length != 56) {
      setState(() => _idError = '设备 ID 长度必须为 56 位');
      return;
    }
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(clean)) {
      setState(() => _idError = '设备 ID 只能包含大写字母和数字');
      return;
    }
    if (existingIds.contains(clean)) {
      setState(() => _idError = '该设备已存在');
      return;
    }
    setState(() => _idError = null);
  }

  Future<void> _scanQrCode() async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QRScannerScreen(onScanResult: null)),
    );
    if (scannedValue != null && scannedValue.isNotEmpty && mounted) {
      setState(() {
        _manualInput = true;
        _manualIdController.text = scannedValue;
      });
      _validate(scannedValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('扫描成功: ${scannedValue.length} 个字符'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildDeviceIdField() {
    final available = _availableDevices();

    if (_isLoadingDiscovery) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: '局域网设备',
          border: OutlineInputBorder(),
          helperText: '正在扫描局域网设备（首次启动可能需约 1 分钟）...',
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              '扫描中...',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
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
                  // 选中后只显示设备名称，不显示完整 ID
                  selectedItemBuilder: (context) => available.map((d) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _deviceLabel(d),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
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
              if (widget.isMobile)
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: '扫描二维码',
                  onPressed: _scanQrCode,
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
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新扫描',
                  onPressed: _loadDiscoveredDevices,
                ),
                if (widget.isMobile)
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: '扫描二维码',
                    onPressed: _scanQrCode,
                  ),
              ],
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
    final canSubmit = _idError == null && (_effectiveDeviceId?.isNotEmpty ?? false);

    return AlertDialog(
      title: const Text('添加设备'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDeviceIdField(),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '设备名称',
                hintText: '请输入设备名称（可选）',
                border: OutlineInputBorder(),
                helperText: '留空则使用设备通告的名称',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: (canSubmit && !_isSubmitting)
              ? () async {
                  final deviceId = _effectiveDeviceId!;
                  setState(() => _isSubmitting = true);
                  try {
                    await widget.deviceProvider.addDevice(
                      deviceID: deviceId,
                      name: _nameController.text,
                    );
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            '已添加到本机。请确认对方设备也添加了本机，才能建立连接。',
                          ),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 5),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('添加设备失败: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isSubmitting = false);
                  }
                }
              : null,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('添加'),
        ),
      ],
    );
  }
}
