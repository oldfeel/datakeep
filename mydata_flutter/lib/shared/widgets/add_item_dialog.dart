import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/services/api_service.dart';
import '../../core/services/market_service.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../utils/sync_folder_paths.dart';

/// 顶层添加（同步文件夹）或目录内添加（子文件夹 / 应用）
enum AddItemScope {
  /// 设备文件夹列表：添加同步文件夹 / 市场应用
  syncRoot,
  /// 已进入某同步文件夹：新建子目录 / 市场应用安装到当前路径
  insideFolder,
}

/// 添加：本地同步文件夹，或从应用市场安装到当前目录；
/// 在文件夹内还可新建子文件夹。
class AddItemDialog extends StatefulWidget {
  final AddItemScope scope;

  /// 当前目录（市场应用安装到其下的 `<appKey>/`；目录内新建子文件夹也基于此）
  final String? initialParentPath;

  /// 所在同步文件夹 ID（目录内新建后触发扫描）
  final String? parentFolderId;
  final VoidCallback? onDone;

  const AddItemDialog({
    super.key,
    this.scope = AddItemScope.syncRoot,
    this.initialParentPath,
    this.parentFolderId,
    this.onDone,
  });

  static Future<void> show(
    BuildContext context, {
    AddItemScope scope = AddItemScope.syncRoot,
    String? parentPath,
    String? parentFolderId,
    VoidCallback? onDone,
  }) {
    return showDialog(
      context: context,
      builder: (_) => AddItemDialog(
        scope: scope,
        initialParentPath: parentPath,
        parentFolderId: parentFolderId,
        onDone: onDone,
      ),
    );
  }

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

enum _AddKind { folder, market }

class _AddItemDialogState extends State<AddItemDialog> {
  _AddKind _kind = _AddKind.folder;

  final _idCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _pathCtrl = TextEditingController();
  final _parentCtrl = TextEditingController();
  final _subDirCtrl = TextEditingController();

  List<MarketAppInfo> _apps = [];
  bool _loadingMarket = false;
  String? _marketError;
  final _busy = <String>{};
  String? _status;
  bool _submitting = false;

  bool get _inside => widget.scope == AddItemScope.insideFolder;

  @override
  void initState() {
    super.initState();
    _initParent();
  }

  Future<void> _initParent() async {
    if (widget.initialParentPath != null && widget.initialParentPath!.isNotEmpty) {
      _parentCtrl.text = widget.initialParentPath!;
    } else {
      final sample = await defaultSyncFolderPath('_');
      _parentCtrl.text = p.dirname(sample);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    _parentCtrl.dispose();
    _subDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMarket() async {
    setState(() {
      _loadingMarket = true;
      _marketError = null;
    });
    try {
      final list = await MarketService.listApps();
      if (!mounted) return;
      setState(() {
        _apps = list;
        _loadingMarket = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _marketError = e.toString();
        _loadingMarket = false;
      });
    }
  }

  Future<void> _pickParent() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null && mounted) {
      setState(() => _parentCtrl.text = result);
    }
  }

  Future<void> _pickFolderPath() async {
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null && mounted) {
      setState(() {
        _pathCtrl.text = result;
        final dirName = p.basename(result);
        if (_idCtrl.text.isEmpty) _idCtrl.text = dirName;
        if (_nameCtrl.text.isEmpty) _nameCtrl.text = dirName;
      });
    }
  }

  Future<void> _submitSyncFolder() async {
    final id = _idCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final path = _pathCtrl.text.trim();
    if (id.isEmpty || name.isEmpty || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整信息')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<FolderProvider>().createFolder(
            id: id,
            name: name,
            path: path,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDone?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitSubDir() async {
    final name = _subDirCtrl.text.trim();
    final parent = _parentCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入文件夹名称')),
      );
      return;
    }
    if (name.contains('/') || name.contains('\\') || name == '.' || name == '..') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称不能包含路径分隔符')),
      );
      return;
    }
    if (parent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前目录无效')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final dir = Directory(p.join(parent, name));
      if (await dir.exists()) {
        throw Exception('已存在同名文件夹');
      }
      await dir.create(recursive: true);
      final folderId = widget.parentFolderId;
      if (folderId != null && folderId.isNotEmpty) {
        try {
          await ApiService.scanFolder(folderId);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDone?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建 $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _installApp(MarketAppInfo app) async {
    final parent = _parentCtrl.text.trim();
    if (parent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写当前安装目录')),
      );
      return;
    }
    setState(() {
      _busy.add(app.appKey);
      _status = '正在安装 ${app.name}…';
    });
    try {
      await MarketService.install(
        app,
        parentDir: parent,
        onProgress: (m) {
          if (mounted) setState(() => _status = m);
        },
      );
      if (!mounted) return;
      await context.read<FolderProvider>().fetchFolders();
      final folderId = widget.parentFolderId;
      if (folderId != null && folderId.isNotEmpty) {
        try {
          await ApiService.scanFolder(folderId);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onDone?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装到 $parent/${app.appKey}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(app.appKey);
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 600;
    final folderLabel = _inside ? '新建文件夹' : '本地文件夹';
    return AlertDialog(
      title: Text(_inside ? '在此目录添加' : '添加'),
      content: SizedBox(
        width: wide ? 480 : null,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_AddKind>(
                segments: [
                  ButtonSegment(
                    value: _AddKind.folder,
                    label: Text(folderLabel),
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  ),
                  const ButtonSegment(
                    value: _AddKind.market,
                    label: Text('应用市场'),
                    icon: Icon(Icons.storefront_outlined, size: 18),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) {
                  setState(() => _kind = s.first);
                  if (_kind == _AddKind.market && _apps.isEmpty && !_loadingMarket) {
                    _loadMarket();
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_kind == _AddKind.folder)
                ...(_inside ? _subDirFields() : _syncFolderFields())
              else
                ..._marketFields(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (_kind == _AddKind.folder)
          FilledButton(
            onPressed: _submitting
                ? null
                : (_inside ? _submitSubDir : _submitSyncFolder),
            child: Text(_inside ? '创建' : '添加'),
          ),
      ],
    );
  }

  List<Widget> _syncFolderFields() {
    return [
      TextField(
        controller: _idCtrl,
        decoration: const InputDecoration(
          labelText: '文件夹 ID',
          hintText: '唯一标识',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _nameCtrl,
        decoration: const InputDecoration(labelText: '文件夹名称'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _pathCtrl,
              decoration: const InputDecoration(
                labelText: '文件夹路径',
                hintText: '本机绝对路径',
              ),
            ),
          ),
          if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
            IconButton(
              tooltip: '浏览',
              icon: const Icon(Icons.folder_open),
              onPressed: _pickFolderPath,
            ),
        ],
      ),
    ];
  }

  List<Widget> _subDirFields() {
    return [
      Text(
        '将在当前目录下创建子文件夹',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _parentCtrl,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: '当前目录',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _subDirCtrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '文件夹名称',
          hintText: '例如 photos',
        ),
        onSubmitted: (_) {
          if (!_submitting) _submitSubDir();
        },
      ),
    ];
  }

  List<Widget> _marketFields() {
    return [
      Text(
        '安装到当前目录下（将创建子目录 `<appKey>/`）',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _parentCtrl,
              readOnly: _inside,
              decoration: const InputDecoration(
                labelText: '当前目录',
                hintText: '应用会安装到此目录下',
              ),
            ),
          ),
          if (!_inside &&
              (Platform.isLinux || Platform.isWindows || Platform.isMacOS))
            IconButton(
              tooltip: '选择目录',
              icon: const Icon(Icons.folder_open),
              onPressed: _pickParent,
            ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _loadingMarket ? null : _loadMarket,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('刷新列表'),
        ),
      ),
      if (_status != null) ...[
        const SizedBox(height: 4),
        Text(_status!, style: Theme.of(context).textTheme.bodySmall),
      ],
      if (_loadingMarket)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_marketError != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            _marketError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        )
      else if (_apps.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('暂无上架应用，请点刷新或检查市场 API 地址'),
        )
      else
        ..._apps.map((app) {
          final busy = _busy.contains(app.appKey);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(app.name),
            subtitle: Text(
              [
                if (app.version != null) 'v${app.version}',
                if (app.description.isNotEmpty) app.description,
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FilledButton(
                    onPressed: () => _installApp(app),
                    child: const Text('安装'),
                  ),
          );
        }),
    ];
  }
}
