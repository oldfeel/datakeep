import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../shared/widgets/share_to_cloud_sheet.dart';
import '../../../shared/widgets/video_preview.dart';

/// 移动端沉浸全屏视频播放页
class VideoPreviewScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const VideoPreviewScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<VideoPreviewScreen> createState() => _VideoPreviewScreenState();
}

class _VideoPreviewScreenState extends State<VideoPreviewScreen> {
  bool _showBar = true;

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
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _showBar
          ? AppBar(
              title: Text(widget.title, overflow: TextOverflow.ellipsis),
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
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
          child: VideoPreview(filePath: widget.filePath),
        ),
      ),
    );
  }
}
