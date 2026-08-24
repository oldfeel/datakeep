import 'package:flutter/material.dart';

import '../../core/models/folder.dart';
import '../../features/apps/screens/app_runner_page.dart';
import '../../shared/utils/app_dir.dart';
import '../../shared/utils/app_manifest.dart';

Future<bool?> openFolderApp(BuildContext context, Folder folder) async {
  if (!folder.isApp) return null;
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
