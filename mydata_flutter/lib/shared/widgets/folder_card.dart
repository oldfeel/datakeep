import 'package:flutter/material.dart';
import '../../core/models/folder.dart';

class FolderCard extends StatelessWidget {
  final Folder folder;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final VoidCallback? onOpenApp;
  final bool isDesktop;
  /// 是否显示路径与统计（本机或已从对端拉取的真实数据）。
  final bool showPath;

  const FolderCard({
    super.key,
    required this.folder,
    this.onEdit,
    this.onTap,
    this.onOpenApp,
    this.isDesktop = false,
    this.showPath = true,
  });

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return _buildDesktopCard(context);
    } else {
      return _buildMobileCard(context);
    }
  }

  Widget _buildDesktopCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: folder.isApp
                        ? Theme.of(context).colorScheme.tertiary
                        : _getStatusColor(folder.status),
                    child: Icon(
                      folder.isApp ? Icons.apps : _getStatusIcon(folder.status),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          folder.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (folder.isApp)
                          Text(
                            '应用',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                          ),
                      ],
                    ),
                  ),
                  if (folder.isApp && onOpenApp != null)
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 22),
                      tooltip: '打开应用',
                      onPressed: onOpenApp,
                    ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: '编辑',
                      onPressed: onEdit,
                    ),
                ],
              ),
              if (showPath && folder.path.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  folder.path,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const Spacer(),
              if (showPath)
                Row(
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      size: 16,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${folder.fileCount} 个文件',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Icon(
                      Icons.storage,
                      size: 16,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatFileSize(folder.totalSize),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: folder.isApp
              ? Theme.of(context).colorScheme.tertiary
              : _getStatusColor(folder.status),
          child: Icon(
            folder.isApp ? Icons.apps : _getStatusIcon(folder.status),
            color: Colors.white,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                folder.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (folder.isApp)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Chip(
                  label: const Text('应用'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  labelStyle: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            if (folder.isReadonlyAccess)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '只读',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                ),
              ),
          ],
        ),
        subtitle: showPath
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (folder.path.isNotEmpty) ...[
                    Text(
                      folder.path,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Icon(
                        Icons.insert_drive_file,
                        size: 16,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${folder.fileCount} 个文件',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.storage,
                        size: 16,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatFileSize(folder.totalSize),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (folder.isApp && onOpenApp != null)
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: '打开应用',
                onPressed: onOpenApp,
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: '编辑',
                onPressed: onEdit,
              ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'syncing':
        return Colors.orange;
      case 'waiting':
        return Colors.blue;
      case 'synced':
        return Colors.green;
      case 'error':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'syncing':
        return Icons.sync;
      case 'waiting':
        return Icons.hourglass_empty;
      case 'synced':
        return Icons.check;
      case 'error':
        return Icons.error;
      default:
        return Icons.folder;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
