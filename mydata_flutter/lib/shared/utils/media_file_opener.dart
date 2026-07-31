import 'package:flutter/material.dart';
import 'file_opener.dart';

/// 打开视频/音频预览（委托统一 file_opener）
Future<void> openMediaPreview(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
}) async {
  await openFilePreview(
    context,
    folderId: folderId,
    folderPath: folderPath,
    filePath: filePath,
    deviceId: deviceId,
  );
}
