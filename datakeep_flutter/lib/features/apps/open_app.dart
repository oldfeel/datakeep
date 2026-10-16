import 'package:flutter/material.dart';

import '../../core/models/folder.dart';
import '../../features/apps/screens/app_runner_page.dart';
import '../../shared/utils/app_dir.dart';
import '../../shared/utils/app_manifest.dart';

/// 防止连点双开多个 AppRunner（争用稳定端口 / 旧服务尚未关闭）。
DateTime? _lastOpenFolderAppAt;

Future<bool?> openFolderApp(BuildContext context, Folder folder) async {
  if (!folder.isApp) return null;
  final now = DateTime.now();
  final last = _lastOpenFolderAppAt;
  if (last != null && now.difference(last) < const Duration(milliseconds: 800)) {
    return null;
  }
  _lastOpenFolderAppAt = now;

  if (!folder.isLocal) {
    openPeerApp(
      context,
      deviceId: folder.deviceId,
      folderId: folder.id,
      appRelPath: '',
      title: folder.name,
      writable: folder.isSyncAccess,
    );
    return null;
  }
  if (folder.path.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('应用路径为空')),
    );
    return null;
  }
  final manifest = AppManifest.tryReadFromDirectory(folder.path);
  final title = manifest?.displayName(fallback: folder.name) ?? folder.name;
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AppRunnerPage(
        appPath: folder.path,
        title: title,
        folderId: folder.id,
      ),
    ),
  );
}
