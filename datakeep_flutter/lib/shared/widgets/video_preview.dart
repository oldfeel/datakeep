import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

/// 播放结束时上报进度
class VideoPlayResult {
  final double positionSec;
  final bool completed;
  final String? entryDir;
  final bool? favorite;

  const VideoPlayResult({
    required this.positionSec,
    required this.completed,
    this.entryDir,
    this.favorite,
  });
}

/// 播放列表中的一集
class VideoEpisode {
  final String filePath;
  final String title;
  final String entryDir;
  final double startPositionSec;
  final String? subtitlePath;
  final bool favorite;

  const VideoEpisode({
    required this.filePath,
    required this.title,
    required this.entryDir,
    this.startPositionSec = 0,
    this.subtitlePath,
    this.favorite = false,
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
  /// 播完回调（用于连播）
  final VoidCallback? onCompleted;
  /// 剧集：上一集 / 下一集（放在播放按钮两侧）
  final bool showEpisodeNav;
  final bool hasPrevEpisode;
  final bool hasNextEpisode;
  final VoidCallback? onPrevEpisode;
  final VoidCallback? onNextEpisode;
  /// 控制栏全屏右侧：剧集列表（传入按钮 context，全屏路由内可正确弹层）
  final bool showPlaylistButton;
  final void Function(BuildContext buttonContext)? onPlaylist;

  const VideoPreview({
    super.key,
    required this.filePath,
    this.startPositionSec = 0,
    this.subtitlePath,
    this.onProgress,
    this.onCompleted,
    this.showEpisodeNav = false,
    this.hasPrevEpisode = false,
    this.hasNextEpisode = false,
    this.onPrevEpisode,
    this.onNextEpisode,
    this.showPlaylistButton = false,
    this.onPlaylist,
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
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _completedSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _completed = false;
  bool _didSeek = false;
  double _pendingStart = 0;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  static const _rates = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  VideoPlayResult currentResult({String? entryDir, bool? favorite}) {
    final pos = _position.inMilliseconds / 1000.0;
    final dur = _duration.inMilliseconds / 1000.0;
    final nearEnd = dur > 0 && pos >= dur - 2.0;
    return VideoPlayResult(
      positionSec: pos.clamp(0, double.infinity),
      completed: _completed || nearEnd,
      entryDir: entryDir,
      favorite: favorite,
    );
  }

  Future<void> jumpTo(VideoEpisode ep) async {
    setState(() {
      _opening = true;
      _error = null;
      _completed = false;
      _didSeek = false;
      _pendingStart = ep.startPositionSec;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _openEpisode(ep);
  }

  @override
  void initState() {
    super.initState();
    _pendingStart = widget.startPositionSec;
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
    _durSub = _player.stream.duration.listen((d) {
      _duration = d;
      // 时长就绪后再 seek，避免 open 后立刻 seek 被重置
      if (!_didSeek && _pendingStart > 1 && d > Duration.zero) {
        _didSeek = true;
        unawaited(_seekStart(_pendingStart));
      }
    });
    _completedSub = _player.stream.completed.listen((c) {
      if (c) {
        _completed = true;
        widget.onProgress?.call(currentResult());
        widget.onCompleted?.call();
      }
    });

    if (!File(widget.filePath).existsSync()) {
      _error = '文件不存在';
      _opening = false;
      return;
    }

    // Video 必须先挂载到 Widget 树，再 open；否则 Linux 纹理会卡在 1x1 黑屏
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _openEpisode(
          VideoEpisode(
            filePath: widget.filePath,
            title: '',
            entryDir: '',
            startPositionSec: widget.startPositionSec,
            subtitlePath: widget.subtitlePath,
          ),
        ),
      );
    });
  }

  Future<void> _seekStart(double start) async {
    try {
      await _player.seek(Duration(milliseconds: (start * 1000).round()));
    } catch (e) {
      debugPrint('[VideoPreview] seek 失败: $e');
    }
  }

  Future<void> _openEpisode(VideoEpisode ep) async {
    try {
      if (!File(ep.filePath).existsSync()) {
        if (mounted) {
          setState(() {
            _error = '文件不存在';
            _opening = false;
          });
        }
        return;
      }
      final start = ep.startPositionSec > 1
          ? Duration(milliseconds: (ep.startPositionSec * 1000).round())
          : null;
      // Media.start 让 mpv 从指定位置起播；再用 duration 回调兜底 seek
      _pendingStart = ep.startPositionSec;
      _didSeek = start == null;
      await _player.open(
        Media(
          Uri.file(ep.filePath).toString(),
          start: start,
        ),
      );
      final sub = ep.subtitlePath;
      if (sub != null && sub.isNotEmpty && File(sub).existsSync()) {
        try {
          await _player.setSubtitleTrack(
            SubtitleTrack.uri(Uri.file(sub).toString()),
          );
        } catch (e) {
          debugPrint('[VideoPreview] 加载字幕失败: $e');
        }
      }
      await _player.play();
      if (start != null) {
        // 部分后端忽略 Media.start，延迟再 seek 一次
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!_didSeek || (_position.inMilliseconds / 1000.0) < 1) {
          _didSeek = true;
          await _seekStart(ep.startPositionSec);
        }
      }
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
    _durSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Widget get _playlistButton => Builder(
        builder: (btnCtx) => IconButton(
          onPressed: widget.onPlaylist == null
              ? null
              : () => widget.onPlaylist!(btnCtx),
          tooltip: '剧集列表',
          color: Colors.white,
          icon: const Icon(Icons.playlist_play),
        ),
      );

  /// 左右 Spacer 近似居中播放键（勿用 Expanded 嵌套 Row，易触发 media_kit 主题依赖异常）
  List<Widget> get _desktopBottomBar {
    final prev = widget.showEpisodeNav
        ? IconButton(
            onPressed: widget.hasPrevEpisode ? widget.onPrevEpisode : null,
            tooltip: '上一集',
            color: Colors.white,
            icon: const Icon(Icons.skip_previous),
          )
        : const MaterialDesktopSkipPreviousButton();
    final next = widget.showEpisodeNav
        ? IconButton(
            onPressed: widget.hasNextEpisode ? widget.onNextEpisode : null,
            tooltip: '下一集',
            color: Colors.white,
            icon: const Icon(Icons.skip_next),
          )
        : const MaterialDesktopSkipNextButton();
    return [
      const MaterialDesktopVolumeButton(),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      prev,
      const MaterialDesktopPlayOrPauseButton(),
      next,
      const Spacer(),
      _RateChip(label: _rateLabel(_rate), onPressed: _pickRate),
      const MaterialDesktopFullscreenButton(),
      if (widget.showPlaylistButton) _playlistButton,
    ];
  }

  List<Widget> get _mobileBottomBar {
    return [
      const MaterialPositionIndicator(),
      const Spacer(),
      if (widget.showEpisodeNav) ...[
        IconButton(
          onPressed: widget.hasPrevEpisode ? widget.onPrevEpisode : null,
          tooltip: '上一集',
          color: Colors.white,
          icon: const Icon(Icons.skip_previous),
        ),
        const MaterialPlayOrPauseButton(),
        IconButton(
          onPressed: widget.hasNextEpisode ? widget.onNextEpisode : null,
          tooltip: '下一集',
          color: Colors.white,
          icon: const Icon(Icons.skip_next),
        ),
        const SizedBox(width: 4),
      ] else
        const MaterialPlayOrPauseButton(),
      _RateChip(label: _rateLabel(_rate), onPressed: _pickRate),
      const MaterialFullscreenButton(),
      if (widget.showPlaylistButton) _playlistButton,
    ];
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

/// 写入条目 meta.json 的局部字段（收藏 / 进度）
Future<void> patchVideoEntryMeta(
  String dataRoot,
  String entryDir,
  Map<String, dynamic> patch,
) async {
  final dir = entryDir.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  if (dir.isEmpty || dir.contains('..')) return;
  final file = File(p.join(dataRoot, dir, 'meta.json'));
  if (!await file.exists()) return;
  try {
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    map.addAll(patch);
    map['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  } catch (e) {
    debugPrint('[VideoPreview] 写 meta 失败: $e');
  }
}
