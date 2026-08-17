import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/models/device.dart';
import '../../../core/models/folder.dart';
import '../../../core/services/api_service.dart';
import '../../folders/screens/folder_detail_screen.dart';
import '../../../shared/widgets/folder_card.dart';
import '../../../shared/widgets/device_info_panel.dart';
import '../../../shared/widgets/peer_folder_status_view.dart';
import '../../../shared/utils/peer_folder_error.dart';
import '../../apps/open_app.dart';

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
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  void _scheduleWaitRetry() {
    _waitTimer?.cancel();
    if (!peerFolderErrorShouldAutoRetry(classifyPeerFolderError(_error))) {
      return;
    }
    _waitTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) _loadData();
    });
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
      _waitTimer?.cancel();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      _scheduleWaitRetry();
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
              ? PeerFolderStatusView(
                  error: _error,
                  onRetry: _loadData,
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
        // 设备信息（可展开/收起）
        if (_device != null)
          DeviceInfoPanel(
            device: _device!,
            wifiName: _wifiName,
            onDeleted: () {
              if (mounted) Navigator.of(context).pop();
            },
          ),
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
          showPath: _device?.isLocal ?? false,
          onBrowseFiles: folder.isApp && (_device?.isLocal ?? false)
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FolderDetailScreen(
                        deviceId: widget.deviceId,
                        folderId: folder.id,
                      ),
                    ),
                  );
                }
              : null,
          onTap: () {
            if (folder.isApp) {
              openFolderApp(context, folder);
              return;
            }
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
          showPath: _device?.isLocal ?? false,
          onBrowseFiles: folder.isApp && (_device?.isLocal ?? false)
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FolderDetailScreen(
                        deviceId: widget.deviceId,
                        folderId: folder.id,
                      ),
                    ),
                  );
                }
              : null,
          onTap: () {
            if (folder.isApp) {
              openFolderApp(context, folder);
              return;
            }
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
}

