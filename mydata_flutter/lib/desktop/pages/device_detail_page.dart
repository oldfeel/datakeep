import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../shared/widgets/device_info_panel.dart';
import '../../shared/widgets/folder_edit_dialog.dart';
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

  @override
  void didUpdateWidget(covariant DeviceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      _loadFolders();
    }
  }

  Future<void> _loadFolders() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final folders =
          await context.read<FolderProvider>().getDeviceFolders(widget.device.id);
      debugPrint(
        '[device-detail] device=${widget.device.id} '
        'local=${widget.device.isLocal} folders=${folders.length} '
        'ids=${folders.map((f) => f.id).join(",")}',
      );
      if (mounted) setState(() { _folders = folders; _isLoading = false; });
    } catch (e) {
      debugPrint('[device-detail] 加载失败 device=${widget.device.id}: $e');
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
            if (widget.device.isLocal) ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _showAddFolderDialog,
                icon: const Icon(Icons.add),
                label: const Text('添加文件夹'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.device.isLocal ? '本机文件夹' : '对方文件夹',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (widget.device.isLocal)
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
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                      ),
                      if (folder.isReadonlyAccess)
                        Text(
                          '只读',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                  subtitle: folder.path.isNotEmpty || folder.fileCount > 0 || folder.totalSize > 0
                      ? Text(
                          [
                            if (folder.path.isNotEmpty) folder.path,
                            '${folder.fileCount} 个文件 · ${_formatFileSize(folder.totalSize)}',
                          ].join('\n'),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      : null,
                  isThreeLine: folder.path.isNotEmpty,
                  trailing: widget.device.isLocal
                      ? IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: '编辑',
                          onPressed: () => _showSharingDialog(context, folder),
                        )
                      : null,
                  onTap: () => widget.onFolderTap(folder),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
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
              TextField(controller: idController, decoration: const InputDecoration(labelText: '文件夹 ID（英文标识）')),
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
                        final dirName = result.split('/').last;
                        if (idController.text.isEmpty) idController.text = dirName;
                        if (nameController.text.isEmpty) nameController.text = dirName;
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
              if (idController.text.isEmpty || nameController.text.isEmpty || pathController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请填写完整信息'), backgroundColor: Colors.orange),
                );
                return;
              }
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

  void _showSharingDialog(BuildContext context, Folder folder) {
    FolderEditDialog.show(context, folder: folder, onDone: _loadFolders);
  }
}
