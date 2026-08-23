import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/thumbnail_service.dart';
import '../../desktop/widgets/file_icon.dart';
import '../utils/file_types.dart';

/// 文件列表缩略图：本机或对端图片/视频缩略图，其余显示类型图标。
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    super.key,
    this.localPath,
    this.deviceId,
    this.folderId,
    this.relativePath,
    this.fileModTime,
    this.fileSize,
    required this.fileName,
    this.isDir = false,
    this.isApp = false,
    this.size = 40,
    this.borderRadius = 6,
    this.circular = false,
    this.fit = BoxFit.contain,
  });

  final String? localPath;
  final String? deviceId;
  final String? folderId;
  final String? relativePath;
  final int? fileModTime;
  final int? fileSize;
  final String fileName;
  final bool isDir;
  final bool isApp;
  final double size;
  final double borderRadius;
  final bool circular;
  final BoxFit fit;

  bool get _isVideo =>
      FileTypes.isVideo(fileName) ||
      (localPath != null && FileTypes.isVideo(localPath!));

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  String? _thumbPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scheduleLoad();
  }

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localPath != widget.localPath ||
        oldWidget.fileName != widget.fileName ||
        oldWidget.deviceId != widget.deviceId ||
        oldWidget.folderId != widget.folderId ||
        oldWidget.relativePath != widget.relativePath ||
        oldWidget.fileModTime != widget.fileModTime ||
        oldWidget.fileSize != widget.fileSize) {
      _thumbPath = null;
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    if (widget.isDir || widget.isApp) return;
    if (!ThumbnailService.supportsFileName(widget.fileName)) return;

    _loading = true;
    final local = widget.localPath;
    Future<String?> task;
    if (local != null) {
      task = ThumbnailService.instance.thumbnailPath(local);
    } else if (widget.deviceId != null &&
        widget.folderId != null &&
        widget.relativePath != null) {
      task = ThumbnailService.instance.remoteThumbnailPath(
        deviceId: widget.deviceId!,
        folderId: widget.folderId!,
        relativePath: widget.relativePath!,
        modTime: widget.fileModTime,
        size: widget.fileSize,
      );
    } else {
      _loading = false;
      return;
    }

    task.then((thumb) {
      if (!mounted) return;
      setState(() {
        _thumbPath = thumb;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.circular ? widget.size / 2 : widget.borderRadius;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );

    Widget child;
    if (_thumbPath != null) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(_thumbPath!),
            width: widget.size,
            height: widget.size,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _icon(),
          ),
          if (widget._isVideo)
            Center(
              child: Icon(
                Icons.play_circle_fill,
                size: widget.size * 0.45,
                color: Colors.white.withValues(alpha: 0.92),
                shadows: const [
                  Shadow(blurRadius: 4, color: Colors.black54),
                ],
              ),
            ),
        ],
      );
    } else if (_loading && ThumbnailService.supportsFileName(widget.fileName)) {
      child = SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else {
      child = _icon();
    }

    return Material(
      color: widget.isDir || widget.isApp
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: child,
      ),
    );
  }

  Widget _icon() {
    final iconSize = widget.size * 0.5;
    return Center(
      child: Icon(
        widget.isApp
            ? Icons.apps
            : getFileIcon(widget.fileName, isDir: widget.isDir),
        size: iconSize,
        color: widget.isApp
            ? Theme.of(context).colorScheme.tertiary
            : getFileIconColor(widget.fileName, isDir: widget.isDir),
      ),
    );
  }
}
