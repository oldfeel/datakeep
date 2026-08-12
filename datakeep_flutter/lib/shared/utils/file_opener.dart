import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/services/api_service.dart';
import '../../features/folders/screens/audio_preview_screen.dart';
import '../../features/folders/screens/image_preview_screen.dart';
import '../../features/folders/screens/pdf_preview_screen.dart';
import '../../features/folders/screens/text_preview_screen.dart';
import '../../features/folders/screens/video_preview_screen.dart';
import 'file_types.dart';
import 'local_file_path.dart';
import 'open_system_file.dart';
import 'preview_limits.dart';

/// 统一按扩展名分发预览（桌面 / 移动共用逻辑）
Future<void> openFilePreview(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
  List<String>? siblingImagePaths,
}) async {
  final fileName = filePath.split('/').last;

  if (FileTypes.isImage(filePath)) {
    await _openImage(
      context,
      folderId: folderId,
      folderPath: folderPath,
      filePath: filePath,
      deviceId: deviceId,
      siblingImagePaths: siblingImagePaths,
    );
    return;
  }

  if (FileTypes.isVideo(filePath) || FileTypes.isAudio(filePath)) {
    await _openMedia(
      context,
      folderId: folderId,
      folderPath: folderPath,
      filePath: filePath,
      deviceId: deviceId,
    );
    return;
  }

  if (FileTypes.isText(filePath)) {
    await _openText(
      context,
      folderId: folderId,
      folderPath: folderPath,
      filePath: filePath,
      deviceId: deviceId,
    );
    return;
  }

  if (FileTypes.isPdf(filePath)) {
    await _openPdf(
      context,
      folderId: folderId,
      folderPath: folderPath,
      filePath: filePath,
      deviceId: deviceId,
    );
    return;
  }

  // 未知类型：下载到临时文件后系统打开
  await _openWithSystem(
    context,
    folderId: folderId,
    folderPath: folderPath,
    filePath: filePath,
    deviceId: deviceId,
    title: fileName,
  );
}

Future<String?> _resolveLocalOrDownload(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
  void Function(int received, int? total)? onProgress,
}) async {
  if (folderPath.isNotEmpty) {
    final localPath = joinLocalFilePath(folderPath, filePath);
    final f = File(localPath);
    if (await f.exists()) {
      final size = await f.length();
      if (size > kMaxPreviewBytes) {
        throw PreviewTooLargeException(size);
      }
      return localPath;
    }
  }
  final result = await ApiService.previewFileToTemp(
    folderId,
    filePath,
    deviceId: deviceId,
    onProgress: onProgress,
  );
  return result.path;
}

Future<void> _openImage(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
  List<String>? siblingImagePaths,
}) async {
  final images = siblingImagePaths ??
      (FileTypes.isImage(filePath) ? [filePath] : <String>[]);
  final initialIndex = images.indexOf(filePath).clamp(0, images.isEmpty ? 0 : images.length - 1);

  // 先解析当前图路径
  String? currentLocal;
  PreviewDownloadResult? temp;
  try {
    if (folderPath.isNotEmpty) {
      final p = joinLocalFilePath(folderPath, filePath);
      if (await File(p).exists()) currentLocal = p;
    }
    if (currentLocal == null) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      temp = await ApiService.previewFileToTemp(
        folderId,
        filePath,
        deviceId: deviceId,
      );
      currentLocal = temp.path;
      if (context.mounted) Navigator.of(context).pop();
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片加载失败: $e'), backgroundColor: Colors.red),
      );
    }
    return;
  }

  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ImagePreviewScreen(
        title: filePath.split('/').last,
        filePath: currentLocal,
        imagePaths: images,
        initialIndex: images.isEmpty ? 0 : initialIndex,
        folderId: folderId,
        folderPath: folderPath,
        deviceId: deviceId,
      ),
    ),
  );
  await temp?.cleanup();
}

Future<void> _openMedia(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
}) async {
  final fileName = filePath.split('/').last;
  final isVideo = FileTypes.isVideo(filePath);
  PreviewDownloadResult? temp;

  try {
    String? playPath;
    if (folderPath.isNotEmpty) {
      final localPath = joinLocalFilePath(folderPath, filePath);
      if (await File(localPath).exists()) playPath = localPath;
    }

    if (playPath == null) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      temp = await ApiService.previewFileToTemp(
        folderId,
        filePath,
        deviceId: deviceId,
      );
      playPath = temp.path;
      if (context.mounted) Navigator.of(context).pop();
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isVideo
            ? VideoPreviewScreen(title: fileName, filePath: playPath!)
            : AudioPreviewScreen(title: fileName, filePath: playPath!),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${isVideo ? '视频' : '音频'}加载失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    await temp?.cleanup();
  }
}

Future<void> _openText(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
}) async {
  PreviewDownloadResult? temp;
  try {
    String? path;
    if (folderPath.isNotEmpty) {
      final local = joinLocalFilePath(folderPath, filePath);
      if (await File(local).exists()) path = local;
    }
    if (path == null) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      temp = await ApiService.previewFileToTemp(
        folderId,
        filePath,
        deviceId: deviceId,
      );
      path = temp.path;
      if (context.mounted) Navigator.of(context).pop();
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TextPreviewScreen(
          title: filePath.split('/').last,
          filePath: path!,
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文本加载失败: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    await temp?.cleanup();
  }
}

Future<void> _openPdf(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
}) async {
  PreviewDownloadResult? temp;
  try {
    String? path;
    if (folderPath.isNotEmpty) {
      final local = joinLocalFilePath(folderPath, filePath);
      if (await File(local).exists()) {
        final size = await File(local).length();
        if (size > kMaxPreviewBytes) {
          // 大 PDF：系统打开
          final err = await openSystemFile(local);
          if (err != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(err), backgroundColor: Colors.red),
            );
          }
          return;
        }
        path = local;
      }
    }
    if (path == null) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      temp = await ApiService.previewFileToTemp(
        folderId,
        filePath,
        deviceId: deviceId,
      );
      path = temp.path;
      if (context.mounted) Navigator.of(context).pop();
    }
    if (!context.mounted) return;

    // 移动端优先系统打开更稳；桌面用内嵌
    if (Platform.isAndroid || Platform.isIOS) {
      final err = await openSystemFile(path);
      if (err != null && context.mounted) {
        // 回退内嵌
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfPreviewScreen(
              title: filePath.split('/').last,
              filePath: path!,
            ),
          ),
        );
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            title: filePath.split('/').last,
            filePath: path!,
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF 打开失败: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    // 系统打开后暂不立刻删临时文件；延迟清理由 OS 回收
    // 内嵌预览页关闭后由调用方不删也可（temp 留在 /tmp）
  }
}

Future<void> _openWithSystem(
  BuildContext context, {
  required String folderId,
  required String folderPath,
  required String filePath,
  String? deviceId,
  required String title,
}) async {
  try {
    final path = await _resolveLocalOrDownload(
      context,
      folderId: folderId,
      folderPath: folderPath,
      filePath: filePath,
      deviceId: deviceId,
    );
    if (path == null) return;
    final err = await openSystemFile(path);
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$title\n$err\n或文件过大无法应用内预览'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  } on PreviewTooLargeException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.orange),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开失败: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
