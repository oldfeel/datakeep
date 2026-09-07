import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Debug 下按 app.json `id` 解析仓库 `examples/*/app.json` 源码目录。
///
/// 若包目录存在 `www/index.html`（Vite 构建产物），返回该 `www/`；否则返回包根。
/// 仅 [kDebugMode] 生效；找不到则返回 null（调用方回退安装目录）。
/// 可用 `--dart-define=DATAKEEP_EXAMPLES_ROOT=/abs/path/to/examples` 覆盖根路径。
String? resolveDevAppSource(String appId) {
  if (!kDebugMode) return null;
  final id = appId.trim();
  if (id.isEmpty) return null;

  final examplesRoot = _resolveExamplesRoot();
  if (examplesRoot == null) return null;

  try {
    final root = Directory(examplesRoot);
    if (!root.existsSync()) return null;
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final meta = File(p.join(entity.path, 'app.json'));
      if (!meta.existsSync()) continue;
      try {
        final raw = json.decode(meta.readAsStringSync());
        if (raw is! Map) continue;
        final foundId = raw['id']?.toString().trim() ?? '';
        if (foundId == id) {
          final pkg = p.normalize(entity.path);
          // Vite 等构建应用：有 www/index.html 时直连构建产物
          final wwwIndex = File(p.join(pkg, 'www', 'index.html'));
          if (wwwIndex.existsSync()) {
            return p.join(pkg, 'www');
          }
          return pkg;
        }
      } catch (_) {
        continue;
      }
    }
  } catch (e) {
    debugPrint('[DevAppSource] 扫描 examples 失败: $e');
  }
  return null;
}

String? _resolveExamplesRoot() {
  const fromDefine = String.fromEnvironment('DATAKEEP_EXAMPLES_ROOT');
  if (fromDefine.trim().isNotEmpty) {
    final defined = p.normalize(fromDefine.trim());
    if (Directory(defined).existsSync()) return defined;
    debugPrint('[DevAppSource] DATAKEEP_EXAMPLES_ROOT 不存在: $defined');
  }

  // 从 cwd 向上找含 examples/ 的仓库根；再试 cwd/../examples（flutter run 常在 datakeep_flutter）
  Directory dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    final candidate = p.join(dir.path, 'examples');
    if (Directory(candidate).existsSync()) {
      return p.normalize(candidate);
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }

  final sibling = p.normalize(p.join(Directory.current.path, '..', 'examples'));
  if (Directory(sibling).existsSync()) return sibling;

  return null;
}
