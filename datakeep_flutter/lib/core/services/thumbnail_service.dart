import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../shared/utils/file_types.dart';
import '../../shared/utils/preview_limits.dart';
import '../services/api_service.dart';

/// 本机 / 对端图片与视频缩略图：磁盘缓存 + 限制并发。
class ThumbnailService {
  ThumbnailService._();
  static final ThumbnailService instance = ThumbnailService._();

  static const int targetSize = 160;
  static const int maxConcurrent = 4;

  Directory? _cacheRoot;
  final Map<String, Future<String?>> _pending = {};
  int _running = 0;
  final List<Completer<void>> _waitQueue = [];

  static bool supportsFileName(String fileName) =>
      FileTypes.isImage(fileName) || FileTypes.isVideo(fileName);

  Future<Directory> _cacheRootDir() async {
    if (_cacheRoot != null) return _cacheRoot!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'thumbnails'));
    await dir.create(recursive: true);
    _cacheRoot = dir;
    return dir;
  }

  String _cacheKey(String kind, String identity, FileStat stat) {
    final raw =
        '$kind|v3|$identity|${stat.modified.millisecondsSinceEpoch}|${stat.size}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  String _remoteCacheKey({
    required String deviceId,
    required String folderId,
    required String relativePath,
    int? modTime,
    int? size,
  }) {
    final raw =
        'remote|v1|$deviceId|$folderId|$relativePath|$modTime|$size';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// 本机已同步文件缩略图（图片或视频首帧）。
  Future<String?> thumbnailPath(String localPath) async {
    if (FileTypes.isImage(localPath)) {
      return imageThumbnailPath(localPath);
    }
    if (FileTypes.isVideo(localPath)) {
      return videoThumbnailPath(localPath);
    }
    return null;
  }

  /// 对端只读浏览：经 API 拉取缩略图并缓存到本机。
  Future<String?> remoteThumbnailPath({
    required String deviceId,
    required String folderId,
    required String relativePath,
    int? modTime,
    int? size,
  }) async {
    if (!supportsFileName(relativePath)) return null;

    final root = await _cacheRootDir();
    final key = _remoteCacheKey(
      deviceId: deviceId,
      folderId: folderId,
      relativePath: relativePath,
      modTime: modTime,
      size: size,
    );
    final cacheFile = File(p.join(root.path, 'remote_$key.png'));
    if (await cacheFile.exists()) return cacheFile.path;

    final pendingKey = cacheFile.path;
    final existing = _pending[pendingKey];
    if (existing != null) return existing;

    final task = _fetchRemote(cacheFile, deviceId, folderId, relativePath);
    _pending[pendingKey] = task;
    try {
      return await task;
    } finally {
      _pending.remove(pendingKey);
    }
  }

  Future<String?> _fetchRemote(
    File cacheFile,
    String deviceId,
    String folderId,
    String relativePath,
  ) async {
    if (await cacheFile.exists()) return cacheFile.path;
    try {
      final bytes = await ApiService.fetchThumbnailBytes(
        folderId,
        relativePath,
        deviceId: deviceId,
      );
      if (bytes == null || bytes.isEmpty) return null;
      await cacheFile.writeAsBytes(bytes);
      return cacheFile.path;
    } catch (e) {
      debugPrint('[thumbnail] 远程缩略图失败: $e');
      return null;
    }
  }

  /// 返回缓存缩略图路径；非图片或失败时返回 null。
  Future<String?> imageThumbnailPath(String localPath) async {
    if (!FileTypes.isImage(localPath)) return null;
    final source = File(localPath);
    if (!await source.exists()) return null;

    final stat = await source.stat();
    final root = await _cacheRootDir();
    final cacheFile =
        File(p.join(root.path, '${_cacheKey('img', localPath, stat)}.png'));
    if (await cacheFile.exists()) return cacheFile.path;

    return _dedupe(cacheFile.path, () => _generateImage(source, cacheFile));
  }

  Future<String?> videoThumbnailPath(String localPath) async {
    if (!FileTypes.isVideo(localPath)) return null;
    final source = File(localPath);
    if (!await source.exists()) return null;

    final stat = await source.stat();
    if (stat.size > kMaxThumbnailSourceBytes) return null;

    final root = await _cacheRootDir();
    final cacheFile =
        File(p.join(root.path, '${_cacheKey('vid', localPath, stat)}.png'));
    if (await cacheFile.exists()) return cacheFile.path;

    return _dedupe(cacheFile.path, () => _generateVideo(source, cacheFile));
  }

  Future<String?> _dedupe(
    String key,
    Future<String?> Function() task,
  ) async {
    final existing = _pending[key];
    if (existing != null) return existing;
    final fut = task();
    _pending[key] = fut;
    try {
      return await fut;
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

  Future<String?> _generateImage(File source, File cacheFile) async {
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

  Future<String?> _generateVideo(File source, File cacheFile) async {
    if (await cacheFile.exists()) return cacheFile.path;
    await _acquireSlot();
    try {
      if (await cacheFile.exists()) return cacheFile.path;

      if (!Platform.isAndroid && !Platform.isIOS) {
        final ok = await _ffmpegThumbnail(source.path, cacheFile.path);
        if (ok && await cacheFile.exists()) return cacheFile.path;
      }

      final generated = await VideoThumbnail.thumbnailFile(
        video: source.path,
        thumbnailPath: cacheFile.path,
        imageFormat: ImageFormat.PNG,
        maxWidth: targetSize,
        quality: 80,
      );
      if (generated != null && await File(generated).exists()) {
        if (generated != cacheFile.path) {
          await File(generated).copy(cacheFile.path);
        }
        return cacheFile.path;
      }
      return null;
    } catch (e) {
      debugPrint('[thumbnail] 视频缩略图失败: $e');
      return null;
    } finally {
      _releaseSlot();
    }
  }

  Future<bool> _ffmpegThumbnail(String inputPath, String outputPath) async {
    try {
      final result = await Process.run(
        'ffmpeg',
        [
          '-hide_banner',
          '-loglevel',
          'error',
          '-ss',
          '0',
          '-i',
          inputPath,
          '-frames:v',
          '1',
          '-vf',
          'scale=$targetSize:-2:force_original_aspect_ratio=decrease',
          '-y',
          outputPath,
        ],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
