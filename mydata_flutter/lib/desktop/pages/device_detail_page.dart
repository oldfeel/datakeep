import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../shared/widgets/device_info_panel.dart';
class DeviceDetailPage extends StatefulWidget {
  final Device device;
  final void Function(Folder folder) onFolderTap;
  final VoidCallback onBack;

  const DeviceDetailPage({
    super.key,
    required this.device,
    required this.onFolderTap,
    required this.onBack,
  });

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  List<Folder> _folders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final folders = await context.read<FolderProvider>().getDeviceFolders(widget.device.id);
      if (mounted) setState(() { _folders = folders; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          DeviceInfoPanel(
            device: widget.device,
            margin: EdgeInsets.zero,
            onDeleted: widget.onBack,
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildFolderList(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
          tooltip: '返回',
        ),
        const SizedBox(width: 8),
        Icon(Icons.devices, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.device.displayName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderList(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text('加载文件夹失败', style: Theme.of(context).textTheme.titleMedium),
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadFolders, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('暂无文件夹', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _showAddFolderDialog,
              icon: const Icon(Icons.add),
              label: const Text('添加文件夹'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('同步文件夹', style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            )),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _showAddFolderDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加'),
              style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loadFolders,
              tooltip: '刷新',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: _folders.length,
            itemBuilder: (context, index) {
              final folder = _folders[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.folder, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(folder.path, style: Theme.of(context).textTheme.bodySmall),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        tooltip: '编辑共享',
                        onPressed: () => _showSharingDialog(context, folder),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: Colors.red,
                        tooltip: '删除',
                        onPressed: () => _showDeleteFolderDialog(context, folder),
                      ),
                    ],
                  ),
                  onTap: () => widget.onFolderTap(folder),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddFolderDialog() {
    final idController = TextEditingController();
    final nameController = TextEditingController();
    final pathController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加同步文件夹'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: idController, decoration: const InputDecoration(labelText: '文件夹 ID')),
              const SizedBox(height: 16),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: '文件夹名称')),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(controller: pathController, decoration: const InputDecoration(labelText: '文件夹路径')),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: '浏览',
                    onPressed: () async {
                      final result = await FilePicker.platform.getDirectoryPath();
                      if (result != null) {
                        pathController.text = result;
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (idController.text.isEmpty || nameController.text.isEmpty || pathController.text.isEmpty) return;
              try {
                await context.read<FolderProvider>().createFolder(
                  id: idController.text,
                  name: nameController.text,
                  path: pathController.text,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadFolders();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('添加失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderDialog(BuildContext context, Folder folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文件夹 "${folder.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              try {
                await context.read<FolderProvider>().deleteFolder(folder.id);
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadFolders();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showSharingDialog(BuildContext context, Folder folder) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('文件夹共享设置'),
        content: const Text('共享功能待实现'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
  }
}
