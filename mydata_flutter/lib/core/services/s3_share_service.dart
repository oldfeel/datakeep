import 'package:minio/io.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as p;
import 's3_share_config.dart';

/// 上传到 S3 兼容存储并生成预签名下载链接
class S3ShareService {
  S3ShareService._();

  static Minio _client(S3ShareConfig c) {
    var end = c.endpoint.trim();
    end = end.replaceFirst(RegExp(r'^https?://'), '');
    end = end.replaceAll(RegExp(r'/$'), '');
    return Minio(
      endPoint: end,
      accessKey: c.accessKey,
      secretKey: c.secretKey,
      region: c.region.isEmpty ? null : c.region,
      useSSL: c.useSSL,
    );
  }

  /// 上传本地文件，返回预签名 GET URL
  static Future<String> uploadAndPresign({
    required S3ShareConfig config,
    required String localPath,
    required Duration expiry,
    void Function(int sent)? onProgress,
  }) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 S3 兼容存储（推荐七牛）');
    }
    final objectKey =
        'mydata-share/${DateTime.now().millisecondsSinceEpoch}_${p.basename(localPath)}';

    final client = _client(config);
    await client.fPutObject(
      config.bucket,
      objectKey,
      localPath,
      onProgress: onProgress,
    );

    final url = await client.presignedGetObject(
      config.bucket,
      objectKey,
      expires: expiry.inSeconds.clamp(60, 7 * 24 * 3600),
    );
    return url;
  }
}
