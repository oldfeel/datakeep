import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/widgets/share_to_cloud_sheet.dart';
import '../../../shared/widgets/video_preview.dart';

/// 移动端沉浸全屏视频播放页；pop 时回传 [VideoPlayResult]
class VideoPreviewScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final double startPositionSec;
  final String? subtitlePath;

  const VideoPreviewScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.startPositionSec = 0,
    this.subtitlePath,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  bool _showBar = true;
  final GlobalKey<VideoPreviewState> _previewKey = GlobalKey<VideoPreviewState>();
  VideoPlayResult _last = const VideoPlayResult(positionSec: 0, completed: false);

  void _popWithResult() {
    final live = _previewKey.currentState?.currentResult();
    Navigator.of(context).pop(live ?? _last);
  }

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _popWithResult();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: _showBar
            ? AppBar(
                title: Text(widget.title, overflow: TextOverflow.ellipsis),
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _popWithResult,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: '分享到互联网',
                    onPressed: () => showShareToCloudSheet(
                      context,
                      localAbsolutePath: widget.filePath,
                    ),
                  ),
                ],
              )
            : null,
        body: GestureDetector(
          onTap: () => setState(() => _showBar = !_showBar),
          child: SizedBox.expand(
            child: VideoPreview(
              key: _previewKey,
              filePath: widget.filePath,
              startPositionSec: widget.startPositionSec,
              subtitlePath: widget.subtitlePath,
              onProgress: (r) => _last = r,
            ),
          ),
        ),
      ),
    );
  }
}
