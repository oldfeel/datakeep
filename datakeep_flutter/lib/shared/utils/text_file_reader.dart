import 'dart:convert';
import 'dart:io';

/// 文本预览：按 UTF-8 读文件字节；预览时将 %XX 还原为可读字符（如 magnet 里的 %3A → :）。
Future<String> readTextFileForPreview(
  String path, {
  int maxChars = 500000,
}) async {
  final bytes = await File(path).readAsBytes();
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('\uFEFF')) {
    text = text.substring(1);
  }
  text = _decodePercentEscapesForDisplay(text);
  if (text.length > maxChars) {
    return text.substring(0, maxChars);
  }
  return text;
}

/// 将文本中的 %XX 还原为对应字符（如 %3A → :），不影响无效的 % 片段。
String _decodePercentEscapesForDisplay(String text) {
  return text.replaceAllMapped(
    RegExp(r'%[0-9A-Fa-f]{2}'),
    (m) => String.fromCharCode(int.parse(m.group(0)!.substring(1), radix: 16)),
  );
}
