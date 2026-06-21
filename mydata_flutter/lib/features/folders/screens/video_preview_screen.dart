import 'package:flutter/material.dart';
import '../../../shared/widgets/video_preview.dart';

/// 移动端全屏视频播放页
class VideoPreviewScreen extends StatelessWidget {
  final String filePath;
  final String title;

  const VideoPreviewScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: VideoPreview(filePath: filePath),
      ),
    );
  }
}
