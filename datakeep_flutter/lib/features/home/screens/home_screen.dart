import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../devices/providers/device_provider.dart';
import '../../devices/screens/devices_screen.dart';
import '../../folders/providers/folder_provider.dart';
import '../../../core/models/device.dart';
import '../../../core/models/folder.dart';
import '../../../shared/widgets/folder_card.dart';
import '../../../shared/widgets/folder_edit_dialog.dart';
import '../../../shared/widgets/device_info_panel.dart';
import '../../../shared/utils/open_syncthing_gui.dart';
import '../../../core/services/api_service.dart';
import '../../folders/screens/folder_detail_screen.dart';
import '../../sync/screens/sync_screen.dart';
import '../../apps/open_app.dart';
import '../../apps/screens/market_screen.dart';
import '../../../shared/widgets/add_item_dialog.dart';
import '../../../shared/widgets/peer_folder_status_view.dart';
import '../../../shared/constants/app_info.dart';
import '../../../shared/widgets/app_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedDeviceId;

  @override
  void initState() {
    super.initState();
    // 初始化数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceProvider>().fetchDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _showMenu(context);
          },
        ),
        title: const Row(
          children: [
            AppLogo(size: 28),
            SizedBox(width: 8),
            Text(kAppDisplayName),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<DeviceProvider>().fetchDevices();
              if (_selectedDeviceId != null) {
                _loadDeviceFolders(_selectedDeviceId!);
              }
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

          // 启动后默认选中本机设备
          if (_selectedDeviceId == null && deviceProvider.devices.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _selectedDeviceId != null) return;
              final local = deviceProvider.devices.firstWhere(
                (d) => d.isLocal,
                orElse: () => deviceProvider.devices.first,
              );
              setState(() {
                _selectedDeviceId = local.id;
              });
              _loadDeviceFolders(local.id);
            });
          }

          return Column(
            children: [
              // 顶部设备列表 Tab
              _buildDeviceTabBar(context, deviceProvider),
              // 文件夹列表
              Expanded(
                child: _buildFoldersList(context),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _isSelectedLocalDevice(context)
          ? FloatingActionButton(
              onPressed: () {
                AddItemDialog.show(
                  context,
                  onDone: () {
                    if (_selectedDeviceId != null) {
                      _loadDeviceFolders(_selectedDeviceId!);
                    }
                  },
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  // 构建设备 Tab 栏
  Widget _buildDeviceTabBar(BuildContext context, DeviceProvider deviceProvider) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: deviceProvider.devices.length + 1, // +1 用于添加设备按钮
        itemBuilder: (context, index) {
          // 最后一个按钮是添加设备
          if (index == deviceProvider.devices.length) {
            return _buildAddDeviceChip(context);
          }

          final device = deviceProvider.devices[index];
          final isSelected = _selectedDeviceId == device.id;

          return _buildDeviceChip(context, device, isSelected);
        },
      ),
    );
  }

  // 构建设备 Chip
  Widget _buildDeviceChip(BuildContext context, Device device, bool isSelected) {
    final isLocal = device.isLocal;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDeviceId = device.id;
        });
        _loadDeviceFolders(device.id);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Chip(
          avatar: CircleAvatar(
            backgroundColor: isSelected
                ? Theme.of(context).colorScheme.primary
                : (isLocal
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.tertiary),
            radius: 12,
            child: Icon(
              isLocal ? Icons.computer : Icons.phone_android,
              size: 16,
              color: Colors.white,
            ),
          ),
          label: Text(
            isLocal ? '本机' : device.displayName,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : null,
            ),
          ),
          backgroundColor: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceVariant,
          side: BorderSide(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
      ),
    );
  }

  // 构建添加设备 Chip
  Widget _buildAddDeviceChip(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        avatar: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          radius: 12,
          child: const Icon(
            Icons.add,
            size: 16,
            color: Colors.white,
          ),
        ),
        label: const Text(
          '添加设备',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
        ),
        onPressed: () {
          DevicesScreen.showAddDeviceDialog(context);
        },
      ),
    );
  }

  // 构建文件夹列表
  Widget _buildFoldersList(BuildContext context) {
    if (_selectedDeviceId == null) {
      return const Center(child: Text('请选择一个设备'));
    }

    final devices = context.watch<DeviceProvider>().devices;
    Device? selectedDevice;
    for (final d in devices) {
      if (d.id == _selectedDeviceId) {
        selectedDevice = d;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedDevice != null)
          DeviceInfoPanel(
            device: selectedDevice,
            onDeleted: () => _onDeviceDeleted(context),
          ),
        Expanded(child: _buildFoldersContent(context)),
      ],
    );
  }

  void _onDeviceDeleted(BuildContext context) {
    final provider = context.read<DeviceProvider>();
    Device? next;
    if (provider.devices.isNotEmpty) {
      next = provider.devices.firstWhere(
        (d) => d.isLocal,
        orElse: () => provider.devices.first,
      );
    }
    setState(() {
      _selectedDeviceId = next?.id;
    });
    if (next != null) {
      _loadDeviceFolders(next.id);
    }
  }

  Widget _buildFoldersContent(BuildContext context) {
    final deviceId = _selectedDeviceId!;
    final devices = context.watch<DeviceProvider>().devices;
    final selectedIsLocal = devices.any((d) => d.id == deviceId && d.isLocal);
    return Consumer<FolderProvider>(
      builder: (context, folderProvider, _) {
        if (folderProvider.loadedDeviceId != deviceId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selectedDeviceId == deviceId) {
              folderProvider.fetchDeviceFolders(deviceId);
            }
          });
        }

        if (folderProvider.isLoading && folderProvider.loadedDeviceId != deviceId) {
          return const Center(child: CircularProgressIndicator());
        }

        if (folderProvider.loadedDeviceId == deviceId && folderProvider.error != null) {
          return PeerFolderStatusView(
            error: folderProvider.error,
            onRetry: () => folderProvider.fetchDeviceFolders(deviceId),
          );
        }

        final folders = folderProvider.loadedDeviceId == deviceId
            ? folderProvider.folders
            : const <Folder>[];

        if (folders.isEmpty && !folderProvider.isLoading) {
          return Center(
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
                  'Syncthing 启动中或未配置文件夹',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => folderProvider.fetchDeviceFolders(deviceId),
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: folders.length,
          itemBuilder: (context, index) {
            final folder = folders[index];
            return FolderCard(
              folder: folder,
              // 远程列表已是对端真实数据，可显示路径与统计
              showPath: true,
              onEdit: selectedIsLocal
                  ? () {
                      FolderEditDialog.show(
                        context,
                        folder: folder,
                        onDone: () => _loadDeviceFolders(deviceId),
                      );
                    }
                  : null,
              onBrowseFiles: folder.isApp && selectedIsLocal
                  ? () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => FolderDetailScreen(
                            deviceId: folder.deviceId,
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
                      deviceId: folder.deviceId,
                      folderId: folder.id,
                    ),
                  ),
                );
              },
              isDesktop: false,
            );
          },
        );
      },
    );
  }

  // 加载设备文件夹
  Future<void> _loadDeviceFolders(String deviceId) async {
    await context.read<FolderProvider>().fetchDeviceFolders(deviceId);
  }

  // 显示菜单
  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('设备管理'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DevicesScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('同步状态'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SyncScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('应用市场'),
              subtitle: const Text('浏览并安装应用'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MarketScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('Syncthing 管理页'),
              subtitle: const Text('高级配置出口'),
              onTap: () {
                Navigator.pop(context);
                openSyncthingGui(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('本机配对二维码'),
              onTap: () async {
                Navigator.pop(context);
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
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('关于'),
              onTap: () {
                Navigator.pop(context);
                showAboutDialog(
                  context: context,
                  applicationName: kAppDisplayName,
                  applicationVersion: '1.0.0',
                  applicationIcon: const AppLogo(size: 48),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isSelectedLocalDevice(BuildContext context) {
    if (_selectedDeviceId == null) return false;
    final local = context.read<DeviceProvider>().devices.firstWhere(
      (d) => d.isLocal,
      orElse: () => Device(id: '', name: ''),
    );
    return local.id == _selectedDeviceId;
  }
}

