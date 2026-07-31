import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// S3 兼容存储配置（七牛 / 阿里云 / 腾讯云 / MinIO）
class S3ShareConfig {
  final String endpoint;
  final String accessKey;
  final String secretKey;
  final String bucket;
  final String region;
  final bool useSSL;

  const S3ShareConfig({
    required this.endpoint,
    required this.accessKey,
    required this.secretKey,
    required this.bucket,
    this.region = 'us-east-1',
    this.useSSL = true,
  });

  bool get isConfigured =>
      endpoint.isNotEmpty &&
      accessKey.isNotEmpty &&
      secretKey.isNotEmpty &&
      bucket.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'endpoint': endpoint,
        'accessKey': accessKey,
        'secretKey': secretKey,
        'bucket': bucket,
        'region': region,
        'useSSL': useSSL,
      };

  factory S3ShareConfig.fromJson(Map<String, dynamic> j) => S3ShareConfig(
        endpoint: j['endpoint']?.toString() ?? '',
        accessKey: j['accessKey']?.toString() ?? '',
        secretKey: j['secretKey']?.toString() ?? '',
        bucket: j['bucket']?.toString() ?? '',
        region: j['region']?.toString() ?? 'us-east-1',
        useSSL: j['useSSL'] != false,
      );

  static const empty = S3ShareConfig(
    endpoint: '',
    accessKey: '',
    secretKey: '',
    bucket: '',
  );
}

class S3ShareConfigStore {
  static const _key = 's3_share_config';

  static Future<S3ShareConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return S3ShareConfig.empty;
    try {
      return S3ShareConfig.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return S3ShareConfig.empty;
    }
  }

  static Future<void> save(S3ShareConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(config.toJson()));
  }
}
