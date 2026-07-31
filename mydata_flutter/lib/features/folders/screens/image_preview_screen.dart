import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/local_file_path.dart';
import '../../../shared/widgets/share_to_cloud_sheet.dart';

/// 全屏图片预览：双击缩放、单击显隐工具栏、左右滑邻图
class ImagePreviewScreen extends StatefulWidget {
  final String title;
  final String? filePath;
  final List<String> imagePaths;
  final int initialIndex;
  final String? folderId;
  final String? folderPath;
  final String? deviceId;

  const ImagePreviewScreen({
    super.key,
    required this.title,
    this.filePath,
    this.imagePaths = const [],
    this.initialIndex = 0,
    this.folderId,
    this.folderPath,
    this.deviceId,
  });

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  late PageController _pageController;
  late int _index;
  bool _showAppBar = true;
  final Map<int, String> _resolvedPaths = {};
  final Map<int, String> _tempDirs = {};
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  List<String> get _paths {
    if (widget.imagePaths.isNotEmpty) return widget.imagePaths;
    if (widget.filePath != null) return [widget.filePath!];
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _paths.isEmpty ? 0 : _paths.length - 1);
    _pageController = PageController(initialPage: _index);
    if (widget.filePath != null) {
      _resolvedPaths[_index] = widget.filePath!;
    }
    _ensureResolved(_index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transform.dispose();
    for (final dir in _tempDirs.values) {
      try {
        Directory(dir).deleteSync(recursive: true);
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _ensureResolved(int i) async {
    if (_resolvedPaths.containsKey(i)) return;
    if (i < 0 || i >= _paths.length) return;
    final rel = _paths[i];

    // 若传入的是绝对路径（单图旧用法）
    if (rel.startsWith('/') || (rel.length > 2 && rel[1] == ':')) {
      if (await File(rel).exists()) {
        if (mounted) setState(() => _resolvedPaths[i] = rel);
        return;
      }
    }

    final folderPath = widget.folderPath ?? '';
    if (folderPath.isNotEmpty) {
      final local = joinLocalFilePath(folderPath, rel);
      if (await File(local).exists()) {
        if (mounted) setState(() => _resolvedPaths[i] = local);
        return;
      }
    }

    final folderId = widget.folderId;
    if (folderId == null) return;
    try {
      final result = await ApiService.previewFileToTemp(
        folderId,
        rel,
        deviceId: widget.deviceId,
      );
      if (!mounted) {
        await result.cleanup();
        return;
      }
      setState(() {
        _resolvedPaths[i] = result.path;
        _tempDirs[i] = result.tempDirPath;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onDoubleTap() {
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (scale > 1.1) {
      _transform.value = Matrix4.identity();
    } else {
      final pos = _doubleTapDetails?.localPosition ?? Offset.zero;
      _transform.value = Matrix4.identity()
        ..translateByDouble(-pos.dx * 1.5, -pos.dy * 1.5, 0, 1)
        ..scaleByDouble(2.5, 2.5, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _paths.isEmpty
        ? widget.title
        : _paths[_index].split('/').last;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showAppBar
          ? AppBar(
              title: Text(title, overflow: TextOverflow.ellipsis),
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: '分享到互联网',
                  onPressed: () {
                    final abs = _resolvedPaths[_index];
                    final rel = _paths.isEmpty ? null : _paths[_index];
                    showShareToCloudSheet(
                      context,
                      folderPath: widget.folderPath ?? '',
                      relativePath: rel ?? '',
                      localAbsolutePath: abs,
                    );
                  },
                ),
                if (_paths.length > 1)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${_index + 1}/${_paths.length}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: _paths.isEmpty
          ? const Center(child: Text('无图片', style: TextStyle(color: Colors.white)))
          : PageView.builder(
              controller: _pageController,
              itemCount: _paths.length,
              onPageChanged: (i) {
                setState(() {
                  _index = i;
                  _transform.value = Matrix4.identity();
                });
                _ensureResolved(i);
                if (i + 1 < _paths.length) _ensureResolved(i + 1);
                if (i - 1 >= 0) _ensureResolved(i - 1);
              },
              itemBuilder: (context, i) {
                final path = _resolvedPaths[i];
                if (path == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return GestureDetector(
                  onTap: () => setState(() => _showAppBar = !_showAppBar),
                  onDoubleTapDown: (d) => _doubleTapDetails = d,
                  onDoubleTap: _onDoubleTap,
                  child: InteractiveViewer(
                    transformationController: i == _index ? _transform : null,
                    minScale: 0.5,
                    maxScale: 5,
                    child: Center(
                      child: Image.file(File(path), fit: BoxFit.contain),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// 桌面真全屏图片 overlay
Future<void> showDesktopImageFullscreen(
  BuildContext context, {
  required String filePath,
  List<String> siblingPaths = const [],
  int initialIndex = 0,
}) async {
  await showDialog(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false,
    builder: (ctx) {
      return Shortcuts(
        shortcuts: {
          LogicalKeySet(LogicalKeyboardKey.escape): const _DismissIntent(),
        },
        child: Actions(
          actions: {
            _DismissIntent: CallbackAction<_DismissIntent>(
              onInvoke: (_) {
                Navigator.of(ctx).pop();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: ImagePreviewScreen(
              title: filePath.split('/').last,
              filePath: filePath,
              imagePaths: siblingPaths.isEmpty ? [filePath] : siblingPaths,
              initialIndex: initialIndex,
            ),
          ),
        ),
      );
    },
  );
}

class _DismissIntent extends Intent {
  const _DismissIntent();
}
