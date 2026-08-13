import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../shared/utils/app_dir.dart';
import '../../shared/widgets/add_item_dialog.dart';
import '../../shared/widgets/folder_sync_banner.dart';
import '../../shared/widgets/share_to_cloud_sheet.dart';
import '../widgets/file_icon.dart';

enum _SortField { name, size, mtime, ctime }

class FolderDetailPage extends StatefulWidget {
  final Device device;
  final Folder folder;
  /// 进入页面时恢复的相对路径，如 `照片` 或 `a/b`
  final String initialPath;
  final void Function(String filePath) onFileTap;
  final void Function(String relativePath)? onPathChanged;
  final VoidCallback onBack;

  const FolderDetailPage({
    super.key,
    required this.device,
    required this.folder,
    this.initialPath = '',
    required this.onFileTap,
    this.onPathChanged,
    required this.onBack,
  });

  @override
  State<FolderDetailPage> createState() => _FolderDetailPageState();
}

class _FolderDetailPageState extends State<FolderDetailPage> {
  List<Map<String, dynamic>> _files = [];
  final List<String> _currentPath = [];
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _syncInfo;
  Timer? _syncTimer;
  bool _scanning = false;

  bool _isGrid = false;
  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;

  bool get _showSyncBanner =>
      widget.device.isLocal && !widget.folder.isReadonlyAccess;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath.isNotEmpty) {
      _currentPath.addAll(
        widget.initialPath.split('/').where((s) => s.isNotEmpty),
      );
    }
    _loadPrefs().then((_) => _loadFiles());
    if (_showSyncBanner) {
      unawaited(_refreshSync());
      _syncTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _refreshSync());
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSync() async {
    if (!_showSyncBanner) return;
    try {
      final info = await ApiService.getFolderSyncStatus(widget.folder.id);
      if (!mounted) return;
      debugPrint(
        '[sync-ui][desktop] folder=${widget.folder.id} '
        'status=${info['status']} completion=${info['completion']} '
        'inSync=${info['inSyncFiles']}/${info['globalFiles']} '
        'local=${info['localFiles']} need=${info['needFiles']} '
        'needBytes=${info['needBytes']}',
      );
      final wasSyncing = _syncInfo?['status'] == 'syncing';
      setState(() => _syncInfo = info);
      final isSyncing = info['status'] == 'syncing';
      if (isSyncing || (wasSyncing && info['status'] == 'synced')) {
        await _loadFiles();
      }
    } catch (e) {
      debugPrint('[sync-ui][desktop] 刷新失败: $e');
    }
  }

  Future<void> _rescanFolder() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await ApiService.scanFolder(widget.folder.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已触发重新扫描')),
      );
      await _refreshSync();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _resetFolderIndex() async {
    if (_scanning) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重建索引？'),
        content: const Text(
          '将清除该文件夹的同步索引并重新扫描本地文件，本地文件不会删除。'
          '之后会与对端重新交换文件列表，可能需要几分钟。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _scanning = true);
    try {
      await ApiService.resetFolderIndex(widget.folder.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已重建索引，正在重新扫描…')),
      );
      await _refreshSync();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('重建索引失败: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _notifyPathChanged() {
    widget.onPathChanged?.call(_currentPath.join('/'));
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    _isGrid = p.getBool('folder_is_grid') ?? false;
    final sf = p.getString('folder_sort_field');
    if (sf != null) {
      _sortField = _SortField.values.firstWhere((v) => v.name == sf, orElse: () => _SortField.name);
    }
    _sortAscending = p.getBool('folder_sort_asc') ?? true;
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('folder_is_grid', _isGrid);
    await p.setString('folder_sort_field', _sortField.name);
    await p.setBool('folder_sort_asc', _sortAscending);
  }

  Future<void> _loadFiles() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final path = _currentPath.join('/');
      final files = await ApiService.getFolderFiles(
        widget.folder.id,
        path: path.isEmpty ? null : path,
        deviceId: widget.device.id,
      );
      if (mounted) { setState(() { _files = files; _isLoading = false; _applySort(); }); }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _applySort() {
    _files.sort((a, b) {
      final aDir = _isDir(a);
      final bDir = _isDir(b);
      if (aDir != bDir) return aDir ? -1 : 1;
      int cmp;
      switch (_sortField) {
        case _SortField.name: cmp = _name(a).toLowerCase().compareTo(_name(b).toLowerCase());
        case _SortField.size: cmp = _val(a['size']).compareTo(_val(b['size']));
        case _SortField.mtime: cmp = _val(a['modTime'] ?? a['modified']).compareTo(_val(b['modTime'] ?? b['modified']));
        case _SortField.ctime: cmp = _val(a['ctime']).compareTo(_val(b['ctime']));
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _toggleSort(_SortField field) {
    setState(() {
      if (_sortField == field) { _sortAscending = !_sortAscending; }
      else { _sortField = field; _sortAscending = true; }
      _applySort();
    });
    _savePrefs();
  }

  void _toggleView() { setState(() => _isGrid = !_isGrid); _savePrefs(); }

  void _enterFolder(String name) {
    setState(() { _currentPath.add(name); });
    _notifyPathChanged();
    _loadFiles();
  }

  void _navigateToPath(List<String> targetPath) {
    setState(() { _currentPath.clear(); _currentPath.addAll(targetPath); });
    _notifyPathChanged();
    _loadFiles();
  }

  void _goUp() {
    if (_currentPath.isEmpty) return;
    setState(() { _currentPath.removeLast(); });
    _notifyPathChanged();
    _loadFiles();
  }

  /// 相对文件夹根的路径（含子目录），供预览/打开使用
  String _relativePath(String name) =>
      _currentPath.isEmpty ? name : '${_currentPath.join('/')}/$name';

  /// 当前浏览目录的本机绝对路径
  String get _absoluteCurrentPath {
    final root = widget.folder.path;
    if (_currentPath.isEmpty) return root;
    return p.join(root, p.joinAll(_currentPath));
  }

  bool get _canAddHere =>
      widget.device.isLocal &&
      widget.folder.path.isNotEmpty &&
      !widget.folder.isReadonlyAccess;

  /// 子目录是否为应用（已注册 kind=app 或含 app.json）
  bool _entryIsApp(String name) {
    if (!widget.device.isLocal) return false;
    final abs = p.join(_absoluteCurrentPath, name);
    final registered = findRegisteredApp(
      context.read<FolderProvider>().folders,
      abs,
    );
    if (registered != null) return true;
    return isAppDirectory(abs);
  }

  void _openEntryApp(String name) {
    final abs = p.join(_absoluteCurrentPath, name);
    final registered = findRegisteredApp(
      context.read<FolderProvider>().folders,
      abs,
    );
    openAppAtPath(
      context,
      absolutePath: abs,
      title: registered?.name ?? name,
      folder: registered,
    );
  }

  void _showAddDialog() {
    AddItemDialog.show(
      context,
      scope: AddItemScope.insideFolder,
      parentPath: _absoluteCurrentPath,
      parentFolderId: widget.folder.id,
      onDone: _loadFiles,
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() { final item = _files.removeAt(oldIndex); _files.insert(newIndex, item); });
  }

  String _name(Map<String, dynamic> f) => f['name']?.toString() ?? '';
  bool _isDir(Map<String, dynamic> f) {
    final t = f['type']; return t == 1 || t == '1' || t == 'dir' || t == true || f['isDir'] == true;
  }
  int _val(dynamic v) => (v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0);

  String _sizeStr(dynamic size) {
    final s = _val(size); if (s == 0) return '-';
    const u = ['B', 'KB', 'MB', 'GB']; var i = 0; double r = s.toDouble();
    while (r >= 1024 && i < u.length - 1) { r /= 1024; i++; }
    return '${r.toStringAsFixed(r >= 100 ? 0 : 1)} ${u[i]}';
  }

  String _dateStr(dynamic ts) {
    final t = _val(ts); if (t == 0) return '-';
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildBreadcrumb(context),
        const SizedBox(height: 8),
        _buildToolbar(context),
        if (_syncInfo != null && _showSyncBanner) ...[
          const SizedBox(height: 12),
          FolderSyncBanner(
            info: _syncInfo!,
            actions: (_syncInfo!['status']?.toString() == 'stalled' ||
                    _syncInfo!['stalled'] == true)
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _scanning ? null : _rescanFolder,
                        icon: _scanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(_scanning ? '处理中…' : '重新扫描'),
                      ),
                      FilledButton.icon(
                        onPressed: _scanning ? null : _resetFolderIndex,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('重建索引'),
                      ),
                    ],
                  )
                : null,
          ),
        ],
        const SizedBox(height: 16),
        Expanded(child: _buildContent(context)),
      ]),
    );
  }

  Widget _buildBreadcrumb(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
          onTap: widget.onBack,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 20), const SizedBox(width: 4),
            Icon(Icons.home, size: 18, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4),
            Text(widget.device.displayName, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ]),
        )),
        const Text(' / ', style: TextStyle(color: Colors.grey)),
        MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
          onTap: () => _navigateToPath([]),
          child: Text(widget.folder.name, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        )),
        for (var i = 0; i < _currentPath.length; i++) ...[
          const Text(' / ', style: TextStyle(color: Colors.grey)),
          MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(
            onTap: i < _currentPath.length - 1 ? () => _navigateToPath(_currentPath.sublist(0, i + 1)) : null,
            child: Text(_currentPath[i], style: TextStyle(
              color: i < _currentPath.length - 1 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              fontWeight: i == _currentPath.length - 1 ? FontWeight.w600 : FontWeight.normal,
            )),
          )),
        ],
      ]),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Row(children: [
      Text(_currentPath.isEmpty ? widget.folder.name : _currentPath.last,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      if (_files.isNotEmpty) ...[
        const SizedBox(width: 8),
        Text('(${_files.length})', style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
      const Spacer(),
      if (_canAddHere)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: FilledButton.tonalIcon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加'),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ),
      IconButton(
        icon: Icon(_isGrid ? Icons.view_list : Icons.grid_view, size: 20),
        tooltip: _isGrid ? '列表视图' : '网格视图',
        onPressed: _toggleView,
      ),
      const SizedBox(width: 4),
      if (_currentPath.isNotEmpty) IconButton(icon: const Icon(Icons.arrow_upward), tooltip: '上级目录', onPressed: _goUp),
      IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: _loadFiles),
    ]);
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
      const SizedBox(height: 8), Text(_error!),
      const SizedBox(height: 8), ElevatedButton(onPressed: _loadFiles, child: const Text('重试')),
    ]));
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text('该目录为空', style: Theme.of(context).textTheme.titleMedium),
            if (_canAddHere) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('添加文件夹或应用'),
              ),
            ],
          ],
        ),
      );
    }
    return _isGrid ? _buildGrid(context) : _buildList(context);
  }

  // ── Sort header ────────────────────────────────────────────

  Widget _sortHeader(String label, _SortField field) {
    final active = _sortField == field;
    return GestureDetector(
      onTap: () => _toggleSort(field),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13,
            color: active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant)),
          if (active) Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14, color: Theme.of(context).colorScheme.primary),
        ]),
      ),
    );
  }

  // ── 列表视图（可拖拽排序 + 点击表头排序） ──────────────────

  void _shareFile(BuildContext context, String name) {
    showShareToCloudSheet(
      context,
      folderPath: widget.folder.path,
      relativePath: _relativePath(name),
    );
  }

  Widget _buildList(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const SizedBox(width: 32),
            Expanded(child: _sortHeader('名称', _SortField.name)),
            const SizedBox(width: 40), // 与行内分享按钮对齐
            SizedBox(width: 100, child: _sortHeader('大小', _SortField.size)),
            SizedBox(width: 140, child: _sortHeader('创建时间', _SortField.ctime)),
            SizedBox(width: 140, child: _sortHeader('修改时间', _SortField.mtime)),
          ]),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _files.length,
            onReorder: _onReorder,
            proxyDecorator: (child, _, __) => Material(elevation: 2, borderRadius: BorderRadius.circular(4), child: child),
            itemBuilder: (_, i) {
              final f = _files[i];
              final name = _name(f);
              final isDir = _isDir(f);
              final isApp = isDir && _entryIsApp(name);
              return Container(
                key: ValueKey('f_$i'),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                ),
                child: InkWell(
                  onTap: isDir
                      ? (isApp
                          ? () => _openEntryApp(name)
                          : () => _enterFolder(name))
                      : () => widget.onFileTap(_relativePath(name)),
                  onSecondaryTap: isDir ? null : () => _shareFile(context, name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(children: [
                      ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Icon(
                        isApp ? Icons.apps : getFileIcon(name, isDir: isDir),
                        size: 20,
                        color: isApp
                            ? Theme.of(context).colorScheme.tertiary
                            : getFileIconColor(name, isDir: isDir),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isApp) ...[
                              const SizedBox(width: 8),
                              Text(
                                '应用',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: isApp
                            ? IconButton(
                                icon: const Icon(Icons.folder_open, size: 20),
                                tooltip: '浏览文件',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                onPressed: () => _enterFolder(name),
                              )
                            : (isDir
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.share_outlined, size: 18),
                                    tooltip: '分享到互联网',
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                    onPressed: () => _shareFile(context, name),
                                  )),
                      ),
                      SizedBox(width: 100, child: Text(isDir ? '-' : _sizeStr(f['size']),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      SizedBox(width: 140, child: Text(_dateStr(f['ctime']),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      SizedBox(width: 140, child: Text(_dateStr(f['modTime'] ?? f['modified']),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ── 网格视图（固定按名称排序，不可拖拽） ───────────────────

  int _gridCols(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w > 1400) return 8; if (w > 1100) return 6; if (w > 800) return 4; return 3;
  }

  Widget _buildGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridCols(context), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85,
      ),
      itemCount: _files.length,
      itemBuilder: (_, i) {
        final f = _files[i];
        final name = _name(f);
        final isDir = _isDir(f);
        final isApp = isDir && _entryIsApp(name);
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isDir
                ? (isApp
                    ? () => _openEntryApp(name)
                    : () => _enterFolder(name))
                : () => widget.onFileTap(_relativePath(name)),
            onSecondaryTap: isDir ? null : () => _shareFile(context, name),
            child: Stack(
              children: [
                SizedBox.expand(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        isApp ? Icons.apps : getFileIcon(name, isDir: isDir),
                        size: 48,
                        color: isApp
                            ? Theme.of(context).colorScheme.tertiary
                            : getFileIconColor(name, isDir: isDir),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        isApp ? '应用' : (isDir ? '文件夹' : _sizeStr(f['size'])),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isApp)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.folder_open, size: 20),
                      tooltip: '浏览文件',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _enterFolder(name),
                    ),
                  )
                else if (!isDir)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const Icon(Icons.share_outlined, size: 18),
                      tooltip: '分享到互联网',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _shareFile(context, name),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
