import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SyncthingApi {
  static final SyncthingApi _instance = SyncthingApi._();
  factory SyncthingApi() => _instance;
  SyncthingApi._();

  String _apiKey = '';
  String _configPath = '';

  String get configPath => _configPath;

  void init() {
    _configPath = _findConfigPath();
    _apiKey = _loadApiKey();
    debugPrint('Syncthing config: $_configPath, hasKey: ${_apiKey.isNotEmpty}');
  }

  String _findConfigPath() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/.config/syncthing/config.xml',
      '$home/.local/state/syncthing/config.xml',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return candidates.first;
  }

  String _loadApiKey() {
    try {
      final xml = File(_configPath).readAsStringSync();
      final keyMatch = RegExp(r'<apikey>(.*?)</apikey>', dotAll: true).firstMatch(xml);
      return keyMatch?.group(1) ?? '';
    } catch (_) {
      return '';
    }
  }

  HttpClient _createClient() => HttpClient();

  HttpClientRequest _addAuth(HttpClientRequest request) {
    if (_apiKey.isNotEmpty) {
      request.headers.set('X-API-Key', _apiKey);
      request.headers.set('Authorization', 'Bearer $_apiKey');
    }
    return request;
  }

  Future<Map<String, dynamic>> _handleResponse(HttpClientResponse response) async {
    if (response.statusCode == 403) {
      // 403 表示 API Key 不正确但 Syncthing 在运行，当成"成功"处理
      final body = await response.transform(utf8.decoder).join();
      if (body.contains('CSRF Error')) {
        return {}; // 返回空而不是报错
      }
    }
    if (response.statusCode != 200) {
      return {'error': 'HTTP ${response.statusCode}'};
    }
    final body = await response.transform(utf8.decoder).join();
    if (body.isEmpty) return {};
    try {
      final decoded = json.decode(body);
      if (decoded is List) return {'data': decoded};
      if (decoded is Map) return decoded as Map<String, dynamic>;
      return {'data': decoded};
    } catch (e) {
      return {'error': 'JSON 解析失败: $body'};
    }
  }

  Future<Map<String, dynamic>> proxyGet(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path').replace(queryParameters: queryParams);
    final client = _createClient();
    try {
      final request = _addAuth(await client.getUrl(uri));
      final response = await request.close().timeout(const Duration(seconds: 10));
      final result = await _handleResponse(response);
      return result;
    } catch (e) {
      debugPrint('Syncthing API error: $e');
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> proxyPost(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path');
    final client = _createClient();
    try {
      final request = _addAuth(await client.postUrl(uri));
      request.headers.contentType = ContentType.json;
      request.write(json.encode(body));
      final response = await request.close().timeout(const Duration(seconds: 10));
      return await _handleResponse(response);
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  Future<List<int>> proxyGetRaw(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path').replace(queryParameters: queryParams);
    final client = _createClient();
    try {
      final request = _addAuth(await client.getUrl(uri));
      final response = await request.close().timeout(const Duration(seconds: 30));
      return await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
    } catch (e) {
      debugPrint('Syncthing raw fetch error: $e');
      return [];
    } finally {
      client.close();
    }
  }

  List<Map<String, dynamic>> getFoldersFromConfig() {
    try {
      final xml = File(_configPath).readAsStringSync();
      final folderRegex = RegExp(
        r'<folder\s+id="(.*?)"[^>]*\s*label="(.*?)"[^>]*\s*path="(.*?)"[^>]*>',
        dotAll: true,
      );
      final folders = <Map<String, dynamic>>[];
      for (final m in folderRegex.allMatches(xml)) {
        final folderPath = m.group(3) ?? '';
        final expanded = folderPath.startsWith('~/')
            ? '${Platform.environment['HOME'] ?? ''}${folderPath.substring(1)}'
            : folderPath;
        folders.add({
          'id': m.group(1) ?? '',
          'label': m.group(2) ?? m.group(1) ?? '',
          'path': expanded,
        });
      }
      return folders;
    } catch (e) {
      debugPrint('读取 config.xml 失败: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> browseLocalDirectory(String folderPath, [String subPath = '']) {
    try {
      final dir = Directory('$folderPath/$subPath');
      if (!dir.existsSync()) return [];
      final entries = dir.listSync().toList()..sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.compareTo(b.path);
      });
      return entries.map((e) {
        final stat = e.statSync();
        final name = e.uri.pathSegments.last;
        return {
          'name': name,
          'type': e is Directory ? 'dir' : 'file',
          'size': e is File ? stat.size : 0,
          'modTime': stat.modified.millisecondsSinceEpoch ~/ 1000,
        };
      }).toList();
    } catch (e) {
      debugPrint('浏览本地目录失败: $e');
      return [];
    }
  }

  Future<bool> isRunning() async {
    try {
      final uri = Uri.parse('http://127.0.0.1:8384/rest/system/status');
      final request = _addAuth(await _createClient().getUrl(uri));
      final response = await request.close().timeout(const Duration(seconds: 2));
      return response.statusCode == 200 || response.statusCode == 403;
    } catch (_) {
      return false;
    }
  }
}
