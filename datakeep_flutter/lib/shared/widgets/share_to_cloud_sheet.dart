import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/utils/local_file_path.dart';

/// 系统分享本机文件（微信 / 邮件等）
Future<void> showShareToCloudSheet(
  BuildContext context, {
  String folderPath = '',
  String relativePath = '',
  String? localAbsolutePath,
}) async {
  var localPath = localAbsolutePath?.trim() ?? '';
  if (localPath.isEmpty) {
    localPath = folderPath.isEmpty
        ? relativePath
        : joinLocalFilePath(folderPath, relativePath);
  }

  if (localPath.isEmpty || !await File(localPath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件不在本机，请先同步或下载后再分享'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  try {
    final name = localPath.split(Platform.pathSeparator).last;
    await Share.shareXFiles(
      [XFile(localPath, name: name)],
      subject: name,
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('分享失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
