// 一次性工具：将图标 PNG 四角黑色 matte 转为透明（RGB → RGBA）
// 用法：dart run tool/fix_icon_alpha.dart [path...]
import 'dart:io';

import 'package:image/image.dart' as img;

void fixFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('skip (missing): $path');
    return;
  }
  final decoded = img.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('skip (decode failed): $path');
    return;
  }
  final rgba = decoded.convert(numChannels: 4);
  var cleared = 0;
  for (var y = 0; y < rgba.height; y++) {
    for (var x = 0; x < rgba.width; x++) {
      final p = rgba.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final a = p.a.toInt();
      if (a == 0) continue;
      // 导出时无 alpha 通道，圆角外通常填纯黑 matte
      if (r < 24 && g < 24 && b < 24) {
        rgba.setPixelRgba(x, y, r, g, b, 0);
        cleared++;
      }
    }
  }
  file.writeAsBytesSync(img.encodePng(rgba));
  stdout.writeln('$path: cleared $cleared pixels → RGBA');
}

void main(List<String> args) {
  final paths = args.isEmpty
      ? [
          'assets/icons/app_icon.png',
          'assets/icons/datakeep_app_icon.png',
          'assets/icons/datakeep_logo.png',
          'assets/images/datakeep_logo.png',
        ]
      : args;
  for (final p in paths) {
    fixFile(p);
  }
}
