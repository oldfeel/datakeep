import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 内置视频播放器（media_kit），直接播放本地文件
class VideoPreview extends StatefulWidget {
  final String filePath;

  const VideoPreview({super.key, required this.filePath});

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  late final Player _player = Player();
  late final VideoController _controller;
  String? _error;
  bool _opening = true;

  bool get _isDesktop => !kIsWeb &&
      (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    // Linux 上 EGL 常不可用；关闭硬解，走软件渲染更稳定
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !Platform.isLinux,
        hwdec: Platform.isLinux ? 'no' : 'auto',
      ),
    );

    if (!File(widget.filePath).existsSync()) {
      _error = '文件不存在';
      _opening = false;
      return;
    }

    // Video 必须先挂载到 Widget 树，再 open；否则 Linux 纹理会卡在 1x1 黑屏
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFile());
  }

  Future<void> _openFile() async {
    try {
      await _player.open(Media(Uri.file(widget.filePath).toString()));
      await _player.play();
      if (mounted) setState(() => _opening = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _opening = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('播放失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(
              controller: _controller,
              controls: _isDesktop ? MaterialDesktopVideoControls : AdaptiveVideoControls,
              fill: Colors.black,
              fit: BoxFit.contain,
            ),
            if (_opening)
              const ColoredBox(
                color: Colors.black87,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
