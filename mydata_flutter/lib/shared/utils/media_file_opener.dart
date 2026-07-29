import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../features/folders/screens/audio_preview_screen.dart';
import '../../features/folders/screens/video_preview_screen.dart';
import 'file_types.dart';
import 'local_file_path.dart';

/// 打开视频/音频预览（优先本地 Syncthing 路径，否则 API 下载到临时目录）
Future<void> openMediaPreview(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
}) async {
  final fileName = filePath.split('/').last;
  final isVideo = FileTypes.isVideo(filePath);

  if (folderPath.isNotEmpty) {
    final localPath = joinLocalFilePath(folderPath, filePath);
    if (await File(localPath).exists()) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => isVideo
              ? VideoPreviewScreen(title: fileName, filePath: localPath)
              : AudioPreviewScreen(title: fileName, filePath: localPath),
        ),
      );
      return;
    }
  }

  if (!context.mounted) return;
  var loadingShown = false;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  loadingShown = true;

  try {
    final response = await ApiService.previewFile(
      folderId,
      filePath,
      deviceId: deviceId,
    );
    if (!context.mounted) return;
    if (loadingShown) Navigator.of(context).pop();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final tempDir = await Directory.systemTemp.createTemp('mydata_media_');
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(response.bodyBytes);

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isVideo
            ? VideoPreviewScreen(title: fileName, filePath: tempFile.path)
            : AudioPreviewScreen(title: fileName, filePath: tempFile.path),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      if (loadingShown) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isVideo ? '视频' : '音频'}加载失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
