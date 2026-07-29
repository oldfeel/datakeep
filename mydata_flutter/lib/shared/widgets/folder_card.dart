import 'package:flutter/material.dart';
import '../../core/models/folder.dart';

class FolderCard extends StatelessWidget {
  final Folder folder;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;
  final bool isDesktop;
  /// 是否显示路径与统计（本机或已从对端拉取的真实数据）。
  final bool showPath;

  const FolderCard({
    super.key,
    required this.folder,
    this.onEdit,
    this.onTap,
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

  // 桌面端卡片 - 更紧凑的网格布局
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
              // 头部：图标和状态
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getStatusColor(folder.status),
                    child: Icon(
                      _getStatusIcon(folder.status),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      folder.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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

  // 移动端卡片 - 列表布局
  Widget _buildMobileCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(folder.status),
          child: Icon(
            _getStatusIcon(folder.status),
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
        trailing: onEdit != null
            ? IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: '编辑',
                onPressed: onEdit,
              )
            : null,
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
