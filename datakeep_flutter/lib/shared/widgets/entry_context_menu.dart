import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/services/api_service.dart';

/// 浏览页文件/子文件夹：重命名 / 删除 / 忽略（本机可写时）
class EntryContextActions {
  EntryContextActions._();

  static Future<void> renameEntry(
    BuildContext context, {
    required String folderId,
    required String relativePath,
    /// 同步根绝对路径（优先本机 rename，避免热重启后旧后端无 rename 路由）
    String folderRootPath = '',
    required bool isDir,
    required VoidCallback onSuccess,
  }) async {
    final oldName = p.basename(relativePath.replaceAll('\\', '/'));
    if (oldName.isEmpty) return;

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(
        title: isDir ? '重命名文件夹' : '重命名文件',
        initialName: oldName,
      ),
    );
    if (newName == null || !context.mounted) return;
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能为空')),
      );
      return;
    }
    if (newName == oldName) return;
    if (newName.contains('/') ||
        newName.contains('\\') ||
        newName == '.' ||
        newName == '..') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能包含路径分隔符')),
      );
      return;
    }

    try {
      await _doRename(
        folderId: folderId,
        relativePath: relativePath,
        folderRootPath: folderRootPath,
        newName: newName,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已重命名为 "$newName"')),
      );
      onSuccess();
    } catch (e) {
      debugPrint('[rename] UI 失败: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('重命名失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static Future<void> _doRename({
    required String folderId,
    required String relativePath,
    required String folderRootPath,
    required String newName,
  }) async {
    final root = folderRootPath.trim();
    if (root.isNotEmpty) {
      await _renameLocal(root, relativePath, newName);
      try {
        await ApiService.scanFolder(folderId);
      } catch (_) {}
      return;
    }
    // 无本机路径时走后端
    await ApiService.renameFolderFile(folderId, relativePath, newName);
  }

  static Future<void> _renameLocal(
    String folderRootPath,
    String relativePath,
    String newName,
  ) async {
    final rel = relativePath
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+'), '');
    final segments = rel.split('/').where((s) => s.isNotEmpty && s != '.' && s != '..');
    final src = p.joinAll([folderRootPath, ...segments]);
    final parent = p.dirname(src);
    final dest = p.join(parent, newName);

    debugPrint('[rename] local $src → $dest');

    final type = await FileSystemEntity.type(src, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw Exception('源文件不存在: $src');
    }
    if (await FileSystemEntity.type(dest, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw Exception('已存在同名文件或文件夹');
    }

    if (type == FileSystemEntityType.directory) {
      await Directory(src).rename(dest);
    } else {
      await File(src).rename(dest);
    }
  }

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
    String folderRootPath = '',
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
        const PopupMenuItem(value: 'rename', child: Text('重命名')),
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
    if (!context.mounted || selected == null) return;
    if (selected == 'rename') {
      await renameEntry(
        context,
        folderId: folderId,
        relativePath: relativePath,
        folderRootPath: folderRootPath,
        isDir: isDir,
        onSuccess: onSuccess,
      );
    } else if (selected == 'delete') {
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
    String folderRootPath = '',
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
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                renameEntry(
                  context,
                  folderId: folderId,
                  relativePath: relativePath,
                  folderRootPath: folderRootPath,
                  isDir: isDir,
                  onSuccess: onSuccess,
                );
              },
            ),
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

/// 重命名对话框：自行持有 TextEditingController，避免弹窗关闭后误用已 dispose 的 controller
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({
    required this.title,
    required this.initialName,
  });

  final String title;
  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '新名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确定'),
        ),
      ],
    );
  }
}
