import 'package:flutter/material.dart';
import '../../../core/models/device.dart';
import '../../../core/models/folder.dart';
import '../../../core/services/api_service.dart';
import '../../folders/screens/folder_detail_screen.dart';
import '../../../shared/widgets/folder_card.dart';

class DeviceDetailScreen extends StatefulWidget {
  final String deviceId;

  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  Device? _device;
  List<Folder> _folders = [];
  bool _isLoading = true;
  String? _error;
  String? _wifiName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 加载设备信息
      if (widget.deviceId == 'local') {
        _device = Device(
          id: 'local',
          name: '本机设备',
          addresses: [],
          connected: true,
          connectionType: 'local',
          version: 'local',
          isLocalNetwork: true,
          crypto: 'local',
        );
      } else {
        final devices = await ApiService.getDevices();
        _device = devices.firstWhere(
          (d) => d.id == widget.deviceId,
          orElse: () => Device(
            id: widget.deviceId,
            name: widget.deviceId,
            addresses: [],
            connected: false,
            isLocalNetwork: false,
          ),
        );
      }

      // 加载文件夹列表
      _folders = await ApiService.getDeviceFolders(widget.deviceId);

      // 加载 WiFi 信息（仅本机设备）
      if (widget.deviceId == 'local') {
        try {
          final wifiInfo = await ApiService.getWifiInfo();
          _wifiName = wifiInfo['wifiName'] as String?;
        } catch (e) {
          debugPrint('获取WiFi信息失败: $e');
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        title: Text(_device?.name ?? '设备详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
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
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _buildContent(isDesktop),
    );
  }

  Widget _buildContent(bool isDesktop) {
    return Column(
      children: [
        // 设备信息卡片
        if (isDesktop)
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Text(
                  _device?.name ?? '设备详情',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
              ],
            ),
          ),
        // 设备信息
        _buildDeviceInfo(),
        // 文件夹列表
        Expanded(
          child: _folders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无文件夹',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '该设备还没有共享任何文件夹',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : isDesktop
                  ? _buildDesktopFolderList()
                  : _buildMobileFolderList(),
        ),
      ],
    );
  }

  Widget _buildDeviceInfo() {
    if (_device == null) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getDeviceTypeColor(_device!.type),
                  radius: 24,
                  child: Icon(
                    _getDeviceTypeIcon(_device!.type),
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
                            _device!.name,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          if (_device!.isLocal) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _device!.connected || _device!.isLocal
                                ? Icons.wifi
                                : Icons.wifi_off,
                            size: 16,
                            color: _device!.connected || _device!.isLocal
                                ? Colors.green
                                : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _device!.connected || _device!.isLocal
                                ? '在线'
                                : '离线',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          if (_device!.connectionType != null &&
                              _device!.connectionType != 'local') ...[
                            const SizedBox(width: 16),
                            Text(
                              _getConnectionTypeText(_device!.connectionType!),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_wifiName != null) ...[
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.wifi, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '当前WiFi: $_wifiName',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            if (_device!.addresses != null && _device!.addresses!.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '地址:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _device!.addresses!.take(3).map((addr) {
                  return Chip(
                    label: Text(
                      addr,
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],
            if (_device!.version != null && _device!.version != 'local') ...[
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '版本: ${_device!.version}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopFolderList() {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return FolderCard(
          folder: folder,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FolderDetailScreen(
                  deviceId: widget.deviceId,
                  folderId: folder.id,
                ),
              ),
            );
          },
          isDesktop: true,
        );
      },
    );
  }

  Widget _buildMobileFolderList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        return FolderCard(
          folder: folder,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FolderDetailScreen(
                  deviceId: widget.deviceId,
                  folderId: folder.id,
                ),
              ),
            );
          },
          isDesktop: false,
        );
      },
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

  String _getConnectionTypeText(String type) {
    switch (type) {
      case 'tcp-server':
        return 'TCP 服务器';
      case 'tcp-client':
        return 'TCP 客户端';
      case 'quic':
        return 'QUIC';
      default:
        return type;
    }
  }
}

