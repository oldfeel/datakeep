import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../../../core/models/device.dart';

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
          // TODO: 打开设备详情页面
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
                '最后在线: ${_formatDateTime(device.lastSeen)}',
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
              '最后在线: ${_formatDateTime(device.lastSeen)}',
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
          // TODO: 打开设备详情页面
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
}
