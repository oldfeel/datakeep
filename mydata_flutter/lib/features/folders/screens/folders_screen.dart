import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/folder_provider.dart';
import '../../devices/providers/device_provider.dart';
import '../../devices/screens/devices_screen.dart';
import '../../../core/models/folder.dart';
import '../../../core/models/device.dart';
import '../../../shared/widgets/folder_card.dart';
import 'folder_detail_screen.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;
    
    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        title: const Text('文件夹管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<FolderProvider>().fetchFolders();
            },
          ),
        ],
      ),
      body: Consumer<FolderProvider>(
        builder: (context, folderProvider, child) {
          if (folderProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (folderProvider.error != null) {
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
                    folderProvider.error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      folderProvider.clearError();
                      folderProvider.fetchFolders();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }

          if (folderProvider.folders.isEmpty) {
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
                    '点击下方按钮添加第一个同步文件夹',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          // 桌面端使用网格布局，移动端使用列表布局
          if (isDesktop) {
            return _buildDesktopLayout(context, folderProvider);
          } else {
            return _buildMobileLayout(context, folderProvider);
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddFolderDialog(context);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  // 桌面端网格布局
  Widget _buildDesktopLayout(BuildContext context, FolderProvider folderProvider) {
    return Column(
      children: [
        // 桌面端标题栏
        Container(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Text(
                '文件夹管理',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  context.read<FolderProvider>().fetchFolders();
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
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.2,
            ),
            itemCount: folderProvider.folders.length,
            itemBuilder: (context, index) {
              final folder = folderProvider.folders[index];
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
                isDesktop: true,
              );
            },
          ),
        ),
      ],
    );
  }

  // 移动端列表布局
  Widget _buildMobileLayout(BuildContext context, FolderProvider folderProvider) {
    return Column(
      children: [
        // 顶部设备列表（类似 tab）
        _buildDeviceTabBar(context),
        // 文件夹列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: folderProvider.folders.length,
            itemBuilder: (context, index) {
              final folder = folderProvider.folders[index];
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
          ),
        ),
      ],
    );
  }

  // 构建设备 Tab 栏
  Widget _buildDeviceTabBar(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
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
              return _buildDeviceChip(context, device);
            },
          ),
        );
      },
    );
  }

  // 构建设备 Chip
  Widget _buildDeviceChip(BuildContext context, Device device) {
    final isLocal = device.isLocal;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Chip(
        avatar: CircleAvatar(
          backgroundColor: isLocal 
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondary,
          radius: 12,
          child: Icon(
            isLocal ? Icons.computer : Icons.phone_android,
            size: 16,
            color: Colors.white,
          ),
        ),
        label: Text(
          device.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
        onDeleted: null,
        deleteIcon: null,
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
          // 调用 DevicesScreen 的添加设备对话框
          DevicesScreen.showAddDeviceDialog(context);
        },
      ),
    );
  }

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
                  pathController.text.isNotEmpty) {
                context.read<FolderProvider>().createFolder(
                      id: idController.text,
                      name: nameController.text,
                      path: pathController.text,
                    );
                Navigator.of(context).pop();
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

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
