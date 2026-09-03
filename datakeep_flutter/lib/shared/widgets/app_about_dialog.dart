import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_info.dart';
import '../utils/open_url_external.dart';
import 'app_logo.dart';

/// 用户可见版本（仅 versionName，如 `0.2.3`）
Future<String> loadAppVersionLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final v = info.version.trim();
    if (v.isNotEmpty) return v;
    final b = info.buildNumber.trim();
    return b.isEmpty ? '未知' : b;
  } catch (e) {
    debugPrint('[about] 读取版本失败: $e');
    return '未知';
  }
}

/// 完整版本（含构建号，如 `0.2.3+23`，用于复制排查）
Future<String> loadAppVersionFullLabel() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final v = info.version.trim();
    final b = info.buildNumber.trim();
    if (v.isEmpty) return b.isEmpty ? '未知' : b;
    if (b.isEmpty || b == v) return v;
    return '$v+$b';
  } catch (e) {
    debugPrint('[about] 读取完整版本失败: $e');
    return '未知';
  }
}

String _platformLabel() {
  if (kIsWeb) return 'Web';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isMacOS) return 'macOS';
  if (Platform.isWindows) return 'Windows';
  if (Platform.isLinux) return 'Linux';
  return Platform.operatingSystem;
}

/// 桌面设置菜单 / 移动端侧栏共用的「关于」对话框
Future<void> showDataKeepAboutDialog(BuildContext context) async {
  PackageInfo? info;
  try {
    info = await PackageInfo.fromPlatform();
  } catch (e) {
    debugPrint('[about] 读取版本失败: $e');
  }
  if (!context.mounted) return;

  final version = (info?.version.trim().isNotEmpty == true)
      ? info!.version.trim()
      : '未知';
  final build = info?.buildNumber.trim() ?? '';
  final versionFull = (build.isNotEmpty && build != version)
      ? '$version+$build'
      : version;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return AlertDialog(
        title: Row(
          children: [
            const AppLogo(size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kAppDisplayName),
                  Text(
                    kAppProductName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(kAppTagline, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                _AboutRow(label: '版本', value: version),
                if (build.isNotEmpty && build != version)
                  _AboutRow(label: '构建号', value: build),
                _AboutRow(label: '平台', value: _platformLabel()),
                const SizedBox(height: 8),
                Text(
                  '同步引擎基于 Syncthing（MPL-2.0）。日常加设备、加文件夹、看文件、管共享；'
                  '高级配置请使用应用内「Syncthing 管理页」。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openLink(ctx, kAppWebsiteUrl),
                      icon: const Icon(Icons.language, size: 18),
                      label: const Text('官网'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openLink(ctx, kAppGitHubUrl),
                      icon: const Icon(Icons.code, size: 18),
                      label: const Text('源码'),
                    ),
                    TextButton.icon(
                      onPressed: () => _openLink(ctx, kAppReleasesUrl),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('下载'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: versionFull));
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('已复制 $versionFull')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制版本'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}

Future<void> _openLink(BuildContext context, String url) async {
  final ok = await openUrlExternal(url);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('无法打开链接: $url')),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
