import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/s3_share_config.dart';
import '../../core/services/s3_share_service.dart';
import '../../shared/utils/local_file_path.dart';
import '../pages/s3_share_settings_page.dart';

/// 分享到互联网：上传 S3 → 复制预签名链接
Future<void> showShareToCloudSheet(
  BuildContext context, {
  required String folderPath,
  required String relativePath,
}) async {
  final localPath = folderPath.isEmpty
      ? relativePath
      : joinLocalFilePath(folderPath, relativePath);

  if (!await File(localPath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件不在本机，请先同步后再分享'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ShareSheet(localPath: localPath),
  );
}

class _ShareSheet extends StatefulWidget {
  final String localPath;
  const _ShareSheet({required this.localPath});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  S3ShareConfig _config = S3ShareConfig.empty;
  Duration _expiry = const Duration(hours: 24);
  bool _loading = false;
  double? _progress;
  String? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await S3ShareConfigStore.load();
    if (mounted) setState(() => _config = c);
  }

  Future<void> _upload() async {
    if (!_config.isConfigured) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const S3ShareSettingsPage()),
      );
      await _load();
      if (!_config.isConfigured) return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _url = null;
      _progress = 0;
    });
    try {
      final size = await File(widget.localPath).length();
      final url = await S3ShareService.uploadAndPresign(
        config: _config,
        localPath: widget.localPath,
        expiry: _expiry,
        onProgress: (sent) {
          if (mounted && size > 0) {
            setState(() => _progress = sent / size);
          }
        },
      );
      if (mounted) {
        setState(() {
          _url = url;
          _loading = false;
          _progress = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.localPath.split(Platform.pathSeparator).last;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('分享到互联网', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(name, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '上传到你配置的对象存储并生成临时下载链接（对方用浏览器即可下载）。'
            '流量费由你的云账号承担；推荐七牛（下行更便宜）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_config.isConfigured ? '已配置：${_config.bucket}' : '未配置存储'),
            subtitle: Text(_config.isConfigured ? _config.endpoint : '点击去配置（S3 兼容）'),
            trailing: const Icon(Icons.settings),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const S3ShareSettingsPage()),
              );
              await _load();
            },
          ),
          DropdownButtonFormField<Duration>(
            initialValue: _expiry,
            decoration: const InputDecoration(labelText: '链接有效期'),
            items: const [
              DropdownMenuItem(value: Duration(hours: 1), child: Text('1 小时')),
              DropdownMenuItem(value: Duration(hours: 24), child: Text('1 天')),
              DropdownMenuItem(value: Duration(days: 7), child: Text('7 天')),
            ],
            onChanged: _loading
                ? null
                : (v) {
                    if (v != null) setState(() => _expiry = v);
                  },
          ),
          const SizedBox(height: 16),
          if (_loading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(_progress == null
                ? '上传中…'
                : '上传中 ${((_progress ?? 0) * 100).toStringAsFixed(0)}%'),
          ],
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
          ],
          if (_url != null) ...[
            SelectableText(_url!, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _url!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('链接已复制'), backgroundColor: Colors.green),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('复制链接'),
            ),
          ] else
            FilledButton.icon(
              onPressed: _loading ? null : _upload,
              icon: const Icon(Icons.cloud_upload),
              label: const Text('上传并生成链接'),
            ),
        ],
      ),
    );
  }
}
