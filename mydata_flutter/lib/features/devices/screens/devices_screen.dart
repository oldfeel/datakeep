import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../../../core/models/device.dart';
import '../../../core/services/api_service.dart';
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
                              device.name,
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
              device.name,
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
    final deviceIdController = TextEditingController();
    final nameController = TextEditingController();
    final deviceProvider = context.read<DeviceProvider>();
    
    // 检查是否为移动平台（Android/iOS）
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    showDialog(
      context: context,
      builder: (dialogContext) => _AddDeviceDialog(
        deviceIdController: deviceIdController,
        nameController: nameController,
        deviceProvider: deviceProvider,
        isMobile: isMobile,
      ),
    );
  }
}

// 添加设备对话框组件
class _AddDeviceDialog extends StatefulWidget {
  final TextEditingController deviceIdController;
  final TextEditingController nameController;
  final DeviceProvider deviceProvider;
  final bool isMobile;

  const _AddDeviceDialog({
    required this.deviceIdController,
    required this.nameController,
    required this.deviceProvider,
    required this.isMobile,
  });

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  List<Map<String, String>> _discoveredDevices = []; // 改为存储带名称的设备列表
  bool _isLoadingDiscovery = true;

  @override
  void initState() {
    super.initState();
    _loadDiscoveredDevices();
  }

  Future<void> _loadDiscoveredDevices() async {
    try {
      final devices = await ApiService.getDiscoveredDevices();
      if (mounted) {
        setState(() {
          _discoveredDevices = devices;
          _isLoadingDiscovery = false;
        });
      }
    } catch (e) {
      debugPrint('加载发现的设备失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingDiscovery = false;
        });
      }
    }
  }
  
  // 获取设备ID列表（用于 Autocomplete）
  List<String> get _discoveredDeviceIds => _discoveredDevices.map((d) => d['id']!).toList();
  
  // 获取设备显示名称（名称 + ID）
  String _getDeviceDisplayName(String deviceId) {
    final device = _discoveredDevices.firstWhere(
      (d) => d['id'] == deviceId,
      orElse: () => {'id': deviceId, 'name': deviceId},
    );
    final name = device['name']!;
    final id = device['id']!;
    // 如果名称就是ID，只显示ID；否则显示 "名称 (ID)"
    if (name == id) {
      return id;
    } else {
      return '$name ($id)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加设备'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 设备 ID 下拉选择框（支持手动输入）
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return _discoveredDeviceIds;
                }
                // 过滤匹配的设备（支持按名称或ID搜索）
                return _discoveredDeviceIds.where((deviceId) {
                  final displayName = _getDeviceDisplayName(deviceId);
                  final searchText = textEditingValue.text.toLowerCase();
                  return deviceId.toLowerCase().contains(searchText) ||
                         displayName.toLowerCase().contains(searchText);
                }).toList();
              },
              onSelected: (String selection) {
                // 选择时只设置设备ID（移除可能的显示名称部分）
                widget.deviceIdController.text = selection;
              },
              displayStringForOption: (String deviceId) {
                return _getDeviceDisplayName(deviceId);
              },
              fieldViewBuilder: (
                BuildContext context,
                TextEditingController textEditingController,
                FocusNode focusNode,
                VoidCallback onFieldSubmitted,
              ) {
                // 同步 controller
                if (widget.deviceIdController.text != textEditingController.text) {
                  textEditingController.text = widget.deviceIdController.text;
                }
                widget.deviceIdController.addListener(() {
                  if (textEditingController.text != widget.deviceIdController.text) {
                    textEditingController.text = widget.deviceIdController.text;
                  }
                });
                textEditingController.addListener(() {
                  if (widget.deviceIdController.text != textEditingController.text) {
                    widget.deviceIdController.text = textEditingController.text;
                  }
                });

                return TextField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: '设备 ID',
                    hintText: _discoveredDeviceIds.isEmpty
                        ? '请输入设备 ID（52-56位字符）'
                        : '选择或输入设备 ID',
                    helperText: _isLoadingDiscovery
                        ? '正在扫描局域网设备...'
                        : (_discoveredDevices.isEmpty
                            ? '未发现设备，可手动输入或扫描二维码'
                            : '已发现 ${_discoveredDevices.length} 个设备，可下拉选择或手动输入'),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isLoadingDiscovery)
                          const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        else if (_discoveredDevices.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () {
                              setState(() {
                                _isLoadingDiscovery = true;
                              });
                              _loadDiscoveredDevices();
                            },
                            tooltip: '刷新设备列表',
                          ),
                        if (widget.isMobile)
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: () async {
                              // 打开二维码扫描页面
                              final scannedValue = await Navigator.of(context).push<String>(
                                MaterialPageRoute(
                                  builder: (context) => QRScannerScreen(
                                    onScanResult: null,
                                  ),
                                ),
                              );
                              // 如果扫描成功，更新设备 ID
                              debugPrint('扫描返回的值: $scannedValue');
                              if (scannedValue != null && scannedValue.isNotEmpty) {
                                widget.deviceIdController.text = scannedValue;
                                textEditingController.text = scannedValue;
                                // 显示成功提示
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('扫描成功: ${scannedValue.length} 个字符'),
                                      duration: const Duration(seconds: 2),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              }
                            },
                            tooltip: '扫描二维码',
                          ),
                      ],
                    ),
                  ),
                  maxLength: 63, // Syncthing 设备ID格式：8组×7字符 + 7个连字符 = 63字符
                  onChanged: (value) {
                    widget.deviceIdController.text = value;
                  },
                );
              },
            ),
            if (widget.isMobile) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  // 打开二维码扫描页面
                  final scannedValue = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (context) => QRScannerScreen(
                        onScanResult: null,
                      ),
                    ),
                  );
                  // 如果扫描成功，更新设备 ID
                  debugPrint('扫描返回的值: $scannedValue');
                  if (scannedValue != null && scannedValue.isNotEmpty) {
                    widget.deviceIdController.text = scannedValue;
                    // 显示成功提示
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('扫描成功: ${scannedValue.length} 个字符'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('扫描二维码'),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: widget.nameController,
              decoration: const InputDecoration(
                labelText: '设备名称',
                hintText: '请输入设备名称（可选）',
                helperText: '如果留空，将使用设备通告的名称',
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
          onPressed: () async {
            if (widget.deviceIdController.text.isNotEmpty) {
              try {
                await widget.deviceProvider.addDevice(
                  deviceID: widget.deviceIdController.text,
                  name: widget.nameController.text,
                );
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('设备添加成功'),
                      backgroundColor: Colors.green,
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
              }
            }
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
