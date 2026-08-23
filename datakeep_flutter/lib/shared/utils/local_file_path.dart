import 'dart:io';

/// 拼接 Syncthing 文件夹根路径与相对文件路径
String joinLocalFilePath(String folderPath, String relativePath) {
  final base = folderPath.replaceAll(RegExp(r'[/\\]+$'), '');
  final rel = relativePath
      .replaceAll('\\', Platform.pathSeparator)
      .replaceAll('/', Platform.pathSeparator);
  return '$base${Platform.pathSeparator}$rel';
}

/// 本机已同步文件绝对路径；非本机或文件不存在时返回 null。
String? resolveLocalSyncedFilePath({
  required bool isLocalDevice,
  required String folderPath,
  required String relativePath,
}) {
  if (!isLocalDevice || folderPath.isEmpty || relativePath.isEmpty) {
    return null;
  }
  final path = joinLocalFilePath(folderPath, relativePath);
  if (File(path).existsSync()) return path;
  return null;
}
