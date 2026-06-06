import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class CertManager {
  final String certDir;

  CertManager(this.certDir);

  String get certFile => '$certDir/cert.pem';
  String get keyFile => '$certDir/key.pem';

  bool get exists => File(certFile).existsSync() && File(keyFile).existsSync();

  /// 确保证书文件存在（桌面端 openssl 生成，移动端从 assets 复制）
  Future<void> ensureReady() async {
    if (exists) return;
    Directory(certDir).createSync(recursive: true);

    if (!Platform.isAndroid && !Platform.isIOS) {
      _generateSelfSignedWithOpenssl();
      if (exists) return;
    }

    await _copyFromAssets();
    if (!exists) {
      throw StateError('无法初始化 HTTPS 证书');
    }
  }

  SecurityContext createSecurityContext() {
    if (!exists) {
      throw StateError('证书未就绪，请先调用 ensureReady()');
    }
    final ctx = SecurityContext();
    ctx.useCertificateChain(certFile);
    ctx.usePrivateKey(keyFile);
    return ctx;
  }

  void _generateSelfSignedWithOpenssl() {
    try {
      final result = Process.runSync('openssl', [
        'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', keyFile,
        '-out', certFile,
        '-days', '3650',
        '-subj', '/CN=localhost',
        '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1',
      ]);
      if (result.exitCode == 0) {
        debugPrint('自签名证书生成完成');
      }
    } catch (e) {
      debugPrint('openssl 生成证书失败: $e');
    }
  }

  Future<void> _copyFromAssets() async {
    try {
      final cert = await rootBundle.load('assets/certs/cert.pem');
      final key = await rootBundle.load('assets/certs/key.pem');
      await File(certFile).writeAsBytes(cert.buffer.asUint8List());
      await File(keyFile).writeAsBytes(key.buffer.asUint8List());
      debugPrint('已从 assets 复制 HTTPS 证书');
    } catch (e) {
      debugPrint('从 assets 复制证书失败: $e');
    }
  }
}
