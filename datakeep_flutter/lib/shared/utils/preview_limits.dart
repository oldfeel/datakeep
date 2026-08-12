/// 应用内预览大小上限（超过则提示下载 / 系统打开）
const int kMaxPreviewBytes = 200 * 1024 * 1024; // 200MB

String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 预览文件过大
class PreviewTooLargeException implements Exception {
  final int sizeBytes;
  PreviewTooLargeException(this.sizeBytes);

  @override
  String toString() =>
      '文件过大（${formatByteSize(sizeBytes)}），超过应用内预览上限 ${formatByteSize(kMaxPreviewBytes)}，请使用下载或系统打开';
}
