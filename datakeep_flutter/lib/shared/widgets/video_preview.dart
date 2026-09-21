import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 播放结束时上报进度
class VideoPlayResult {
  final double positionSec;
  final bool completed;

  const VideoPlayResult({
    required this.positionSec,
    required this.completed,
  });
}

/// 内置视频播放器（media_kit），直接播放本地文件
class VideoPreview extends StatefulWidget {
  final String filePath;
  /// 续播起点（秒）
  final double startPositionSec;
  /// 外挂字幕本地绝对路径
  final String? subtitlePath;
  /// 进度变化回调（节流由父级决定）
  final ValueChanged<VideoPlayResult>? onProgress;

  const VideoPreview({
    super.key,
    required this.filePath,
    this.startPositionSec = 0,
    this.subtitlePath,
    this.onProgress,
  });

  @override
  State<VideoPreview> createState() => VideoPreviewState();
}

class VideoPreviewState extends State<VideoPreview> {
  late final Player _player = Player();
  late final VideoController _controller;
  String? _error;
  bool _opening = true;
  double _rate = 1.0;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _completedSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _completed = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  static const _rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  VideoPlayResult currentResult() {
    final pos = _position.inMilliseconds / 1000.0;
    final dur = _duration.inMilliseconds / 1000.0;
    final nearEnd = dur > 0 && pos >= dur - 2.0;
    return VideoPlayResult(
      positionSec: pos.clamp(0, double.infinity),
      completed: _completed || nearEnd,
    );
  }

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
    _rateSub = _player.stream.rate.listen((r) {
      if (mounted) setState(() => _rate = r);
    });
    _posSub = _player.stream.position.listen((p) {
      _position = p;
      widget.onProgress?.call(currentResult());
    });
    _player.stream.duration.listen((d) {
      _duration = d;
    });
    _completedSub = _player.stream.completed.listen((c) {
      if (c) {
        _completed = true;
        widget.onProgress?.call(currentResult());
      }
    });

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
      final sub = widget.subtitlePath;
      if (sub != null && sub.isNotEmpty && File(sub).existsSync()) {
        try {
          await _player.setSubtitleTrack(SubtitleTrack.uri(Uri.file(sub).toString()));
        } catch (e) {
          debugPrint('[VideoPreview] 加载字幕失败: $e');
        }
      }
      final start = widget.startPositionSec;
      if (start > 1) {
        try {
          await _player.seek(Duration(milliseconds: (start * 1000).round()));
        } catch (e) {
          debugPrint('[VideoPreview] seek 失败: $e');
        }
      }
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

  Future<void> _setRate(double rate) async {
    try {
      await _player.setRate(rate);
      if (mounted) setState(() => _rate = rate);
    } catch (e) {
      debugPrint('[VideoPreview] setRate 失败: $e');
    }
  }

  /// 用根 Navigator 弹出菜单，避免控件栏自动隐藏时 dispose 掉 PopupMenuButton 导致 onSelected 不触发
  Future<void> _pickRate(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final selected = await showMenu<double>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy - 8,
        origin.dx + size.width,
        origin.dy,
      ),
      items: [
        for (final r in _rates)
          PopupMenuItem<double>(
            value: r,
            child: Text(
              _rateLabel(r),
              style: TextStyle(
                fontWeight:
                    (r - _rate).abs() < 0.001 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
      ],
    );
    if (selected != null) await _setRate(selected);
  }

  static String _rateLabel(double rate) {
    if (rate == rate.roundToDouble()) {
      return '${rate.toStringAsFixed(0)}.0x';
    }
    return '${rate}x';
  }

  @override
  void dispose() {
    _rateSub?.cancel();
    _posSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  List<Widget> get _desktopBottomBar => [
        const MaterialDesktopSkipPreviousButton(),
        const MaterialDesktopPlayOrPauseButton(),
        const MaterialDesktopSkipNextButton(),
        const MaterialDesktopVolumeButton(),
        const MaterialDesktopPositionIndicator(),
        const Spacer(),
        _RateChip(label: _rateLabel(_rate), onPressed: _pickRate),
        const MaterialDesktopFullscreenButton(),
      ];

  List<Widget> get _mobileBottomBar => [
        const MaterialPositionIndicator(),
        const Spacer(),
        _RateChip(label: _rateLabel(_rate), onPressed: _pickRate),
        const MaterialFullscreenButton(),
      ];

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('播放失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final desktopTheme = MaterialDesktopVideoControlsThemeData(
      bottomButtonBar: _desktopBottomBar,
    );
    final mobileTheme = MaterialVideoControlsThemeData(
      bottomButtonBar: _mobileBottomBar,
      speedUpOnLongPress: true,
      speedUpFactor: 2.0,
    );

    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MaterialDesktopVideoControlsTheme(
              normal: desktopTheme,
              fullscreen: desktopTheme,
              child: MaterialVideoControlsTheme(
                normal: mobileTheme,
                fullscreen: mobileTheme,
                child: Video(
                  controller: _controller,
                  controls: _isDesktop
                      ? MaterialDesktopVideoControls
                      : AdaptiveVideoControls,
                  fill: Colors.black,
                  fit: BoxFit.contain,
                ),
              ),
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

class _RateChip extends StatelessWidget {
  final String label;
  final Future<void> Function(BuildContext buttonContext) onPressed;

  const _RateChip({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '播放倍速',
      child: TextButton(
        onPressed: () => onPressed(context),
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
