import 'package:flutter/material.dart';

import '../../core/services/api_service.dart';

/// 浏览页文件/子文件夹：删除 / 忽略（本机可写时）
class EntryContextActions {
  EntryContextActions._();

  static Future<void> deleteEntry(
    BuildContext context, {
    required String entryName,
    required String folderId,
    required String relativePath,
    required bool isDir,
    required VoidCallback onSuccess,
  }) async {
    final content = isDir
        ? '确定从本机删除 "$entryName" 及其全部内容？\n\n此操作不可恢复。'
        : '确定从本机删除 "$entryName"？\n\n此操作不可恢复。';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ApiService.deleteFolderFile(folderId, relativePath);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除 "$entryName"')),
      );
      onSuccess();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static Future<void> ignoreEntry(
    BuildContext context, {
    required String entryName,
    required String folderId,
    required String relativePath,
    required bool isDir,
    required VoidCallback onSuccess,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入忽略'),
        content: Text('将 "$entryName" 加入忽略规则，不再参与同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('忽略'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ApiService.appendFolderIgnore(
        folderId,
        relativePath,
        isDir: isDir,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已忽略 "$entryName"')),
      );
      onSuccess();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('忽略失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 桌面：右键菜单（文件 / 子文件夹）
  static Future<void> showEntryDesktopMenu(
    BuildContext context,
    Offset globalPosition, {
    required String entryName,
    required String folderId,
    required String relativePath,
    required bool isDir,
    required VoidCallback onSuccess,
  }) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'delete',
          child: Text(
            '删除',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        const PopupMenuItem(value: 'ignore', child: Text('忽略')),
      ],
    );
    if (selected == 'delete') {
      await deleteEntry(
        context,
        entryName: entryName,
        folderId: folderId,
        relativePath: relativePath,
        isDir: isDir,
        onSuccess: onSuccess,
      );
    } else if (selected == 'ignore') {
      await ignoreEntry(
        context,
        entryName: entryName,
        folderId: folderId,
        relativePath: relativePath,
        isDir: isDir,
        onSuccess: onSuccess,
      );
    }
  }

  /// 移动：长按菜单（文件 / 子文件夹）
  static Future<void> showEntryActionSheet(
    BuildContext context, {
    required String entryName,
    required String folderId,
    required String relativePath,
    required bool isDir,
    required VoidCallback onSuccess,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(entryName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(isDir ? '文件夹' : '文件'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                deleteEntry(
                  context,
                  entryName: entryName,
                  folderId: folderId,
                  relativePath: relativePath,
                  isDir: isDir,
                  onSuccess: onSuccess,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('忽略'),
              onTap: () {
                Navigator.pop(ctx);
                ignoreEntry(
                  context,
                  entryName: entryName,
                  folderId: folderId,
                  relativePath: relativePath,
                  isDir: isDir,
                  onSuccess: onSuccess,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
