import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 局域网对端 MyData HTTPS 客户端（自签名 + 私网 IP）
class PeerClient {
  PeerClient._();

  static const int peerPort = 8443;
  static const String deviceIdHeader = 'X-MyData-Device-ID';

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

  static HttpClient _client() {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 3);
    c.badCertificateCallback = (cert, host, port) {
      return _isPrivateIpv4(host) && port == peerPort;
    };
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
      return {'error': '对端 MyData 未运行或不可达'};
    } on TimeoutException catch (_) {
      return {'error': '连接对端超时'};
    } catch (e) {
      debugPrint('[peer] 请求失败 $uri: $e');
      return {'error': e.toString()};
    } finally {
      client.close(force: true);
    }
  }
}
