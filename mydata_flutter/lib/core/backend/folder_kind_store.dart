import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// 本机 folder_kind.json：{ folderId: "folder" | "app" }
class FolderKindStore {
  String _filePath = '';
  Map<String, String> _data = {};

  String get filePath => _filePath;

  Future<void> init(String dataDir) async {
    final dir = Directory(dataDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _filePath = '$dataDir/folder_kind.json';
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
      _data = {
        for (final e in decoded.entries) e.key.toString(): e.value.toString(),
      };
    } catch (e) {
      debugPrint('[kind] 加载失败: $e');
      _data = {};
    }
  }

  Future<void> _save() async {
    final f = File(_filePath);
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
  }

  String getKind(String folderId) {
    final k = _data[folderId];
    if (k == 'app') return 'app';
    return 'folder';
  }

  Future<void> setKind(String folderId, String kind) async {
    final v = kind == 'app' ? 'app' : 'folder';
    _data[folderId] = v;
    await _save();
  }

  Future<void> remove(String folderId) async {
    _data.remove(folderId);
    await _save();
  }
}
