import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';
import 'package:minio/io.dart';
import 'package:minio/minio.dart';
import 'package:path/path.dart' as p;

import 's3_share_config.dart';
import 's3_share_history.dart';

/// 上传到 S3 兼容存储并生成预签名下载链接
class S3ShareService {
  S3ShareService._();

  /// 带提取码的分享建议不超过此大小（需整文件加密）
  static const maxPasswordShareBytes = 200 * 1024 * 1024;

  static String _newId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Minio _client(S3ShareConfig c) {
    final n = c.normalized();
    return Minio(
      endPoint: n.endpoint,
      accessKey: n.accessKey,
      secretKey: n.secretKey,
      region: n.region,
      useSSL: n.useSSL,
      // path-style：https://s3.cn-east-1.qiniucs.com/bucket/key
      pathStyle: true,
    );
  }

  static String _bucket(S3ShareConfig c) => c.normalized().bucket;

  static int _expirySeconds(Duration expiry) =>
      expiry.inSeconds.clamp(60, 7 * 24 * 3600);

  /// 与路径无关的文件指纹（同名+大小+修改时间未变则可复用云端对象）
  static Future<String> fileFingerprint(String localPath) async {
    final file = File(localPath);
    final st = await file.stat();
    final base = p.basename(localPath);
    return sha256
        .convert(utf8.encode(
          '$base|${st.size}|${st.modified.millisecondsSinceEpoch}',
        ))
        .toString()
        .substring(0, 32);
  }

  static String plainObjectKey(String fingerprint, String fileName) =>
      'datakeep-share/plain/${fingerprint}_${_safeObjectFileName(fileName)}';

  /// 对象 key 只用安全 ASCII，避免空格/括号等导致七牛 Forbidden / 签名失败
  /// 展示用文件名仍保存在分享记录里。
  static String _safeObjectFileName(String fileName) {
    final base = p.basename(fileName);
    final ext = p.extension(base).toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');
    final name = p.basenameWithoutExtension(base);
    var safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    safe = safe.replaceAll(RegExp(r'_+'), '_');
    safe = safe.replaceAll(RegExp(r'^_|_$'), '');
    if (safe.isEmpty) safe = 'file';
    if (safe.length > 80) safe = safe.substring(0, 80);
    return '$safe$ext';
  }

  static String _friendlyMinioError(Object e) {
    final s = e.toString();
    if (s.contains('Forbidden') || s.contains('AccessDenied')) {
      return '上传被拒绝（Forbidden）。请检查：\n'
          '1) AccessKey/SecretKey 是否有该空间写权限\n'
          '2) Bucket 名是否正确\n'
          '3) 已自动避开文件名中的空格/括号，可再试一次「强制重新上传」';
    }
    return s;
  }

  static String _passwordPrefix(String fingerprint, String password) {
    final pwHash = sha256
        .convert(utf8.encode(password))
        .toString()
        .substring(0, 16);
    return 'datakeep-share/enc/$fingerprint/$pwHash';
  }

  /// 上传（或复用）并生成分享记录
  static Future<S3ShareResult> share({
    required S3ShareConfig config,
    required String localPath,
    required Duration expiry,
    String? password,
    bool forceReupload = false,
    void Function(int sent)? onProgress,
  }) async {
    if (!config.isConfigured) {
      throw Exception('请先在设置中配置 S3 兼容存储（推荐七牛）');
    }
    final pw = password?.trim() ?? '';
    try {
      if (pw.isNotEmpty) {
        return await _shareWithPassword(
          config: config,
          localPath: localPath,
          expiry: expiry,
          password: pw,
          forceReupload: forceReupload,
          onProgress: onProgress,
        );
      }
      return await _sharePlain(
        config: config,
        localPath: localPath,
        expiry: expiry,
        forceReupload: forceReupload,
        onProgress: onProgress,
      );
    } catch (e) {
      throw Exception(_friendlyMinioError(e));
    }
  }

  static Future<bool> _objectExists(
    Minio client,
    String bucket,
    String key,
  ) async {
    try {
      await client.statObject(bucket, key);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 刷新预签名（无提取码直接改 URL；有提取码则重写解锁页，不重传数据文件）
  static Future<S3ShareRecord> refreshLink({
    required S3ShareConfig config,
    required S3ShareRecord record,
    required Duration expiry,
  }) async {
    if (!config.isConfigured) {
      throw Exception('请先配置 S3 兼容存储');
    }
    final client = _client(config);
    final bucket = _bucket(config);
    if (!await _objectExists(client, bucket, record.objectKey)) {
      throw Exception('云端文件已不存在，请使用「强制重新上传」');
    }
    final seconds = _expirySeconds(expiry);
    final expiresAt = DateTime.now().add(Duration(seconds: seconds));

    if (record.hasPassword) {
      final gateKey = record.gateObjectKey;
      final salt = record.saltB64;
      final iv = record.ivB64;
      if (gateKey == null || salt == null || iv == null) {
        throw Exception('该提取码分享缺少元数据，请重新生成');
      }
      final dataUrl = await client.presignedGetObject(
        bucket,
        record.objectKey,
        expires: seconds,
      );
      final html = utf8.encode(buildGateHtml(
        fileName: record.fileName,
        saltB64: salt,
        ivB64: iv,
        dataUrl: dataUrl,
      ));
      await client.putObject(
        bucket,
        gateKey,
        Stream<Uint8List>.value(Uint8List.fromList(html)),
        size: html.length,
        metadata: {'content-type': 'text/html; charset=utf-8'},
      );
      final gateUrl = await client.presignedGetObject(
        bucket,
        gateKey,
        expires: seconds,
      );
      final updated = record.copyWith(url: gateUrl, expiresAt: expiresAt);
      await S3ShareHistoryStore.update(updated);
      return updated;
    }

    final url = await client.presignedGetObject(
      bucket,
      record.objectKey,
      expires: seconds,
    );
    final updated = record.copyWith(url: url, expiresAt: expiresAt);
    await S3ShareHistoryStore.update(updated);
    return updated;
  }

  static Future<S3ShareResult> _sharePlain({
    required S3ShareConfig config,
    required String localPath,
    required Duration expiry,
    required bool forceReupload,
    void Function(int sent)? onProgress,
  }) async {
    final fp = await fileFingerprint(localPath);
    final fileName = p.basename(localPath);
    final objectKey = plainObjectKey(fp, fileName);
    final client = _client(config);
    final seconds = _expirySeconds(expiry);
    final expiresAt = DateTime.now().add(Duration(seconds: seconds));
    final fileSize = await File(localPath).length();

    if (!forceReupload) {
      final hit = await S3ShareHistoryStore.findReusable(
        localPath: localPath,
        fileFingerprint: fp,
        wantPassword: false,
      );
      if (hit != null) {
        try {
          final updated = await refreshLink(
            config: config,
            record: hit.copyWith(
              localPath: localPath,
              fileFingerprint: fp,
            ),
            expiry: expiry,
          );
          onProgress?.call(fileSize);
          return S3ShareResult(record: updated, reusedObject: true);
        } catch (_) {
          // 云端对象缺失，清掉失效记录后重新上传
          await S3ShareHistoryStore.remove(hit.id);
        }
      }
      try {
        await client.statObject(_bucket(config), objectKey);
        final url = await client.presignedGetObject(
          _bucket(config),
          objectKey,
          expires: seconds,
        );
        final record = S3ShareRecord(
          id: _newId(),
          localPath: localPath,
          fileName: fileName,
          fileFingerprint: fp,
          objectKey: objectKey,
          url: url,
          createdAt: DateTime.now(),
          expiresAt: expiresAt,
        );
        await S3ShareHistoryStore.add(record);
        onProgress?.call(fileSize);
        return S3ShareResult(record: record, reusedObject: true);
      } catch (_) {}
    }

    await client.fPutObject(
      _bucket(config),
      objectKey,
      localPath,
      onProgress: onProgress,
    );

    final url = await client.presignedGetObject(
      _bucket(config),
      objectKey,
      expires: seconds,
    );
    final record = S3ShareRecord(
      id: _newId(),
      localPath: localPath,
      fileName: fileName,
      fileFingerprint: fp,
      objectKey: objectKey,
      url: url,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );
    await S3ShareHistoryStore.add(record);
    return S3ShareResult(record: record, reusedObject: false);
  }

  static Future<S3ShareResult> _shareWithPassword({
    required S3ShareConfig config,
    required String localPath,
    required Duration expiry,
    required String password,
    required bool forceReupload,
    void Function(int sent)? onProgress,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    if (size > maxPasswordShareBytes) {
      throw Exception(
        '带提取码的分享暂支持不超过 '
        '${maxPasswordShareBytes ~/ (1024 * 1024)}MB 的文件',
      );
    }

    final fp = await fileFingerprint(localPath);
    final fileName = p.basename(localPath);
    final prefix = _passwordPrefix(fp, password);
    final dataKey = '$prefix/data.bin';
    final gateKey = '$prefix/index.html';

    if (!forceReupload) {
      final hit = await S3ShareHistoryStore.findReusable(
        localPath: localPath,
        fileFingerprint: fp,
        wantPassword: true,
        password: password,
      );
      if (hit != null) {
        try {
          final updated = await refreshLink(
            config: config,
            record: hit.copyWith(
              localPath: localPath,
              fileFingerprint: fp,
            ),
            expiry: expiry,
          );
          onProgress?.call(size);
          return S3ShareResult(record: updated, reusedObject: true);
        } catch (_) {
          // 云端 data.bin 缺失（例如早期 endpoint 误配），清记录后重传
          await S3ShareHistoryStore.remove(hit.id);
        }
      }
    }

    onProgress?.call(0);
    final clear = await file.readAsBytes();
    final salt = _randomBytes(16);
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secretKey = await pbkdf2.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final algorithm = AesGcm.with256bits();
    final box = await algorithm.encrypt(clear, secretKey: secretKey);
    final cipherWithTag = Uint8List.fromList([
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
    onProgress?.call(size ~/ 3);

    final client = _client(config);
    final seconds = _expirySeconds(expiry);
    final expiresAt = DateTime.now().add(Duration(seconds: seconds));
    final saltB64 = base64Encode(salt);
    final ivB64 = base64Encode(box.nonce);

    await client.putObject(
      _bucket(config),
      dataKey,
      Stream<Uint8List>.value(cipherWithTag),
      size: cipherWithTag.length,
    );
    if (!await _objectExists(client, _bucket(config), dataKey)) {
      throw Exception('加密文件上传失败，请重试');
    }
    onProgress?.call((size * 2) ~/ 3);

    final dataUrl = await client.presignedGetObject(
      _bucket(config),
      dataKey,
      expires: seconds,
    );
    final html = utf8.encode(buildGateHtml(
      fileName: fileName,
      saltB64: saltB64,
      ivB64: ivB64,
      dataUrl: dataUrl,
    ));
    await client.putObject(
      _bucket(config),
      gateKey,
      Stream<Uint8List>.value(Uint8List.fromList(html)),
      size: html.length,
      metadata: {'content-type': 'text/html; charset=utf-8'},
    );

    final gateUrl = await client.presignedGetObject(
      _bucket(config),
      gateKey,
      expires: seconds,
    );
    onProgress?.call(size);

    final record = S3ShareRecord(
      id: _newId(),
      localPath: localPath,
      fileName: fileName,
      fileFingerprint: fp,
      objectKey: dataKey,
      gateObjectKey: gateKey,
      url: gateUrl,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      hasPassword: true,
      password: password,
      saltB64: saltB64,
      ivB64: ivB64,
    );
    await S3ShareHistoryStore.add(record);
    return S3ShareResult(record: record, reusedObject: false);
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  /// 浏览器解锁页（提取码 + AES-GCM）
  static String buildGateHtml({
    required String fileName,
    required String saltB64,
    required String ivB64,
    required String dataUrl,
  }) {
    final safeName = const HtmlEscape().convert(fileName);
    String jsStr(String s) => json.encode(s);
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>DataKeep 分享 · $safeName</title>
<style>
body{font-family:system-ui,sans-serif;max-width:420px;margin:48px auto;padding:0 16px;color:#222}
h1{font-size:1.25rem;margin:0 0 8px}
.muted{color:#666;font-size:.9rem;margin-bottom:24px}
input{width:100%;box-sizing:border-box;padding:12px;font-size:1rem;border:1px solid #ccc;border-radius:8px}
button{margin-top:12px;width:100%;padding:12px;font-size:1rem;border:0;border-radius:8px;background:#1976d2;color:#fff;cursor:pointer}
button:disabled{opacity:.6}
.err{color:#c62828;margin-top:12px;min-height:1.2em}
</style>
</head>
<body>
<h1>$safeName</h1>
<p class="muted">此文件受提取码保护，输入正确后即可下载。</p>
<input id="pw" type="password" placeholder="提取码" autocomplete="off"/>
<button id="btn" type="button">解锁并下载</button>
<p class="err" id="err"></p>
<script>
const SALT = ${jsStr(saltB64)};
const IV = ${jsStr(ivB64)};
const DATA_URL = ${jsStr(dataUrl)};
const FILE_NAME = ${jsStr(fileName)};
function b64ToBytes(b64){
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i=0;i<bin.length;i++) out[i]=bin.charCodeAt(i);
  return out;
}
document.getElementById('btn').onclick = async () => {
  const err = document.getElementById('err');
  const btn = document.getElementById('btn');
  err.textContent = '';
  const password = document.getElementById('pw').value;
  if (!password) { err.textContent = '请输入提取码'; return; }
  btn.disabled = true;
  try {
    const keyMaterial = await crypto.subtle.importKey(
      'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveKey']);
    const key = await crypto.subtle.deriveKey(
      {name:'PBKDF2', salt:b64ToBytes(SALT), iterations:100000, hash:'SHA-256'},
      keyMaterial, {name:'AES-GCM', length:256}, false, ['decrypt']);
    const res = await fetch(DATA_URL);
    if (!res.ok) throw new Error('下载加密数据失败: ' + res.status);
    const buf = await res.arrayBuffer();
    const plain = await crypto.subtle.decrypt(
      {name:'AES-GCM', iv:b64ToBytes(IV)}, key, buf);
    const blob = new Blob([plain]);
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = FILE_NAME;
    a.click();
    URL.revokeObjectURL(a.href);
  } catch (e) {
    const msg = (e && e.message) ? String(e.message) : String(e);
    if (msg.indexOf('下载加密数据失败') >= 0) {
      err.textContent = msg + '（云端文件缺失，请在 DataKeep 中强制重新上传后再分享）';
    } else {
      err.textContent = '提取码错误，或加密数据已损坏/失效';
    }
    console.error(e);
  } finally {
    btn.disabled = false;
  }
};
</script>
</body>
</html>''';
  }
}

class S3ShareResult {
  final S3ShareRecord record;
  /// true：复用了已上传的数据对象，未重新上传文件本体
  final bool reusedObject;

  const S3ShareResult({
    required this.record,
    required this.reusedObject,
  });
}
