import 'dart:io';

/// 拼接 Syncthing 文件夹根路径与相对文件路径
String joinLocalFilePath(String folderPath, String relativePath) {
  final base = folderPath.replaceAll(RegExp(r'[/\\]+$'), '');
  final rel = relativePath
      .replaceAll('\\', Platform.pathSeparator)
      .replaceAll('/', Platform.pathSeparator);
  return '$base${Platform.pathSeparator}$rel';
}
