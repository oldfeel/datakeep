import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../devices/providers/device_provider.dart';
import '../../devices/screens/devices_screen.dart';
import '../../folders/providers/folder_provider.dart';
import '../../../core/models/device.dart';
import '../../../core/models/folder.dart';
import '../../../shared/widgets/folder_card.dart';
import '../../../shared/widgets/device_info_panel.dart';
import '../../folders/screens/folder_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedDeviceId;
  List<Folder> _deviceFolders = [];
  bool _isLoadingFolders = false;
  String? _foldersError;

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
        title: const Text('MyData'),
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
      floatingActionButton: _selectedDeviceId != null
          ? FloatingActionButton(
              onPressed: () {
                _showAddFolderDialog(context);
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
            device.displayName,
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
      _deviceFolders = [];
    });
    if (next != null) {
      _loadDeviceFolders(next.id);
    }
  }

  Widget _buildFoldersContent(BuildContext context) {
    if (_isLoadingFolders) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_foldersError != null) {
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
              '加载文件夹失败',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _foldersError!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                _loadDeviceFolders(_selectedDeviceId!);
              },
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_deviceFolders.isEmpty) {
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
              '点击右下角按钮添加第一个同步文件夹',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _deviceFolders.length,
      itemBuilder: (context, index) {
        final folder = _deviceFolders[index];
        return FolderCard(
          folder: folder,
          onDelete: () {
            _showDeleteDialog(context, folder);
          },
          onTap: () {
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
  }

  // 加载设备文件夹
  Future<void> _loadDeviceFolders(String deviceId) async {
    setState(() {
      _isLoadingFolders = true;
      _foldersError = null;
    });

    try {
      final folders = await context.read<FolderProvider>().getDeviceFolders(deviceId);
      setState(() {
        _deviceFolders = folders;
        _isLoadingFolders = false;
      });
    } catch (e) {
      setState(() {
        _foldersError = e.toString();
        _isLoadingFolders = false;
      });
    }
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
                // TODO: 导航到同步状态页面
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              onTap: () {
                Navigator.pop(context);
                // TODO: 导航到设置页面
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
                  applicationName: 'MyData',
                  applicationVersion: '1.0.0',
                  applicationIcon: const Icon(Icons.sync),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 显示添加文件夹对话框
  void _showAddFolderDialog(BuildContext context) {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final pathController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加同步文件夹'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: '文件夹 ID',
                  hintText: '请输入文件夹 ID（唯一标识）',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '文件夹名称',
                  hintText: '请输入文件夹名称',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: '文件夹路径',
                  hintText: '请输入文件夹路径',
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
            onPressed: () {
              if (idController.text.isNotEmpty &&
                  nameController.text.isNotEmpty &&
                  pathController.text.isNotEmpty &&
                  _selectedDeviceId != null) {
                context.read<FolderProvider>().createFolder(
                      id: idController.text,
                      name: nameController.text,
                      path: pathController.text,
                    );
                Navigator.of(context).pop();
                _loadDeviceFolders(_selectedDeviceId!);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  // 显示删除对话框
  void _showDeleteDialog(BuildContext context, Folder folder) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文件夹 "${folder.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<FolderProvider>().deleteFolder(folder.id);
              Navigator.of(context).pop();
              _loadDeviceFolders(_selectedDeviceId!);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

