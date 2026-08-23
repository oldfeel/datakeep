import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../shared/utils/file_types.dart';

/// 本机图片缩略图：磁盘缓存 + 限制并发，列表滚动时按需生成。
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const int targetSize = 160;
  static const int maxConcurrent = 4;

  Directory? _cacheRoot;
  final Map<String, Future<String?>> _pending = {};
  int _running = 0;
  final List<Completer<void>> _waitQueue = [];

  Future<Directory> _cacheRootDir() async {
    if (_cacheRoot != null) return _cacheRoot!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'thumbnails'));
    await dir.create(recursive: true);
    _cacheRoot = dir;
    return dir;
  }

  String _cacheKey(String path, FileStat stat) {
    // v2：修正缩略图宽高比与 EXIF 方向
    final raw = 'v2|$path|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// 返回缓存缩略图路径；非图片或失败时返回 null。
  Future<String?> imageThumbnailPath(String localPath) async {
    if (!FileTypes.isImage(localPath)) return null;
    final source = File(localPath);
    if (!await source.exists()) return null;

    final stat = await source.stat();
    final root = await _cacheRootDir();
    final cacheFile = File(p.join(root.path, '${_cacheKey(localPath, stat)}.png'));
    if (await cacheFile.exists()) return cacheFile.path;

    final key = cacheFile.path;
    final existing = _pending[key];
    if (existing != null) return existing;

    final task = _generate(source, cacheFile);
    _pending[key] = task;
    try {
      return await task;
    } finally {
      _pending.remove(key);
    }
  }

  Future<void> _acquireSlot() async {
    while (_running >= maxConcurrent) {
      final gate = Completer<void>();
      _waitQueue.add(gate);
      await gate.future;
    }
    _running++;
  }

  void _releaseSlot() {
    _running--;
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    }
  }

  Future<String?> _generate(File source, File cacheFile) async {
    if (await cacheFile.exists()) return cacheFile.path;
    await _acquireSlot();
    try {
      if (await cacheFile.exists()) return cacheFile.path;
      final bytes = await source.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final oriented = img.bakeOrientation(decoded);
      final resized = img.copyResize(
        oriented,
        width: oriented.width >= oriented.height ? targetSize : null,
        height: oriented.width < oriented.height ? targetSize : null,
      );
      final png = Uint8List.fromList(img.encodePng(resized));
      await cacheFile.writeAsBytes(png);
      return cacheFile.path;
    } catch (_) {
      return null;
    } finally {
      _releaseSlot();
    }
  }
}
