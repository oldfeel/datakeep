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

/// 封面画廊中的一帧候选
class CoverFrameCandidate {
  const CoverFrameCandidate({
    required this.path,
    required this.sec,
    required this.luma,
    this.recommended = false,
  });

  final String path;
  final double sec;
  final double luma;
  final bool recommended;
}

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
        final path = await extractVideoCover(
          videoPath: source.path,
          outputPath: cacheFile.path,
          maxWidth: targetSize,
        );
        if (path != null) return path;
      }

      // 移动端 / ffmpeg 失败：多时间点取样，避开片头黑场
      String? bestPath;
      var bestMean = -1.0;
      for (final ms in _coverSeekMsCandidates(null)) {
        try {
          final generated = await VideoThumbnail.thumbnailFile(
            video: source.path,
            thumbnailPath: cacheFile.path,
            imageFormat: ImageFormat.PNG,
            maxWidth: targetSize,
            quality: 80,
            timeMs: ms,
          );
          if (generated == null || !await File(generated).exists()) continue;
          if (generated != cacheFile.path) {
            await File(generated).copy(cacheFile.path);
          }
          final mean = await _imageLumaMean(cacheFile.path);
          if (mean != null && mean > bestMean) {
            bestMean = mean;
            bestPath = cacheFile.path;
          }
          if (mean != null && mean >= _minCoverLuma) {
            return cacheFile.path;
          }
        } catch (_) {
          /* try next */
        }
      }
      return bestPath;
    } catch (e) {
      debugPrint('[thumbnail] 视频缩略图失败: $e');
      return null;
    } finally {
      _releaseSlot();
    }
  }

  /// 桌面截帧封面：ffmpeg 多点取样，跳过过暗帧（片头黑场）。
  Future<String?> extractVideoCover({
    required String videoPath,
    required String outputPath,
    int maxWidth = 640,
  }) async {
    final out = File(outputPath);
    await out.parent.create(recursive: true);
    final duration = await _probeDurationSeconds(videoPath);
    final seeks = _coverSeekSecondsCandidates(duration);

    String? bestPath;
    var bestMean = -1.0;
    final tmp = File('$outputPath.part.jpg');

    for (final sec in seeks) {
      try {
        final result = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-ss',
          sec.toString(),
          '-i',
          videoPath,
          '-frames:v',
          '1',
          '-vf',
          'scale=$maxWidth:-2:force_original_aspect_ratio=decrease',
          '-y',
          tmp.path,
        ]);
        if (result.exitCode != 0 || !await tmp.exists() || await tmp.length() == 0) {
          continue;
        }
        final mean = await _imageLumaMean(tmp.path);
        if (mean == null) continue;
        if (mean > bestMean) {
          bestMean = mean;
          await tmp.copy(outputPath);
          bestPath = outputPath;
        }
        if (mean >= _minCoverLuma) {
          try {
            await tmp.delete();
          } catch (_) {}
          return outputPath;
        }
      } catch (e) {
        debugPrint('[thumbnail] ffmpeg 截帧 ${sec}s 失败: $e');
      }
    }
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    return bestPath;
  }

  /// 平均亮度低于此值视为过暗（0–255）
  static const double minCoverLuma = 18;
  static const double _minCoverLuma = minCoverLuma;

  /// 准备封面画廊目录并返回取样时间点（不截帧）。
  Future<({double? duration, List<double> seeks})> prepareCoverGallery({
    required String videoPath,
    required String outputDir,
    int maxFrames = 20,
  }) async {
    final dir = Directory(outputDir);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
    await dir.create(recursive: true);
    final duration = await _probeDurationSeconds(videoPath);
    final seeks = gallerySeekSeconds(duration, maxFrames);
    return (duration: duration, seeks: seeks);
  }

  /// 截取单帧封面（画廊逐帧更新用）。
  Future<CoverFrameCandidate?> extractSingleCoverFrame({
    required String videoPath,
    required String outputPath,
    required double sec,
    int maxWidth = 480,
  }) async {
    await File(outputPath).parent.create(recursive: true);
    try {
      final result = await Process.run('ffmpeg', [
        '-hide_banner',
        '-loglevel',
        'error',
        '-ss',
        sec.toStringAsFixed(3),
        '-i',
        videoPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=$maxWidth:-2:force_original_aspect_ratio=decrease',
        '-q:v',
        '3',
        '-y',
        outputPath,
      ]);
      if (result.exitCode != 0 || !await File(outputPath).exists()) return null;
      if (await File(outputPath).length() == 0) return null;
      final mean = await _imageLumaMean(outputPath) ?? 0;
      return CoverFrameCandidate(path: outputPath, sec: sec, luma: mean);
    } catch (e) {
      debugPrint('[thumbnail] 单帧截取 ${sec}s 失败: $e');
      return null;
    }
  }

  /// 封面画廊：均匀抽帧（含亮度），供用户选择。
  Future<List<CoverFrameCandidate>> extractVideoCoverCandidates({
    required String videoPath,
    required String outputDir,
    int maxWidth = 480,
    int maxFrames = 20,
  }) async {
    final prepared = await prepareCoverGallery(
      videoPath: videoPath,
      outputDir: outputDir,
      maxFrames: maxFrames,
    );
    final results = <CoverFrameCandidate>[];

    for (var i = 0; i < prepared.seeks.length; i++) {
      final sec = prepared.seeks[i];
      final name = 'f_${i.toString().padLeft(3, '0')}.jpg';
      final outPath = p.join(outputDir, name);
      final frame = await extractSingleCoverFrame(
        videoPath: videoPath,
        outputPath: outPath,
        sec: sec,
        maxWidth: maxWidth,
      );
      if (frame != null) results.add(frame);
    }

    if (results.isEmpty) return results;

    final usable = results.where((f) => f.luma >= _minCoverLuma).toList();
    final pool = usable.isNotEmpty ? usable : results;
    pool.sort((a, b) => b.luma.compareTo(a.luma));
    final bestPath = pool.first.path;

    return [
      for (final f in results)
        CoverFrameCandidate(
          path: f.path,
          sec: f.sec,
          luma: f.luma,
          recommended: f.path == bestPath,
        ),
    ];
  }

  static List<double> gallerySeekSeconds(double? durationSec, int maxFrames) {
    final n = maxFrames.clamp(6, 36);
    final d = (durationSec != null && durationSec.isFinite && durationSec > 2)
        ? durationSec
        : 120.0;
    // 避开首尾：从 2%～95% 均匀取点
    final start = (d * 0.02).clamp(0.5, d);
    final end = (d * 0.95).clamp(start + 0.5, d);
    final out = <double>[];
    for (var i = 0; i < n; i++) {
      final t = start + (end - start) * (i + 0.5) / n;
      out.add(t);
    }
    return out;
  }

  static List<double> _gallerySeekSeconds(double? durationSec, int maxFrames) =>
      gallerySeekSeconds(durationSec, maxFrames);

  static List<double> _coverSeekSecondsCandidates(double? durationSec) {
    final d = durationSec;
    final raw = <double>[
      1,
      5,
      10,
      30,
      60,
      120,
      if (d != null && d.isFinite && d > 0) ...[
        (d * 0.05).clamp(1, d),
        (d * 0.1).clamp(1, d),
        (d * 0.2).clamp(1, d),
      ],
    ];
    final out = <double>[];
    for (final s in raw) {
      if (d != null && d.isFinite && s >= d - 0.5) continue;
      if (out.any((x) => (x - s).abs() < 0.4)) continue;
      out.add(s);
    }
    out.sort();
    return out.isEmpty ? const [1.0] : out;
  }

  static List<int> _coverSeekMsCandidates(double? durationSec) {
    return _coverSeekSecondsCandidates(durationSec)
        .map((s) => (s * 1000).round())
        .toList();
  }

  Future<double?> _probeDurationSeconds(String videoPath) async {
    try {
      final r = await Process.run('ffprobe', [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        videoPath,
      ]);
      if (r.exitCode != 0) return null;
      return double.tryParse(r.stdout.toString().trim());
    } catch (_) {
      return null;
    }
  }

  Future<double?> _imageLumaMean(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return null;
      }
      // 下采样统计，避免大图过慢
      final stepX = (decoded.width / 64).ceil().clamp(1, decoded.width);
      final stepY = (decoded.height / 64).ceil().clamp(1, decoded.height);
      var sum = 0.0;
      var n = 0;
      for (var y = 0; y < decoded.height; y += stepY) {
        for (var x = 0; x < decoded.width; x += stepX) {
          final p = decoded.getPixel(x, y);
          sum += 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b;
          n++;
        }
      }
      return n == 0 ? null : sum / n;
    } catch (_) {
      return null;
    }
  }
}
