import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 移动端全屏图片预览（支持双指缩放）
class ImagePreviewScreen extends StatelessWidget {
  final String title;
  final String? filePath;
  final Uint8List? bytes;

  const ImagePreviewScreen({
    super.key,
    required this.title,
    this.filePath,
    this.bytes,
  }) : assert(filePath != null || bytes != null);

  @override
  Widget build(BuildContext context) {
    final Widget image = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.contain)
        : Image.file(File(filePath!), fit: BoxFit.contain);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: SizedBox.expand(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(child: image),
        ),
      ),
    );
  }
}
