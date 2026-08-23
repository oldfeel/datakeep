import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/thumbnail_service.dart';
import '../../desktop/widgets/file_icon.dart';
import '../utils/file_types.dart';

/// 文件列表缩略图：本机图片走缓存缩略图，其余显示类型图标。
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    super.key,
    this.localPath,
    required this.fileName,
    this.isDir = false,
    this.isApp = false,
    this.size = 40,
    this.borderRadius = 6,
    this.circular = false,
    this.fit = BoxFit.contain,
  });

  final String? localPath;
  final String fileName;
  final bool isDir;
  final bool isApp;
  final double size;
  final double borderRadius;
  final bool circular;
  final BoxFit fit;

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
        oldWidget.fileName != widget.fileName) {
      _thumbPath = null;
      _scheduleLoad();
    }
  }

  void _scheduleLoad() {
    final path = widget.localPath;
    if (path == null ||
        widget.isDir ||
        widget.isApp ||
        !FileTypes.isImage(path)) {
      return;
    }
    _loading = true;
    ThumbnailService.instance.imageThumbnailPath(path).then((thumb) {
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
      child = Image.file(
        File(_thumbPath!),
        width: widget.size,
        height: widget.size,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _icon(),
      );
    } else if (_loading &&
        widget.localPath != null &&
        FileTypes.isImage(widget.localPath!)) {
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
