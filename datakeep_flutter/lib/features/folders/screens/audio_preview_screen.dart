import 'package:flutter/material.dart';
import '../../../shared/widgets/audio_preview.dart';

/// 移动端全屏音频播放页
class AudioPreviewScreen extends StatelessWidget {
  final String filePath;
  final String title;

  const AudioPreviewScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: AudioPreview(filePath: filePath, title: title),
      ),
    );
  }
}
