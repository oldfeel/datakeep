import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_manifest.dart';

/// 判定应用是否允许应用内 AI 写文件。
///
/// 规则（与 app-package-spec 一致）：
/// 1. `app.json` 的 `aiEditable` 必须为 true（缺省禁止）
/// 2. 防御：代码根存在 `package.json` 时仍禁止（避免误标可编辑）
///
/// 不得仅凭「无 package.json」就开放 AI。
class AppAiGate {
  AppAiGate._();

  static bool isAiWritable({
    required AppManifest? manifest,
    required String codeRoot,
  }) {
    if (manifest == null || !manifest.aiEditable) return false;
    if (codeRoot.isEmpty) return false;
    final pkg = File(p.join(codeRoot, 'package.json'));
    if (pkg.existsSync()) return false;
    return true;
  }

  /// 为何禁用的用户可读说明（可写时返回 null）
  static String? denyReason({
    required AppManifest? manifest,
    required String codeRoot,
  }) {
    if (manifest == null) {
      return '无法读取 app.json';
    }
    if (!manifest.aiEditable) {
      return '此应用需构建工具链或不支持应用内 AI 修改（aiEditable≠true）';
    }
    if (File(p.join(codeRoot, 'package.json')).existsSync()) {
      return '检测到 package.json，为防止误改源码工程，已禁用应用内 AI 写文件';
    }
    return null;
  }
}
