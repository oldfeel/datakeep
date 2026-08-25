import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../shared/utils/preview_limits.dart';
import '../../shared/utils/local_http_client.dart';

/// 局域网对端 DataKeep HTTPS 客户端（自签名 + 私网 IP）
class PeerClient {
  PeerClient._();

  static const int peerPort = 8443;
  static const String deviceIdHeader = 'X-DataKeep-Device-ID';

  /// 从 Syncthing 连接地址提取 IPv4，如 `192.168.2.12:22000` → `192.168.2.12`
  static String? extractLanIp(String? address) {
    if (address == null || address.isEmpty) return null;
    var s = address.trim();
    s = s.replaceFirst(RegExp(r'^[a-z]+://'), '');
    // [IPv6]:port — 本期仅 IPv4
    if (s.startsWith('[')) return null;
    final host = s.split('%').first.split('/').first.split(':').first;
    if (!_isPrivateIpv4(host)) return null;
    return host;
  }

  static bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null || n < 0 || n > 255)) return false;
    final a = nums[0]!, b = nums[1]!;
    if (a == 10) return true;
    if (a == 192 && b == 168) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    return false;
  }

  static HttpClient _client({Duration? connectionTimeout}) {
    final c = HttpClient();
    c.connectionTimeout = connectionTimeout ?? const Duration(seconds: 5);
    configureLocalHttpClient(
      c,
      trustCertificate: (host, port) => _isPrivateIpv4(host) && port == peerPort,
    );
    return c;
  }

  /// GET https://{ip}:8443/path
  static Future<Map<String, dynamic>> getJson(
    String ip,
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final uri = Uri.parse('https://$ip:$peerPort$path');
    final client = _client();
    try {
      final req = await client.getUrl(uri).timeout(timeout);
      headers?.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        String msg = 'HTTP ${res.statusCode}';
        try {
          final decoded = json.decode(body);
          if (decoded is Map && decoded['data'] != null) {
            msg = decoded['data'].toString();
          }
        } catch (_) {}
        return {'error': msg, 'statusCode': res.statusCode};
      }
      if (body.isEmpty) return {};
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {'data': decoded};
    } on SocketException catch (e) {
      debugPrint('[peer] 连接失败 $uri: $e');
      return {
        'error': '对端数据管理不可达（需同局域网且对端已打开数据管理）',
      };
    } on TimeoutException catch (_) {
      return {'error': '连接对端超时（需同局域网且对端已打开数据管理）'};
    } catch (e) {
      debugPrint('[peer] 请求失败 $uri: $e');
      return {'error': e.toString()};
    } finally {
      client.close(force: true);
    }
  }

  /// 流式下载对端文件到本地路径（带大小上限）
  static Future<Map<String, dynamic>> downloadToFile(
    String ip,
    String path,
    String destPath, {
    Map<String, String>? headers,
    Duration timeout = const Duration(minutes: 5),
    int? maxBytes,
    void Function(int received, int? total)? onProgress,
  }) async {
    final uri = Uri.parse('https://$ip:$peerPort$path');
    final client = _client(connectionTimeout: const Duration(seconds: 8));
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      headers?.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      final contentLen = res.contentLength >= 0 ? res.contentLength : null;
      final byteLimit = maxBytes ?? kMaxPreviewBytes;
      if (contentLen != null && contentLen > byteLimit) {
        await res.drain();
        return {
          'error': PreviewTooLargeException(contentLen).toString(),
          'statusCode': 413,
        };
      }
      if (res.statusCode != 200) {
        final body = await res.transform(utf8.decoder).join();
        String msg = 'HTTP ${res.statusCode}';
        try {
          final decoded = json.decode(body);
          if (decoded is Map && decoded['data'] != null) {
            msg = decoded['data'].toString();
          } else if (body.isNotEmpty) {
            msg = body;
          }
        } catch (_) {
          if (body.isNotEmpty) msg = body;
        }
        return {'error': msg, 'statusCode': res.statusCode};
      }

      final file = File(destPath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.timeout(timeout)) {
          received += chunk.length;
          if (received > byteLimit) {
            await sink.close();
            await file.delete();
            return {
              'error': PreviewTooLargeException(received).toString(),
              'statusCode': 413,
            };
          }
          sink.add(chunk);
          onProgress?.call(received, contentLen);
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        try {
          await file.delete();
        } catch (_) {}
        rethrow;
      }
      return {
        'path': destPath,
        'contentType': res.headers.contentType?.mimeType ??
            res.headers.value('content-type') ??
            'application/octet-stream',
        'bytes': received,
      };
    } on SocketException catch (e) {
      debugPrint('[peer] 下载失败 $uri: $e');
      return {
        'error': '对端数据管理不可达（需同局域网且对端已打开数据管理）',
      };
    } on TimeoutException catch (_) {
      return {'error': '下载对端文件超时（需同局域网且对端已打开数据管理）'};
    } catch (e) {
      debugPrint('[peer] 下载失败 $uri: $e');
      return {'error': e.toString()};
    } finally {
      client.close(force: true);
    }
  }

  /// GET → 原始字节（小文件兼容；大文件请用 downloadToFile）
  static Future<Map<String, dynamic>> getBytes(
    String ip,
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(minutes: 3),
    int? maxBytes,
  }) async {
    final temp = await Directory.systemTemp.createTemp('datakeep_peer_');
    final dest = '${temp.path}/download.bin';
    final result = await downloadToFile(
      ip,
      path,
      dest,
      headers: headers,
      timeout: timeout,
      maxBytes: maxBytes,
    );
    if (result.containsKey('error')) {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
      return result;
    }
    try {
      final bytes = await File(dest).readAsBytes();
      await temp.delete(recursive: true);
      return {
        'bytes': bytes,
        'contentType': result['contentType'],
      };
    } catch (e) {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
      return {'error': e.toString()};
    }
  }

  /// PUT 原始字节到对端
  static Future<Map<String, dynamic>> putBytes(
    String ip,
    String path,
    List<int> body, {
    Map<String, String>? headers,
    String contentType = 'application/octet-stream',
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final uri = Uri.parse('https://$ip:$peerPort$path');
    final client = _client(connectionTimeout: const Duration(seconds: 8));
    try {
      final req = await client.putUrl(uri).timeout(const Duration(seconds: 15));
      headers?.forEach(req.headers.set);
      req.headers.set(HttpHeaders.contentTypeHeader, contentType);
      req.headers.contentLength = body.length;
      req.add(body);
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return {
          'error': text.isNotEmpty ? text : 'HTTP ${res.statusCode}',
          'statusCode': res.statusCode,
        };
      }
      return {'ok': true, 'statusCode': res.statusCode};
    } on SocketException catch (e) {
      debugPrint('[peer] 上传失败 $uri: $e');
      return {
        'error': '对端数据管理不可达（需同局域网且对端已打开数据管理）',
      };
    } on TimeoutException catch (_) {
      return {'error': '上传对端超时（需同局域网且对端已打开数据管理）'};
    } catch (e) {
      debugPrint('[peer] 上传失败 $uri: $e');
      return {'error': e.toString()};
    } finally {
      client.close(force: true);
    }
  }

  /// DELETE 对端文件
  static Future<Map<String, dynamic>> delete(
    String ip,
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = Uri.parse('https://$ip:$peerPort$path');
    final client = _client();
    try {
      final req = await client.deleteUrl(uri).timeout(timeout);
      headers?.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return {
          'error': text.isNotEmpty ? text : 'HTTP ${res.statusCode}',
          'statusCode': res.statusCode,
        };
      }
      return {'ok': true, 'statusCode': res.statusCode};
    } on SocketException {
      return {
        'error': '对端数据管理不可达（需同局域网且对端已打开数据管理）',
      };
    } on TimeoutException catch (_) {
      return {'error': '删除对端文件超时'};
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      client.close(force: true);
    }
  }
}
