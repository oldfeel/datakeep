import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../shared/widgets/share_to_cloud_sheet.dart';
import '../../../shared/widgets/video_preview.dart';

/// 全屏视频播放页；支持剧集连播 / 收藏；pop 时回传 [VideoPlayResult]
class VideoPreviewScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final double startPositionSec;
  final String? subtitlePath;
  /// 剧集列表（含当前集）；为空则单集
  final List<VideoEpisode> episodes;
  final int initialIndex;
  final bool autoNext;
  /// data/ 根目录，用于写回 meta
  final String? dataRoot;

  const VideoPreviewScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.startPositionSec = 0,
    this.subtitlePath,
    this.episodes = const [],
    this.initialIndex = 0,
    this.autoNext = true,
    this.dataRoot,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  final GlobalKey<VideoPreviewState> _previewKey = GlobalKey<VideoPreviewState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late List<VideoEpisode> _episodes;
  late int _index;
  VideoPlayResult _last = const VideoPlayResult(positionSec: 0, completed: false);
  bool _switching = false;

  VideoEpisode get _current {
    if (_episodes.isEmpty) {
      return VideoEpisode(
        filePath: widget.filePath,
        title: widget.title,
        entryDir: '',
        startPositionSec: widget.startPositionSec,
        subtitlePath: widget.subtitlePath,
      );
    }
    return _episodes[_index.clamp(0, _episodes.length - 1)];
  }

  bool get _hasSeries => _episodes.length > 1;
  bool get _hasPrev => _hasSeries;
  bool get _hasNext => _hasSeries;

  int _loopIndex(int nextIndex) {
    final n = _episodes.length;
    if (n <= 0) return 0;
    return ((nextIndex % n) + n) % n;
  }

  @override
  void initState() {
    super.initState();
    if (widget.episodes.isEmpty) {
      _episodes = [
        VideoEpisode(
          filePath: widget.filePath,
          title: widget.title,
          entryDir: '',
          startPositionSec: widget.startPositionSec,
          subtitlePath: widget.subtitlePath,
        ),
      ];
      _index = 0;
    } else {
      _episodes = List<VideoEpisode>.from(widget.episodes);
      _index = widget.initialIndex.clamp(0, _episodes.length - 1);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _persistProgress({bool completed = false}) async {
    final ep = _current;
    final root = widget.dataRoot;
    if (root == null || root.isEmpty || ep.entryDir.isEmpty) return;
    final live = _previewKey.currentState?.currentResult();
    var pos = live?.positionSec ?? _last.positionSec;
    if (completed) pos = 0;
    await patchVideoEntryMeta(root, ep.entryDir, {
      'positionSec': pos.round(),
    });
  }

  Future<void> _popWithResult() async {
    await _persistProgress(completed: _last.completed);
    final live = _previewKey.currentState?.currentResult(
      entryDir: _current.entryDir,
      favorite: _current.favorite,
    );
    if (!mounted) return;
    Navigator.of(context).pop(live ?? _last);
  }

  Future<void> _switchTo(int nextIndex, {bool fromCompleted = false}) async {
    if (_switching) return;
    if (_episodes.isEmpty) return;
    final target = _loopIndex(nextIndex);
    if (target == _index && !fromCompleted) return;
    _switching = true;
    try {
      await _persistProgress(completed: fromCompleted);
      setState(() {
        _index = target;
      });
      final ep = _current;
      final playEp = fromCompleted
          ? VideoEpisode(
              filePath: ep.filePath,
              title: ep.title,
              entryDir: ep.entryDir,
              startPositionSec: 0,
              subtitlePath: ep.subtitlePath,
              favorite: ep.favorite,
            )
          : ep;
      await _previewKey.currentState?.jumpTo(playEp);
      if (mounted) {
        setState(() {
          _last = VideoPlayResult(
            positionSec: playEp.startPositionSec,
            completed: false,
            entryDir: ep.entryDir,
            favorite: ep.favorite,
          );
        });
      }
    } finally {
      _switching = false;
    }
  }

  Future<void> _onCompleted() async {
    await _persistProgress(completed: true);
    if (!widget.autoNext || !_hasSeries) return;
    await _switchTo(_index + 1, fromCompleted: true);
  }

  Future<void> _toggleFavorite() async {
    final ep = _current;
    final root = widget.dataRoot;
    if (root == null || ep.entryDir.isEmpty) return;
    final next = !ep.favorite;
    await patchVideoEntryMeta(root, ep.entryDir, {'favorite': next});
    setState(() {
      _episodes[_index] = VideoEpisode(
        filePath: ep.filePath,
        title: ep.title,
        entryDir: ep.entryDir,
        startPositionSec: ep.startPositionSec,
        subtitlePath: ep.subtitlePath,
        favorite: next,
      );
      _last = VideoPlayResult(
        positionSec: _last.positionSec,
        completed: _last.completed,
        entryDir: ep.entryDir,
        favorite: next,
      );
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(next ? '已加入收藏' : '已取消收藏'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Widget _episodeListPanel({required VoidCallback onClose}) {
    return Material(
      color: Colors.grey.shade900,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(
                        '剧集（${_episodes.length}）',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white12),
                Expanded(
                  child: ListView.builder(
                    itemCount: _episodes.length,
                    itemBuilder: (_, i) {
                      final ep = _episodes[i];
                      final selected = i == _index;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: Colors.white12,
                        leading: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: selected
                                ? Colors.lightBlueAccent
                                : Colors.white54,
                          ),
                        ),
                        title: Text(
                          ep.title,
                          style: TextStyle(
                            color: selected
                                ? Colors.lightBlueAccent
                                : Colors.white,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: ep.favorite
                            ? const Icon(Icons.favorite,
                                color: Colors.redAccent, size: 18)
                            : null,
                        onTap: () {
                          onClose();
                          if (i != _index) _switchTo(i);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            // 与控制栏剧集按钮同屏位置（贴底右侧），鼠标不用挪即可关闭
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  tooltip: '关闭剧集列表',
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.playlist_play),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episodeDrawer() {
    return Drawer(
      backgroundColor: Colors.grey.shade900,
      child: _episodeListPanel(
        onClose: () {
          final s = _scaffoldKey.currentState;
          if (s != null && s.isEndDrawerOpen) {
            s.closeEndDrawer();
          }
        },
      ),
    );
  }

  /// media_kit 全屏是独立路由；在其 Navigator 上弹侧栏，避免 maybePop 误关全屏
  Future<void> _showEpisodeOverlay(BuildContext buttonContext) async {
    final width = MediaQuery.sizeOf(buttonContext).width;
    final panelW = width < 720 ? width * 0.72 : 360.0;
    await showGeneralDialog<void>(
      context: buttonContext,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierLabel: '关闭剧集列表',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, anim, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelW,
            height: double.infinity,
            child: _episodeListPanel(
              onClose: () => Navigator.of(ctx).pop(),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        final offset = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic));
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  void _toggleEpisodeDrawer(BuildContext buttonContext) {
    // 全屏路由内：侧栏 overlay，绝不 exitFullscreen / maybePop 全屏页
    if (isFullscreen(buttonContext)) {
      _showEpisodeOverlay(buttonContext);
      return;
    }
    final s = _scaffoldKey.currentState;
    if (s == null) return;
    if (s.isEndDrawerOpen) {
      s.closeEndDrawer();
    } else {
      s.openEndDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ep = _current;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithResult();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        // 注意：drawer 打开期间不要因 setState 重建 endDrawer，
        // 否则会触发 InheritedWidget `_dependents.isEmpty` 断言崩溃。
        endDrawer: _hasSeries ? _episodeDrawer() : null,
        appBar: AppBar(
          title: Text(ep.title, overflow: TextOverflow.ellipsis),
          backgroundColor: Colors.black54,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _popWithResult,
          ),
          actions: [
            if (ep.entryDir.isNotEmpty)
              IconButton(
                icon: Icon(
                  ep.favorite ? Icons.favorite : Icons.favorite_border,
                  color: ep.favorite ? Colors.redAccent : null,
                ),
                tooltip: ep.favorite ? '取消收藏' : '收藏',
                onPressed: _toggleFavorite,
              ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: '分享到互联网',
              onPressed: () => showShareToCloudSheet(
                context,
                localAbsolutePath: ep.filePath,
              ),
            ),
          ],
        ),
        // 顶栏常驻，避免与 media_kit 控制条自动隐藏抢状态
        body: VideoPreview(
          key: _previewKey,
          filePath: ep.filePath,
          startPositionSec: ep.startPositionSec,
          subtitlePath: ep.subtitlePath,
          showEpisodeNav: _hasSeries,
          hasPrevEpisode: _hasPrev,
          hasNextEpisode: _hasNext,
          onPrevEpisode: () => _switchTo(_index - 1),
          onNextEpisode: () => _switchTo(_index + 1),
          showPlaylistButton: _hasSeries,
          onPlaylist: _toggleEpisodeDrawer,
          onProgress: (r) => _last = VideoPlayResult(
            positionSec: r.positionSec,
            completed: r.completed,
            entryDir: ep.entryDir,
            favorite: ep.favorite,
          ),
          onCompleted: () {
            _onCompleted();
          },
        ),
      ),
    );
  }
}
