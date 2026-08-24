import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../../core/services/market_service.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../shared/utils/app_dir.dart';

/// 删除本机已安装的应用（含市场顶层安装、嵌套在同步文件夹内的应用）。
Future<void> deleteAppInstallation(
  FolderProvider provider, {
  required String appPath,
  String? folderId,
}) async {
  if (appPath.isEmpty) {
    throw Exception('无法删除：应用路径为空');
  }

  final folders = provider.folders;
  final normalized = normalizeFsPath(appPath);

  Folder? registered;
  if (folderId != null && folderId.isNotEmpty) {
    for (final f in folders) {
      if (f.id == folderId) {
        registered = f;
        break;
      }
    }
  }
  registered ??= findRegisteredApp(folders, appPath);

  final enclosing = findEnclosingSyncFolder(folders, appPath);
  final isNested = enclosing != null &&
      normalizeFsPath(enclosing.path) != normalized &&
      (registered == null || normalizeFsPath(registered.path) != normalized);

  String? removedFolderId;
  if (!isNested && registered != null && registered.isApp) {
    removedFolderId = registered.id;
  }

  if (!isNested &&
      registered != null &&
      registered.isApp &&
      registered.id.startsWith('app-')) {
    await MarketService.uninstall(registered.id.substring(4));
    await provider.refreshAfterDelete(
      removedFolderId: removedFolderId,
      removedPath: normalized,
    );
    return;
  }

  if (registered != null && registered.isApp && !isNested) {
    try {
      await provider.deleteFolder(registered.id);
    } catch (e) {
      debugPrint('[deleteApp] deleteFolder: $e');
    }
  }

  final dir = Directory(appPath);
  if (dir.existsSync()) {
    await dir.delete(recursive: true);
  }

  if (isNested) {
    try {
      await ApiService.scanFolder(enclosing.id);
    } catch (e) {
      debugPrint('[deleteApp] scan parent: $e');
    }
  }

  await provider.refreshAfterDelete(
    removedFolderId: isNested ? null : removedFolderId,
    removedPath: isNested ? null : normalized,
  );
}

Future<bool> confirmDeleteApp(
  BuildContext context,
  String name, {
  String title = '删除应用',
  String actionLabel = '删除',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(
        '确定$actionLabel「$name」？\n\n'
        '将删除该应用文件夹下的全部内容（含 data/ 中的数据库与用户数据），'
        '此操作不可恢复。\n\n'
        '若为独立同步应用，还会一并取消 Syncthing 文件夹注册。',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return ok == true;
}
