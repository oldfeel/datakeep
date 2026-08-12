/// 按扩展名判断文件类型（预览 / 播放）
class FileTypes {
  FileTypes._();

  static String extension(String filePath) =>
      filePath.toLowerCase().split('.').lastOrNull ?? '';

  static bool isImage(String filePath) => [
        'jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico',
      ].contains(extension(filePath));

  static bool isVideo(String filePath) => [
        'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v',
      ].contains(extension(filePath));

  static bool isAudio(String filePath) => [
        'mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a',
      ].contains(extension(filePath));

  static bool isPdf(String filePath) => extension(filePath) == 'pdf';

  static bool isText(String filePath) => [
        'txt', 'md', 'json', 'xml', 'yaml', 'yml', 'js', 'ts', 'html', 'css',
        'py', 'java', 'cpp', 'c', 'go', 'rs', 'dart', 'csv', 'log',
      ].contains(extension(filePath));

  /// 需要在应用内下载后预览（图片、文本）
  static bool needsDownloadPreview(String filePath) =>
      isImage(filePath) || isText(filePath);
}
