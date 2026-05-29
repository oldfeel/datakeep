import 'dart:io';
import 'package:flutter/foundation.dart';

class CertManager {
  final String certDir;

  CertManager(this.certDir);

  String get certFile => '$certDir/cert.pem';
  String get keyFile => '$certDir/key.pem';

  bool get exists => File(certFile).existsSync() && File(keyFile).existsSync();

  SecurityContext createSecurityContext() {
    final ctx = SecurityContext();
    if (!exists) {
      debugPrint('证书不存在，尝试生成...');
      _generateSelfSigned();
    }
    ctx.useCertificateChain(certFile);
    ctx.usePrivateKey(keyFile);
    return ctx;
  }

  void _generateSelfSigned() {
    Directory(certDir).createSync(recursive: true);
    // 使用 openssl 生成自签名证书（桌面端可用）
    try {
      Process.runSync('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', keyFile,
        '-out', certFile,
        '-days', '3650',
        '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
      ]);
      debugPrint('自签名证书生成完成');
    } catch (e) {
      debugPrint('openssl 生成证书失败: $e（使用 Go 生成）');
    }
  }
}
