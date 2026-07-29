import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../../core/backend/folder_acl_store.dart';
import '../../features/folders/providers/folder_provider.dart';

/// 编辑文件夹：按设备设置 同步 / 只读 / 隐藏 + 删除
class FolderEditDialog extends StatefulWidget {
  final Folder folder;
  final VoidCallback onDone;

  const FolderEditDialog({
    super.key,
    required this.folder,
    required this.onDone,
  });

  static Future<void> show(
    BuildContext context, {
    required Folder folder,
    required VoidCallback onDone,
  }) {
    return showDialog(
      context: context,
      builder: (_) => FolderEditDialog(folder: folder, onDone: onDone),
    );
  }

  @override
  State<FolderEditDialog> createState() => _FolderEditDialogState();
}

class _FolderEditDialogState extends State<FolderEditDialog> {
  final Map<String, FolderAccess> _permissions = {};
  List<Map<String, dynamic>> _devices = [];
  bool _loading = true;

  String _normId(String id) => id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await ApiService.getDevicesRaw();
      final acl = await ApiService.getFolderAcl(widget.folder.id);

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
          // 本机不参与 ACL，也不写入 folder_acl.json
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
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('加载权限设置失败: $e');
      if (mounted) setState(() => _loading = false);
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
    try {
      final payload = <String, String>{
        for (final e in _permissions.entries) e.key: e.value.apiValue,
      };
      await ApiService.setFolderAcl(widget.folder.id, payload);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑: ${widget.folder.name}'),
      content: SizedBox(
        width: 440,
        height: 360,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _devices.isEmpty
                ? const Center(child: Text('没有其他设备'))
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '同步：双向同步　只读：可见可浏览不同步　隐藏：对端不可见',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      ..._devices.map((d) {
                        final id = d['deviceID']?.toString() ?? '';
                        final name = d['name']?.toString().trim();
                        final title =
                            (name != null && name.isNotEmpty) ? name : id;
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
                                  ButtonSegment(
                                    value: FolderAccess.sync,
                                    label: Text('同步'),
                                  ),
                                  ButtonSegment(
                                    value: FolderAccess.readonly,
                                    label: Text('只读'),
                                  ),
                                  ButtonSegment(
                                    value: FolderAccess.hidden,
                                    label: Text('隐藏'),
                                  ),
                                ],
                                selected: {access},
                                onSelectionChanged: (s) {
                                  if (s.isNotEmpty) _setAccess(id, s.first);
                                },
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
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
            ElevatedButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
      ],
    );
  }
}
