import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 文件夹对单个设备的访问权限
enum FolderAccess {
  sync,
  readonly,
  hidden;

  static FolderAccess? tryParse(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'sync':
        return FolderAccess.sync;
      case 'readonly':
      case 'read_only':
      case 'ro':
        return FolderAccess.readonly;
      case 'hidden':
        return FolderAccess.hidden;
      default:
        return null;
    }
  }

  String get apiValue {
    switch (this) {
      case FolderAccess.sync:
        return 'sync';
      case FolderAccess.readonly:
        return 'readonly';
      case FolderAccess.hidden:
        return 'hidden';
    }
  }

  String get label {
    switch (this) {
      case FolderAccess.sync:
        return '同步';
      case FolderAccess.readonly:
        return '只读';
      case FolderAccess.hidden:
        return '隐藏';
    }
  }

  bool get isPeerVisible =>
      this == FolderAccess.sync || this == FolderAccess.readonly;
}

/// 本机 folder_acl.json：{ folderId: { DEVICE_NORM: "sync"|"readonly"|"hidden" } }
class FolderAclStore {
  String _filePath = '';
  /// folderId → (deviceNorm → access)
  Map<String, Map<String, String>> _data = {};

  String get filePath => _filePath;

  Future<void> init(String dataDir) async {
    final dir = Directory(dataDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _filePath = '$dataDir/folder_acl.json';
    await _load();
  }

  Future<void> _load() async {
    try {
      final f = File(_filePath);
      if (!f.existsSync()) {
        _data = {};
        return;
      }
      final decoded = json.decode(await f.readAsString());
      if (decoded is! Map) {
        _data = {};
        return;
      }
      final out = <String, Map<String, String>>{};
      for (final e in decoded.entries) {
        final folderId = e.key.toString();
        final v = e.value;
        if (v is! Map) continue;
        out[folderId] = {
          for (final d in v.entries)
            _norm(d.key.toString()): d.value.toString(),
        };
      }
      _data = out;
    } catch (e) {
      debugPrint('[acl] 加载失败: $e');
      _data = {};
    }
  }

  Future<void> _save() async {
    final f = File(_filePath);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
  }

  static String _norm(String id) =>
      id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  /// 显式配置；无记录返回 null
  FolderAccess? getExplicit(String folderId, String deviceId) {
    final m = _data[folderId];
    if (m == null) return null;
    return FolderAccess.tryParse(m[_norm(deviceId)]);
  }

  /// 解析有效权限：有显式配置用显式；否则 Syncthing 已共享 → sync，否则 hidden
  FolderAccess resolve(
    String folderId,
    String deviceId, {
    required bool syncthingShared,
  }) {
    return getExplicit(folderId, deviceId) ??
        (syncthingShared ? FolderAccess.sync : FolderAccess.hidden);
  }

  /// 某文件夹全部设备权限（原始存储，key 已归一化）
  Map<String, FolderAccess> getFolderAccessMap(String folderId) {
    final m = _data[folderId] ?? {};
    final out = <String, FolderAccess>{};
    for (final e in m.entries) {
      final a = FolderAccess.tryParse(e.value);
      if (a != null) out[e.key] = a;
    }
    return out;
  }

  /// 覆盖写入某文件夹的权限表（deviceId 可为带连字符的原始 ID）
  Future<void> setFolderPermissions(
    String folderId,
    Map<String, FolderAccess> permissions,
  ) async {
    _data[folderId] = {
      for (final e in permissions.entries) _norm(e.key): e.value.apiValue,
    };
    await _save();
  }
}
