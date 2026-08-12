import 'package:flutter/material.dart';

import '../../core/models/folder.dart';
import '../../features/apps/screens/app_runner_page.dart';

void openFolderApp(BuildContext context, Folder folder) {
  if (!folder.isApp) return;
  if (folder.path.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('应用路径为空')),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AppRunnerPage(
        appPath: folder.path,
        title: folder.name,
      ),
    ),
  );
}
