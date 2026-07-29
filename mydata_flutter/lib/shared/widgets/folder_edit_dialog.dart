import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../../core/backend/folder_acl_store.dart';
import '../../features/folders/providers/folder_provider.dart';

/// 打开文件夹编辑：手机用整页，桌面用弹框
class FolderEditDialog {
  FolderEditDialog._();

  static Future<void> show(
    BuildContext context, {
    required Folder folder,
    required VoidCallback onDone,
  }) {
    final usePage = Platform.isAndroid ||
        Platform.isIOS ||
        MediaQuery.of(context).size.width < 600;

    if (usePage) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => FolderEditScreen(folder: folder, onDone: onDone),
        ),
      );
    }

    return showDialog<void>(
      context: context,
      builder: (_) => _FolderEditAlert(folder: folder, onDone: onDone),
    );
  }
}

/// Android / 窄屏：整页编辑
class FolderEditScreen extends StatelessWidget {
  final Folder folder;
  final VoidCallback onDone;

  const FolderEditScreen({
    super.key,
    required this.folder,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return FolderEditForm(
      folder: folder,
      onDone: onDone,
      asPage: true,
    );
  }
}

class _FolderEditAlert extends StatelessWidget {
  final Folder folder;
  final VoidCallback onDone;

  const _FolderEditAlert({required this.folder, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return FolderEditForm(
      folder: folder,
      onDone: onDone,
      asPage: false,
    );
  }
}

/// 编辑表单本体（共享 → 有「同步」时显示同步/忽略/问题）
class FolderEditForm extends StatefulWidget {
  final Folder folder;
  final VoidCallback onDone;
  final bool asPage;

  const FolderEditForm({
    super.key,
    required this.folder,
    required this.onDone,
    required this.asPage,
  });

  @override
  State<FolderEditForm> createState() => _FolderEditFormState();
}

class _FolderEditFormState extends State<FolderEditForm> {
  final Map<String, FolderAccess> _permissions = {};
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;

  String _folderType = 'sendreceive';
  bool _paused = false;
  final _ignoresController = TextEditingController();
  Map<String, dynamic>? _issues;
  bool _scanning = false;
  bool _saving = false;

  String _normId(String id) => id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  bool get _showSyncExtras =>
      _devices.isEmpty ||
      _permissions.values.any((a) => a == FolderAccess.sync);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ignoresController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getDevicesRaw();
      final acl = await ApiService.getFolderAcl(widget.folder.id);
      final settings = await ApiService.getFolderSettings(widget.folder.id);
      final ignores = await ApiService.getFolderIgnores(widget.folder.id);
      final issues = await ApiService.getFolderIssues(widget.folder.id);

      String? aclValueFor(String deviceId) {
        if (acl.containsKey(deviceId)) return acl[deviceId];
        final n = _normId(deviceId);
        for (final e in acl.entries) {
          if (_normId(e.key) == n) return e.value;
        }
        return null;
      }

      bool isLocalDevice(Map<String, dynamic> d) {
        final id = d['deviceID']?.toString() ?? '';
        return id == 'local' ||
            d['connectionType'] == 'local' ||
            d['clientVersion'] == 'local';
      }

      if (mounted) {
        setState(() {
          _devices = list.where((d) => !isLocalDevice(d)).toList();
          _permissions
            ..clear()
            ..addAll({
              for (final d in _devices)
                if ((d['deviceID']?.toString() ?? '').isNotEmpty)
                  d['deviceID'].toString(): FolderAccess.tryParse(
                        aclValueFor(d['deviceID'].toString()),
                      ) ??
                      FolderAccess.hidden,
            });
          _folderType = settings['type']?.toString() ?? 'sendreceive';
          _paused = settings['paused'] == true;
          _ignoresController.text = ignores.join('\n');
          _issues = issues;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('加载文件夹编辑数据失败: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  FolderAccess _accessFor(String deviceId) =>
      _permissions[deviceId] ??
      _permissions.entries
          .where((e) => _normId(e.key) == _normId(deviceId))
          .map((e) => e.value)
          .firstOrNull ??
      FolderAccess.hidden;

  void _setAccess(String deviceId, FolderAccess access) {
    setState(() {
      _permissions.removeWhere((k, _) => _normId(k) == _normId(deviceId));
      _permissions[deviceId] = access;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final payload = <String, String>{
        for (final e in _permissions.entries) e.key: e.value.apiValue,
      };
      await ApiService.setFolderAcl(widget.folder.id, payload);

      if (_showSyncExtras) {
        await ApiService.updateFolderSettings(
          widget.folder.id,
          type: _folderType,
          paused: _paused,
        );
        final lines = _ignoresController.text
            .split('\n')
            .map((e) => e.trimRight())
            .toList();
        while (lines.isNotEmpty && lines.last.trim().isEmpty) {
          lines.removeLast();
        }
        await ApiService.setFolderIgnores(widget.folder.id, lines);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scanNow() async {
    setState(() => _scanning = true);
    try {
      await ApiService.scanFolder(widget.folder.id);
      final issues = await ApiService.getFolderIssues(widget.folder.id);
      if (mounted) {
        setState(() => _issues = issues);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已触发扫描')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文件夹 "${widget.folder.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<FolderProvider>().deleteFolder(widget.folder.id);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: widget.asPage
          ? const EdgeInsets.fromLTRB(16, 8, 16, 24)
          : EdgeInsets.zero,
      children: [
        _sectionTitle('共享权限'),
        Text(
          '同步：双向同步　只读：可见可浏览不同步　隐藏：对端不可见',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (_devices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('没有其他设备'),
          )
        else
          ..._devices.map(_buildDevicePermission),
        if (!_showSyncExtras && _devices.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '将至少一台设备设为「同步」后，可配置同步类型、忽略规则与问题提示。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        if (_showSyncExtras) ...[
          const Divider(height: 28),
          _sectionTitle('同步设置'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sendreceive', label: Text('双向')),
              ButtonSegment(value: 'sendonly', label: Text('仅发送')),
              ButtonSegment(value: 'receiveonly', label: Text('仅接收')),
            ],
            selected: {_folderType},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) setState(() => _folderType = s.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            '双向：两端互相同步　仅发送：本机只上传　仅接收：本机只下载',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('暂停同步'),
            subtitle: const Text('暂停后本机文件夹不再与其他设备同步'),
            value: _paused,
            onChanged: (v) => setState(() => _paused = v),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _scanning ? null : _scanNow,
              icon: _scanning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('立即扫描'),
            ),
          ),
          const Divider(height: 28),
          _sectionTitle('忽略规则'),
          Text(
            '每行一条（.stignore），例如：(?d)*.tmp',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ignoresController,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '# 忽略临时文件\n(?d)*.tmp\n(?d)*.bak',
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          const Divider(height: 28),
          _sectionTitle('问题'),
          ..._buildIssuesChildren(),
        ],
        if (widget.asPage) ...[
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: _confirmDelete,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除文件夹'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asPage) {
      return Scaffold(
        appBar: AppBar(
          title: Text('编辑: ${widget.folder.name}'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
        body: SafeArea(child: _buildBody()),
      );
    }

    return AlertDialog(
      title: Text('编辑: ${widget.folder.name}'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: _buildBody(),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: _confirmDelete,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('删除文件夹'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDevicePermission(Map<String, dynamic> d) {
    final id = d['deviceID']?.toString() ?? '';
    final name = d['name']?.toString().trim();
    final title = (name != null && name.isNotEmpty) ? name : id;
    final access = _accessFor(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 6),
          SegmentedButton<FolderAccess>(
            segments: const [
              ButtonSegment(value: FolderAccess.sync, label: Text('同步')),
              ButtonSegment(value: FolderAccess.readonly, label: Text('只读')),
              ButtonSegment(value: FolderAccess.hidden, label: Text('隐藏')),
            ],
            selected: {access},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) _setAccess(id, s.first);
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildIssuesChildren() {
    final issues = _issues;
    if (issues == null) {
      return [const Text('暂无问题数据')];
    }
    final pullErrors = (issues['pullErrors'] as num?)?.toInt() ?? 0;
    final needFiles = (issues['needFiles'] as num?)?.toInt() ?? 0;
    final errors = (issues['errors'] as List?) ?? [];
    final pending = (issues['pending'] as List?) ?? [];
    final conflicts = (issues['conflicts'] as List?) ?? [];

    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          pullErrors > 0 || conflicts.isNotEmpty
              ? Icons.error_outline
              : Icons.check_circle_outline,
          color: pullErrors > 0 || conflicts.isNotEmpty
              ? Colors.orange
              : Colors.green,
        ),
        title: Text(
          pullErrors > 0
              ? '拉取错误 $pullErrors 个'
              : (conflicts.isNotEmpty ? '发现冲突文件' : '暂无严重错误'),
        ),
        subtitle: Text('待同步文件约 $needFiles 个'),
      ),
      if (errors.isNotEmpty) ...[
        Text('失败文件', style: Theme.of(context).textTheme.labelLarge),
        ...errors.take(8).map((e) {
          final m = e is Map ? e : <String, dynamic>{};
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              m['path']?.toString() ?? '',
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              m['error']?.toString() ?? '',
              style: const TextStyle(fontSize: 12),
            ),
          );
        }),
      ],
      if (conflicts.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('冲突文件', style: Theme.of(context).textTheme.labelLarge),
        ...conflicts.take(8).map(
              (c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber, size: 18),
                title: Text(c.toString(), style: const TextStyle(fontSize: 13)),
              ),
            ),
      ],
      if (pending.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('待同步（节选）', style: Theme.of(context).textTheme.labelLarge),
        ...pending.take(6).map(
              (p) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.toString(), style: const TextStyle(fontSize: 13)),
              ),
            ),
      ],
      if (errors.isEmpty && conflicts.isEmpty && pending.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('当前没有需要关注的问题'),
        ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            final issues = await ApiService.getFolderIssues(widget.folder.id);
            if (mounted) setState(() => _issues = issues);
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('刷新问题'),
        ),
      ),
    ];
  }
}

/// 展示本机设备 ID 二维码，方便对端扫码配对
class LocalDeviceQrDialog extends StatelessWidget {
  final String deviceId;
  final String deviceName;

  const LocalDeviceQrDialog({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  static Future<void> show(
    BuildContext context, {
    required String deviceId,
    required String deviceName,
  }) {
    return showDialog(
      context: context,
      builder: (_) => LocalDeviceQrDialog(
        deviceId: deviceId,
        deviceName: deviceName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clean = deviceId.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    return AlertDialog(
      title: const Text('本机设备 ID'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              deviceName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: clean,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              deviceId,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '对端可扫描此二维码添加本机',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: deviceId));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制设备 ID')),
              );
            }
          },
          child: const Text('复制 ID'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
