import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
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

  bool _isGrid = false;
  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialPath.isNotEmpty) {
      _currentPath.addAll(
        widget.initialPath.split('/').where((s) => s.isNotEmpty),
      );
    }
    _loadPrefs().then((_) => _loadFiles());
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
    if (_files.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.folder_open, size: 64, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
      const SizedBox(height: 16), Text('该目录为空', style: Theme.of(context).textTheme.titleMedium),
    ]));
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

  Widget _buildList(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            const SizedBox(width: 32),
            Expanded(flex: 3, child: _sortHeader('名称', _SortField.name)),
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
              return Container(
                key: ValueKey('f_$i'),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.3))),
                ),
                child: InkWell(
                  onTap: isDir
                      ? () => _enterFolder(name)
                      : () => widget.onFileTap(_relativePath(name)),
                  onSecondaryTap: isDir
                      ? null
                      : () => showShareToCloudSheet(
                            context,
                            folderPath: widget.folder.path,
                            relativePath: _relativePath(name),
                          ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle, size: 20, color: Colors.grey)),
                      const SizedBox(width: 8),
                      Icon(getFileIcon(name, isDir: isDir), size: 20, color: getFileIconColor(name, isDir: isDir)),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: Text(name, style: const TextStyle(fontSize: 13))),
                      SizedBox(width: 100, child: Text(isDir ? '-' : _sizeStr(f['size']),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      SizedBox(width: 140, child: Text(_dateStr(f['ctime']),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      SizedBox(width: 140, child: Text(_dateStr(f['modTime'] ?? f['modified']),
                        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                      if (!isDir)
                        IconButton(
                          icon: const Icon(Icons.share_outlined, size: 18),
                          tooltip: '分享到互联网',
                          onPressed: () => showShareToCloudSheet(
                            context,
                            folderPath: widget.folder.path,
                            relativePath: _relativePath(name),
                          ),
                        ),
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
        return Card(clipBehavior: Clip.antiAlias, child: InkWell(
          onTap: isDir
              ? () => _enterFolder(name)
              : () => widget.onFileTap(_relativePath(name)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(getFileIcon(name, isDir: isDir), size: 48, color: getFileIconColor(name, isDir: isDir)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
            ),
            Text(isDir ? '文件夹' : _sizeStr(f['size']),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ]),
        ));
      },
    );
  }
}
