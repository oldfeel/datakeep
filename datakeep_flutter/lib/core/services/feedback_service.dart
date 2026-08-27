import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'market_service.dart';

/// 意见反馈（提交至 market_server 公网 API）
class FeedbackService {
  FeedbackService._();

  static String _platformLabel() {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  static Future<String> _appVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (e) {
      debugPrint('[feedback] 读取版本失败: $e');
      return 'unknown';
    }
  }

  /// 提交反馈；[contact] 可选
  static Future<void> submit({
    required String content,
    String? contact,
  }) async {
    final base = await MarketService.getBaseUrl();
    final url = Uri.parse('$base/api/feedback');
    final body = jsonEncode({
      'content': content.trim(),
      if (contact != null && contact.trim().isNotEmpty) 'contact': contact.trim(),
      'platform': _platformLabel(),
      'appVersion': await _appVersionLabel(),
    });

    debugPrint('[feedback] POST $url');
    final res = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: body,
        )
        .timeout(const Duration(seconds: 30));

    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (json['code'] != 0) {
      throw Exception(json['data']?.toString() ?? '提交失败');
    }
  }
}
