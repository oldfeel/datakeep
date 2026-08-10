import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models/folder.dart';
import '../../features/apps/screens/app_runner_page.dart';

/// 规范化路径便于比较（去尾斜杠）
String normalizeFsPath(String path) {
  if (path.isEmpty) return path;
  final n = p.normalize(path);
  if (n.length > 1 && (n.endsWith('/') || n.endsWith('\\'))) {
    return n.substring(0, n.length - 1);
  }
  return n;
}

/// child 是否位于 parent 目录之下（不含自身）
bool isPathInside(String childPath, String parentPath) {
  final child = normalizeFsPath(childPath);
  final parent = normalizeFsPath(parentPath);
  if (child.isEmpty || parent.isEmpty || child == parent) return false;
  final prefix = parent.endsWith(p.separator) ? parent : '$parent${p.separator}';
  return child.startsWith(prefix) || child.startsWith('$parent/');
}

/// 在已有同步文件夹中，找出包围该路径的最内层父文件夹
Folder? findEnclosingSyncFolder(List<Folder> folders, String absolutePath) {
  Folder? best;
  var bestLen = -1;
  final want = normalizeFsPath(absolutePath);
  for (final f in folders) {
    final fp = normalizeFsPath(f.path);
    if (fp.isEmpty) continue;
    if (want == fp || isPathInside(want, fp)) {
      if (fp.length > bestLen) {
        best = f;
        bestLen = fp.length;
      }
    }
  }
  return best;
}

/// 目录是否包含 app.json（本地应用包）
bool isAppDirectory(String absolutePath) {
  if (absolutePath.isEmpty) return false;
  try {
    return File(p.join(absolutePath, 'app.json')).existsSync();
  } catch (_) {
    return false;
  }
}

/// 在已注册同步文件夹中查找指向该路径的应用
Folder? findRegisteredApp(List<Folder> folders, String absolutePath) {
  final want = normalizeFsPath(absolutePath);
  for (final f in folders) {
    if (!f.isApp) continue;
    if (normalizeFsPath(f.path) == want) return f;
  }
  return null;
}

/// 打开应用：优先用已注册 Folder，否则直接用路径
void openAppAtPath(
  BuildContext context, {
  required String absolutePath,
  String? title,
  Folder? folder,
}) {
  final f = folder;
  if (f != null && f.isApp && f.path.isNotEmpty) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AppRunnerPage(appPath: f.path, title: f.name),
      ),
    );
    return;
  }
  if (absolutePath.isEmpty || !isAppDirectory(absolutePath)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('不是有效的应用目录')),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AppRunnerPage(
        appPath: absolutePath,
        title: title ?? p.basename(absolutePath),
      ),
    ),
  );
}
