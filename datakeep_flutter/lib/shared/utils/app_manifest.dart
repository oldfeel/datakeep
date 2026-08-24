import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 应用包清单（app.json）
class AppManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String entry;
  final String? icon;

  const AppManifest({
    required this.id,
    required this.name,
    this.version = '',
    this.description = '',
    this.entry = 'index.html',
    this.icon,
  });

  factory AppManifest.fromJson(Map<String, dynamic> json) {
    return AppManifest(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      version: json['version']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      entry: json['entry']?.toString().trim() ?? 'index.html',
      icon: json['icon']?.toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'entry': entry,
        if (icon != null && icon!.isNotEmpty) 'icon': icon,
      };

  /// 从应用目录读取 app.json；失败返回 null。
  static AppManifest? tryReadFromDirectory(String appPath) {
    if (appPath.isEmpty) return null;
    try {
      final file = File(p.join(appPath, 'app.json'));
      if (!file.existsSync()) return null;
      final raw = json.decode(file.readAsStringSync());
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final manifest = AppManifest.fromJson(map);
      if (manifest.id.isEmpty && manifest.name.isEmpty) return null;
      return manifest;
    } catch (_) {
      return null;
    }
  }

  /// 列表/标题优先用 name，否则回退 id 或目录名。
  String displayName({String? fallback}) {
    if (name.isNotEmpty) return name;
    if (id.isNotEmpty) return id;
    return fallback ?? '应用';
  }
}
