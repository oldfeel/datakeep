import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/services/native_service.dart';
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
                if (Platform.isIOS) ...[
                  const SizedBox(height: 12),
                  const _IosBackgroundSyncSection(),
                ],
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

/// iOS 后台同步开关（系统调度，非持续在线）
class _IosBackgroundSyncSection extends StatefulWidget {
  const _IosBackgroundSyncSection();

  @override
  State<_IosBackgroundSyncSection> createState() =>
      _IosBackgroundSyncSectionState();
}

class _IosBackgroundSyncSectionState extends State<_IosBackgroundSyncSection> {
  bool _loading = true;
  bool _long = true;
  bool _short = false;
  String? _lastRun;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await NativeService.getBackgroundSyncStatus();
    if (!mounted) return;
    final ms = s['lastRunEpochMs'];
    String? last;
    if (ms is int && ms > 0) {
      last = DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toString();
    }
    setState(() {
      _long = s['longEnabled'] != false;
      _short = s['shortEnabled'] == true;
      _lastRun = last;
      _loading = false;
    });
  }

  Future<void> _set({bool? longEnabled, bool? shortEnabled}) async {
    final s = await NativeService.setBackgroundSyncEnabled(
      longEnabled: longEnabled,
      shortEnabled: shortEnabled,
    );
    if (!mounted) return;
    setState(() {
      _long = s['longEnabled'] != false;
      _short = s['shortEnabled'] == true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('后台同步', style: theme.textTheme.titleSmall),
        Text(
          '由系统在空闲/充电时唤醒，不能保证持续在线。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('长后台同步'),
          subtitle: const Text('充电且有网络时（推荐）'),
          value: _long,
          onChanged: (v) => _set(longEnabled: v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('短后台刷新'),
          subtitle: const Text('更频繁、时长更短'),
          value: _short,
          onChanged: (v) => _set(shortEnabled: v),
        ),
        if (_lastRun != null)
          Text(
            '上次后台运行：$_lastRun',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
