import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 一次互联网分享记录（本机持久化）
class S3ShareRecord {
  final String id;
  final String localPath;
  final String fileName;
  /// 文件指纹（basename|size|mtime），用于跨路径复用云端对象
  final String? fileFingerprint;
  /// 数据对象 key（明文或密文）
  final String objectKey;
  /// 带提取码时的解锁页 key
  final String? gateObjectKey;
  /// 可发给对方的链接（直链或解锁页）
  final String url;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool hasPassword;
  /// 提取码（仅本机可查看，用于再次复制）
  final String? password;
  /// 带提取码时用于刷新解锁页（与 Web Crypto 一致）
  final String? saltB64;
  final String? ivB64;

  const S3ShareRecord({
    required this.id,
    required this.localPath,
    required this.fileName,
    this.fileFingerprint,
    required this.objectKey,
    this.gateObjectKey,
    required this.url,
    required this.createdAt,
    required this.expiresAt,
    this.hasPassword = false,
    this.password,
    this.saltB64,
    this.ivB64,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get remaining {
    final d = expiresAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String get remainingLabel {
    if (isExpired) return '已过期';
    final d = remaining;
    if (d.inDays >= 1) return '剩余 ${d.inDays} 天';
    if (d.inHours >= 1) return '剩余 ${d.inHours} 小时';
    if (d.inMinutes >= 1) return '剩余 ${d.inMinutes} 分钟';
    return '即将过期';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'localPath': localPath,
        'fileName': fileName,
        'fileFingerprint': fileFingerprint,
        'objectKey': objectKey,
        'gateObjectKey': gateObjectKey,
        'url': url,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'hasPassword': hasPassword,
        'password': password,
        'saltB64': saltB64,
        'ivB64': ivB64,
      };

  factory S3ShareRecord.fromJson(Map<String, dynamic> j) => S3ShareRecord(
        id: j['id']?.toString() ?? '',
        localPath: j['localPath']?.toString() ?? '',
        fileName: j['fileName']?.toString() ?? '',
        fileFingerprint: j['fileFingerprint']?.toString(),
        objectKey: j['objectKey']?.toString() ?? '',
        gateObjectKey: j['gateObjectKey']?.toString(),
        url: j['url']?.toString() ?? '',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        expiresAt: DateTime.tryParse(j['expiresAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        hasPassword: j['hasPassword'] == true,
        password: j['password']?.toString(),
        saltB64: j['saltB64']?.toString(),
        ivB64: j['ivB64']?.toString(),
      );

  S3ShareRecord copyWith({
    String? url,
    DateTime? expiresAt,
    String? localPath,
    String? fileFingerprint,
  }) =>
      S3ShareRecord(
        id: id,
        localPath: localPath ?? this.localPath,
        fileName: fileName,
        fileFingerprint: fileFingerprint ?? this.fileFingerprint,
        objectKey: objectKey,
        gateObjectKey: gateObjectKey,
        url: url ?? this.url,
        createdAt: createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
        hasPassword: hasPassword,
        password: password,
        saltB64: saltB64,
        ivB64: ivB64,
      );
}

class S3ShareHistoryStore {
  static const _key = 's3_share_history_v1';
  static const _maxRecords = 100;

  static Future<List<S3ShareRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      return list
          .map((e) => S3ShareRecord.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<S3ShareRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = records.take(_maxRecords).toList();
    await prefs.setString(
      _key,
      json.encode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> add(S3ShareRecord record) async {
    final all = await loadAll();
    all.removeWhere((r) => r.id == record.id);
    // 同一对象 key 只保留最新一条，避免重复历史
    all.removeWhere((r) =>
        r.objectKey == record.objectKey &&
        r.hasPassword == record.hasPassword &&
        (r.password ?? '') == (record.password ?? ''));
    all.insert(0, record);
    await _saveAll(all);
  }

  static Future<void> update(S3ShareRecord record) async {
    final all = await loadAll();
    final i = all.indexWhere((r) => r.id == record.id);
    if (i >= 0) {
      all[i] = record;
    } else {
      all.insert(0, record);
    }
    await _saveAll(all);
  }

  static Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((r) => r.id == id);
    await _saveAll(all);
  }

  /// 某本地文件的未过期分享（最新在前）
  static Future<List<S3ShareRecord>> forLocalPath(String localPath) async {
    final all = await loadAll();
    return all
        .where((r) => r.localPath == localPath && !r.isExpired)
        .toList();
  }

  /// 查找可复用的云端对象（含已过期记录：对象通常仍在桶里）
  static Future<S3ShareRecord?> findReusable({
    required String localPath,
    String? fileFingerprint,
    required bool wantPassword,
    String? password,
  }) async {
    final all = await loadAll();
    final pw = password?.trim() ?? '';
    for (final r in all) {
      final pathOk = r.localPath == localPath;
      final fpOk = fileFingerprint != null &&
          fileFingerprint.isNotEmpty &&
          r.fileFingerprint == fileFingerprint;
      if (!pathOk && !fpOk) continue;
      if (wantPassword) {
        if (!r.hasPassword) continue;
        if (pw.isNotEmpty && (r.password ?? '') != pw) continue;
        if (r.gateObjectKey == null ||
            r.saltB64 == null ||
            r.ivB64 == null) {
          continue;
        }
        return r;
      }
      if (r.hasPassword) continue;
      return r;
    }
    return null;
  }
}
