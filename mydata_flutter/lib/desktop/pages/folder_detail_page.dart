import 'package:flutter/material.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../widgets/file_icon.dart';

class FolderDetailPage extends StatefulWidget {
  final Device device;
  final Folder folder;
  final void Function(String filePath) onFileTap;
  final VoidCallback onBack;

  const FolderDetailPage({
    super.key,
    required this.device,
    required this.folder,
    required this.onFileTap,
    required this.onBack,
  });

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  List<Map<String, dynamic>> _files = [];
  final List<String> _currentPath = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final path = _currentPath.join('/');
      final files = await ApiService.getFolderFiles(widget.folder.id, path: path.isEmpty ? null : path);
      if (mounted) setState(() { _files = files; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _enterFolder(String name) {
    setState(() { _currentPath.add(name); });
    _loadFiles();
  }

  void _navigateToPath(List<String> targetPath) {
    setState(() {
      _currentPath.clear();
      _currentPath.addAll(targetPath);
    });
    _loadFiles();
  }

  void _goUp() {
    if (_currentPath.isEmpty) return;
    setState(() { _currentPath.removeLast(); });
    _loadFiles();
  }

  String _formatSize(dynamic size) {
    final s = (size is int ? size : int.tryParse(size.toString()) ?? 0);
    if (s == 0) return '-';
    const units = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double result = s.toDouble();
    while (result >= 1024 && i < units.length - 1) { result /= 1024; i++; }
    return '${result.toStringAsFixed(result >= 100 ? 0 : 1)} ${units[i]}';
  }

  String _formatTime(dynamic timestamp) {
    final t = (timestamp is int ? timestamp : int.tryParse(timestamp.toString()) ?? 0);
    if (t == 0) return '-';
    final dt = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBreadcrumb(context),
          const SizedBox(height: 8),
          _buildToolbar(context),
          const SizedBox(height: 16),
          Expanded(child: _buildFileTable(context)),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onBack,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.arrow_back, size: 20),
                  const SizedBox(width: 4),
                  Icon(Icons.home, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(widget.device.name,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                ],
              ),
            ),
          ),
          const Text(' / ', style: TextStyle(color: Colors.grey)),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _navigateToPath([]),
              child: Text(widget.folder.name,
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          ),
          for (var i = 0; i < _currentPath.length; i++) ...[
            const Text(' / ', style: TextStyle(color: Colors.grey)),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: i < _currentPath.length - 1
                    ? () => _navigateToPath(_currentPath.sublist(0, i + 1))
                    : null,
                child: Text(
                  _currentPath[i],
                  style: TextStyle(
                    color: i < _currentPath.length - 1
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: i == _currentPath.length - 1 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Row(
      children: [
        Text(
          _currentPath.isEmpty ? widget.folder.name : _currentPath.last,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (_currentPath.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: '上级目录',
            onPressed: _goUp,
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新',
          onPressed: _loadFiles,
        ),
      ],
    );
  }

  Widget _buildFileTable(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadFiles, child: const Text('重试')),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text('该目录为空', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          final name = file['name']?.toString() ?? '';
          final isDir = file['isDir'] == true || file['type'] == 'dir';
          final size = file['size'];
          final modTime = file['modTime'] ?? file['modified'];
          final onClick = isDir ? () => _enterFolder(name) : () => widget.onFileTap(name);

          return ListTile(
            dense: true,
            leading: Icon(getFileIcon(name, isDir: isDir), color: getFileIconColor(name, isDir: isDir)),
            title: Text(name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(isDir ? '文件夹' : _formatSize(size),
              style: Theme.of(context).textTheme.bodySmall),
            trailing: Text(_formatTime(modTime),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            onTap: onClick,
          );
        },
      ),
    );
  }
}
