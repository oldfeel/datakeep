import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/s3_share_config.dart';
import '../../core/services/s3_share_history.dart';
import '../../core/services/s3_share_service.dart';
import '../../shared/utils/local_file_path.dart';
import '../pages/s3_share_settings_page.dart';

/// 分享到互联网：历史上传链接 / 新建（可选提取码）
Future<void> showShareToCloudSheet(
  BuildContext context, {
  String folderPath = '',
  String relativePath = '',
  String? localAbsolutePath,
}) async {
  var localPath = localAbsolutePath?.trim() ?? '';
  if (localPath.isEmpty) {
    localPath = folderPath.isEmpty
        ? relativePath
        : joinLocalFilePath(folderPath, relativePath);
  }

  if (localPath.isEmpty || !await File(localPath).exists()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件不在本机，请先同步或下载后再分享'),
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
  List<S3ShareRecord> _history = [];
  Duration _expiry = const Duration(hours: 24);
  final _passwordCtrl = TextEditingController();
  bool _usePassword = false;
  bool _loading = false;
  double? _progress;
  String? _status;
  String? _error;
  S3ShareRecord? _justCreated;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await S3ShareConfigStore.load();
    final h = await S3ShareHistoryStore.forLocalPath(widget.localPath);
    if (mounted) {
      setState(() {
        _config = c;
        _history = h;
      });
    }
  }

  String _fmtExpiry(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  /// 只复制 URL。切勿把提取码粘进浏览器地址栏，否则签名会失效。
  Future<void> _copyUrl(S3ShareRecord r) async {
    await Clipboard.setData(ClipboardData(text: r.url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.hasPassword
                ? '已复制链接（提取码请单独发给对方，不要粘到地址栏）'
                : '链接已复制',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _copyPassword(S3ShareRecord r) async {
    final pw = r.password ?? '';
    if (pw.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: pw));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('提取码已复制'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _copyShareMessage(S3ShareRecord r) async {
    final text = r.hasPassword && (r.password?.isNotEmpty ?? false)
        ? '文件：${r.fileName}\n'
            '链接：\n${r.url}\n\n'
            '提取码：${r.password}\n'
            '（请只打开链接那一行，不要把提取码粘进浏览器地址栏）'
        : r.url;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('分享文案已复制（可发给聊天软件）'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _refreshRecord(S3ShareRecord r) async {
    if (!_config.isConfigured) {
      await _openSettings();
      if (!_config.isConfigured) return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _status = '刷新链接…';
    });
    try {
      final updated = await S3ShareService.refreshLink(
        config: _config,
        record: r,
        expiry: _expiry,
      );
      await _load();
      if (mounted) {
        setState(() {
          _justCreated = updated;
          _loading = false;
          _status = null;
        });
        await _copyUrl(updated);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _status = null;
        });
      }
    }
  }

  Future<void> _deleteRecord(S3ShareRecord r) async {
    await S3ShareHistoryStore.remove(r.id);
    await _load();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const S3ShareSettingsPage()),
    );
    await _load();
  }

  Future<void> _create({bool forceReupload = false}) async {
    if (!_config.isConfigured) {
      await _openSettings();
      if (!_config.isConfigured) return;
    }
    final pw = _usePassword ? _passwordCtrl.text.trim() : '';
    if (_usePassword && pw.isEmpty) {
      setState(() => _error = '请填写提取码，或关闭「需要提取码」');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _justCreated = null;
      _progress = forceReupload ? 0 : null;
      _status = forceReupload ? '重新上传…' : '检查是否可复用云端文件…';
    });
    try {
      final size = await File(widget.localPath).length();
      final result = await S3ShareService.share(
        config: _config,
        localPath: widget.localPath,
        expiry: _expiry,
        password: _usePassword ? pw : null,
        forceReupload: forceReupload,
        onProgress: (sent) {
          if (mounted && size > 0) {
            setState(() {
              _progress = (sent / size).clamp(0.0, 1.0);
              _status = '上传中 ${((_progress ?? 0) * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      await _load();
      if (mounted) {
        setState(() {
          _justCreated = result.record;
          _loading = false;
          _progress = 1;
          _status = result.reusedObject ? '已复用云端文件，仅刷新链接' : null;
        });
        await _copyUrl(result.record);
        if (mounted && result.reusedObject) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已复用云端文件，未重新上传'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.localPath.split(Platform.pathSeparator).last;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('分享到互联网', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(name, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              '上传到你的对象存储后生成临时链接。对方用浏览器即可下载；流量费由你的云账号承担。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                _config.isConfigured ? '已配置：${_config.bucket}' : '未配置存储',
              ),
              subtitle: Text(
                _config.isConfigured ? _config.endpoint : '点击去配置（S3 兼容）',
              ),
              trailing: const Icon(Icons.settings),
              onTap: _loading ? null : _openSettings,
            ),
            if (_history.isNotEmpty) ...[
              const Divider(),
              Text('历史链接', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              ..._history.map(_buildHistoryTile),
              const SizedBox(height: 8),
            ],
            const Divider(),
            Text('新建分享', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<Duration>(
              initialValue: _expiry,
              decoration: const InputDecoration(
                labelText: '链接有效期',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: Duration(hours: 1), child: Text('1 小时')),
                DropdownMenuItem(value: Duration(hours: 24), child: Text('1 天')),
                DropdownMenuItem(value: Duration(days: 3), child: Text('3 天')),
                DropdownMenuItem(value: Duration(days: 7), child: Text('7 天')),
              ],
              onChanged: _loading
                  ? null
                  : (v) {
                      if (v != null) setState(() => _expiry = v);
                    },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('需要提取码'),
              subtitle: Text(
                _usePassword
                    ? '对方打开链接后需输入提取码才能下载（≤200MB）'
                    : '关闭则生成直接下载链接',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: _usePassword,
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _usePassword = v),
            ),
            if (_usePassword)
              TextField(
                controller: _passwordCtrl,
                enabled: !_loading,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '提取码',
                  hintText: '发给对方时一并告知',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            const SizedBox(height: 16),
            if (_loading) ...[
              if (_progress != null) LinearProgressIndicator(value: _progress),
              if (_progress == null) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_status ?? '处理中…'),
              const SizedBox(height: 8),
            ],
            if (!_loading && _status != null) ...[
              Text(
                _status!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 8),
            ],
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            if (_justCreated != null) ...[
              _buildResultCard(_justCreated!),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _loading ? null : () => _create(),
              icon: Icon(_history.isNotEmpty ? Icons.refresh : Icons.cloud_upload),
              label: Text(
                _history.isNotEmpty ? '复用云端文件并刷新链接' : '上传并生成链接',
              ),
            ),
            if (_history.isNotEmpty)
              TextButton(
                onPressed: _loading ? null : () => _create(forceReupload: true),
                child: const Text('强制重新上传'),
              ),
            Text(
              '同一文件未修改时会复用已上传对象，只刷新下载链接；改提取码或点「强制重新上传」才会再传文件。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(S3ShareRecord r) {
    final expired = r.isExpired;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.hasPassword ? Icons.lock_outline : Icons.link,
                  size: 18,
                  color: expired
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${r.remainingLabel} · 到期 ${_fmtExpiry(r.expiresAt)}'
                    '${r.hasPassword && (r.password?.isNotEmpty ?? false) ? ' · 提取码：${r.password}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              r.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _loading || expired ? null : () => _copyUrl(r),
                  child: const Text('复制链接'),
                ),
                if (r.hasPassword)
                  TextButton(
                    onPressed: _loading || expired ? null : () => _copyPassword(r),
                    child: const Text('复制提取码'),
                  ),
                TextButton(
                  onPressed:
                      _loading || expired ? null : () => _copyShareMessage(r),
                  child: const Text('复制文案'),
                ),
                TextButton(
                  onPressed: _loading || expired ? null : () => _refreshRecord(r),
                  child: const Text('刷新有效期'),
                ),
                TextButton(
                  onPressed: _loading ? null : () => _deleteRecord(r),
                  child: const Text('移除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(S3ShareRecord r) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已生成 · ${r.remainingLabel}', style: Theme.of(context).textTheme.titleSmall),
          Text('到期：${_fmtExpiry(r.expiresAt)}',
              style: Theme.of(context).textTheme.bodySmall),
          if (r.hasPassword && r.password != null)
            Text('提取码：${r.password}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    )),
          const SizedBox(height: 8),
          SelectableText(r.url, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '打开时请只粘贴上面的链接；提取码在网页里输入，不要写进地址栏。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _copyUrl(r),
                icon: const Icon(Icons.link, size: 18),
                label: const Text('复制链接'),
              ),
              if (r.hasPassword)
                TextButton.icon(
                  onPressed: () => _copyPassword(r),
                  icon: const Icon(Icons.password, size: 18),
                  label: const Text('复制提取码'),
                ),
              TextButton.icon(
                onPressed: () => _copyShareMessage(r),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制文案'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
