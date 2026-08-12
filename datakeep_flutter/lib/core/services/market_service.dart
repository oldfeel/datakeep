import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import '../../shared/utils/app_dir.dart';

class MarketAppInfo {
  final String appKey;
  final String name;
  final String description;
  final String? version;
  final String? sha256;
  final int? size;
  final String? downloadUrl;
  final String? iconUrl;

  MarketAppInfo({
    required this.appKey,
    required this.name,
    required this.description,
    this.version,
    this.sha256,
    this.size,
    this.downloadUrl,
    this.iconUrl,
  });

  factory MarketAppInfo.fromJson(Map<String, dynamic> j) => MarketAppInfo(
        appKey: j['appKey']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        version: j['version']?.toString(),
        sha256: j['sha256']?.toString(),
        size: (j['size'] as num?)?.toInt(),
        downloadUrl: j['downloadUrl']?.toString(),
        iconUrl: j['iconUrl']?.toString(),
      );

  String get folderId => 'app-$appKey';
}

/// 应用市场客户端（默认局域网 API）
class MarketService {
  static const _prefKey = 'market_api_base';
  static const defaultBase = 'http://192.168.2.10:8088';

  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? defaultBase;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<List<MarketAppInfo>> listApps() async {
    final base = await getBaseUrl();
    final url = '$base/api/apps';
    debugPrint('[market] GET $url');
    final res = await http.get(Uri.parse(url));
    debugPrint('[market] list status=${res.statusCode} bodyLen=${res.bodyBytes.length}');
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['code'] != 0) {
      throw Exception(json['data']?.toString() ?? '加载失败');
    }
    final list = json['data'] as List? ?? [];
    final apps = list
        .whereType<Map>()
        .map((e) => MarketAppInfo.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    for (final a in apps) {
      debugPrint('[market] app=${a.appKey} downloadUrl=${a.downloadUrl}');
    }
    return apps;
  }

  static Future<Directory> appsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'DataKeepApps'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> installPathFor(String appKey) async {
    final root = await appsRoot();
    return p.join(root.path, appKey);
  }

  // 私有桶直链会 400（NotSupportAnonymous）；优先走市场服务代下
  static Future<Uri> resolveDownloadUri(MarketAppInfo app) async {
    final base = await getBaseUrl();
    final proxy = Uri.parse('$base/api/apps/${Uri.encodeComponent(app.appKey)}/package');
    final raw = app.downloadUrl?.trim() ?? '';
    if (raw.isEmpty) return proxy;
    final u = Uri.tryParse(raw);
    // 相对路径：拼到 API base
    if (u == null || !u.hasScheme) {
      final path = raw.startsWith('/') ? raw : '/$raw';
      return Uri.parse('$base$path');
    }
    // 对象存储直链（无签名）不可用 → 强制代下
    final host = u.host.toLowerCase();
    if (host.contains('qiniucs.com') ||
        host.contains('amazonaws.com') ||
        host.contains('aliyuncs.com')) {
      debugPrint('[market] rewrite storage URL → proxy: $raw → $proxy');
      return proxy;
    }
    return u;
  }

  /// 下载、校验、解压到 parentDir/appKey（保留已有 data/），并注册为 kind=app
  static Future<void> install(
    MarketAppInfo app, {
    String? parentDir,
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('下载中…');
    final uri = await resolveDownloadUri(app);
    debugPrint('[market] install app=${app.appKey} GET $uri');
    final res = await http.get(uri);
    final preview = utf8.decode(
      res.bodyBytes.take(300).toList(),
      allowMalformed: true,
    );
    debugPrint(
      '[market] download status=${res.statusCode} '
      'len=${res.bodyBytes.length} content-type=${res.headers['content-type']} '
      'preview=$preview',
    );
    if (res.statusCode >= 300) {
      throw Exception(
        '下载失败 HTTP ${res.statusCode}: ${preview.replaceAll('\n', ' ')}',
      );
    }
    // 若误下到 JSON 错误包
    if (res.bodyBytes.isNotEmpty && res.bodyBytes[0] == 0x7b /* { */) {
      try {
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        if (j['code'] != null && j['code'] != 0) {
          throw Exception(j['data']?.toString() ?? '下载失败');
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('下载')) rethrow;
      }
    }
    final bytes = res.bodyBytes;
    if (app.sha256 != null && app.sha256!.isNotEmpty) {
      final digest = sha256.convert(bytes).toString();
      if (digest.toLowerCase() != app.sha256!.toLowerCase()) {
        debugPrint('[market] sha256 want=${app.sha256} got=$digest');
        throw Exception('sha256 校验失败');
      }
    }

    final String targetPath;
    if (parentDir != null && parentDir.trim().isNotEmpty) {
      targetPath = p.join(parentDir.trim(), app.appKey);
    } else {
      targetPath = await installPathFor(app.appKey);
    }
    final target = Directory(targetPath);
    Directory? preservedData;
    final dataDir = Directory(p.join(target.path, 'data'));
    if (dataDir.existsSync()) {
      onProgress?.call('保留 data/…');
      final tmp = await Directory.systemTemp.createTemp('datakeep_app_data_');
      await _copyDir(dataDir, Directory(p.join(tmp.path, 'data')));
      preservedData = Directory(p.join(tmp.path, 'data'));
    }

    if (target.existsSync()) {
      await target.delete(recursive: true);
    }
    await target.create(recursive: true);

    onProgress?.call('解压中…');
    final archive = ZipDecoder().decodeBytes(bytes);
    // 若 zip 只有一层顶目录，剥掉
    String? stripPrefix;
    final topDirs = <String>{};
    for (final f in archive.files) {
      final name = f.name.replaceAll('\\', '/');
      if (name.isEmpty || name.startsWith('__MACOSX')) continue;
      final parts = name.split('/');
      if (parts.length > 1) topDirs.add(parts.first);
    }
    if (topDirs.length == 1 &&
        !archive.files.any((f) => f.name.replaceAll('\\', '/') == 'app.json')) {
      stripPrefix = '${topDirs.first}/';
    }

    for (final file in archive.files) {
      var name = file.name.replaceAll('\\', '/');
      if (name.startsWith('__MACOSX')) continue;
      if (stripPrefix != null) {
        if (!name.startsWith(stripPrefix)) continue;
        name = name.substring(stripPrefix.length);
      }
      if (name.isEmpty) continue;
      final outPath = p.join(target.path, name);
      if (file.isFile) {
        final out = File(outPath);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>);
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }

    if (preservedData != null && preservedData.existsSync()) {
      final dest = Directory(p.join(target.path, 'data'));
      if (dest.existsSync()) await dest.delete(recursive: true);
      await _copyDir(preservedData, dest);
      try {
        await preservedData.parent.delete(recursive: true);
      } catch (_) {}
    }

    onProgress?.call('完成安装…');
    final folderId = app.folderId;
    final existing = await ApiService.getFolders();
    // 安装目标若已在某个同步文件夹内部：只作为子目录应用，不注册到首页
    final enclosing = findEnclosingSyncFolder(existing, target.path);
    final nested = enclosing != null &&
        normalizeFsPath(enclosing.path) != normalizeFsPath(target.path);

    if (nested) {
      debugPrint(
        '[market] 嵌套安装到 ${enclosing.id} 下: ${target.path}，不注册独立同步文件夹',
      );
      // 若此前误注册为独立文件夹，取消注册（保留磁盘文件）
      try {
        await ApiService.deleteFolder(folderId);
        debugPrint('[market] 已取消嵌套应用的独立同步注册: $folderId');
      } catch (e) {
        debugPrint('[market] 取消注册（可忽略）: $e');
      }
      // 仍写入本目录 .stignore；父文件夹需自行忽略或接受 *.db 被同步
      await _writeLocalStignore(target.path);
      try {
        await ApiService.scanFolder(enclosing.id);
      } catch (e) {
        debugPrint('[market] scan parent: $e');
      }
      return;
    }

    final already = existing.any((f) => f.id == folderId);
    if (!already) {
      onProgress?.call('注册同步文件夹…');
      await ApiService.createFolder(
        id: folderId,
        name: app.name,
        path: target.path,
        kind: 'app',
      );
    } else {
      await ApiService.setFolderKind(folderId, 'app');
      debugPrint('应用文件夹已存在，已更新 kind: $folderId');
    }

    await _applySyncIgnoreFromAppJson(folderId, target.path);
  }

  static Future<List<String>> _readSyncIgnoreRules(String appPath) async {
    final meta = File(p.join(appPath, 'app.json'));
    if (!meta.existsSync()) return const [];
    try {
      final m = json.decode(await meta.readAsString());
      if (m is Map && m['syncIgnore'] is List) {
        return (m['syncIgnore'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static Future<void> _writeLocalStignore(String appPath) async {
    final rules = await _readSyncIgnoreRules(appPath);
    if (rules.isEmpty) return;
    try {
      final stignore = File(p.join(appPath, '.stignore'));
      final existingLines = stignore.existsSync()
          ? (await stignore.readAsLines())
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : <String>[];
      final fileMerged = <String>[...existingLines];
      for (final r in rules) {
        if (!fileMerged.contains(r)) fileMerged.add(r);
      }
      if (fileMerged.length != existingLines.length || !stignore.existsSync()) {
        await stignore.writeAsString('${fileMerged.join('\n')}\n');
      }
    } catch (e) {
      debugPrint('[market] 写 .stignore: $e');
    }
  }

  /// 读取 app.json 的 syncIgnore，合并进该同步文件夹的忽略规则。
  static Future<void> _applySyncIgnoreFromAppJson(
    String folderId,
    String appPath,
  ) async {
    final rules = await _readSyncIgnoreRules(appPath);
    if (rules.isEmpty) return;

    await _writeLocalStignore(appPath);

    try {
      final existing = await ApiService.getFolderIgnores(folderId);
      final merged = <String>[...existing];
      for (final r in rules) {
        if (!merged.contains(r)) merged.add(r);
      }
      if (merged.length != existing.length) {
        await ApiService.setFolderIgnores(folderId, merged);
        debugPrint('[market] 已合并 syncIgnore: $rules');
      }
    } catch (e) {
      debugPrint('[market] setFolderIgnores（可忽略）: $e');
    }
  }

  static Future<void> uninstall(String appKey) async {
    final folderId = 'app-$appKey';
    try {
      await ApiService.deleteFolder(folderId);
    } catch (e) {
      debugPrint('deleteFolder: $e');
    }
    final dir = Directory(await installPathFor(appKey));
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(recursive: true)) {
      final rel = p.relative(entity.path, from: src.path);
      final targetPath = p.join(dst.path, rel);
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      }
    }
  }
}
