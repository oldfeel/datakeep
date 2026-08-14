import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/android_storage_service.dart';
import '../../../core/models/folder.dart';
import '../../../features/folders/providers/folder_provider.dart';
import '../../../shared/utils/app_dir.dart';
import '../../../shared/utils/file_types.dart';
import '../../../shared/utils/file_opener.dart';
import '../../../shared/widgets/add_item_dialog.dart';
import '../../../shared/widgets/folder_sync_banner.dart';
import '../../../shared/widgets/share_to_cloud_sheet.dart';

class FolderDetailScreen extends StatefulWidget {
  final String deviceId;
  final String folderId;

  const FolderDetailScreen({
    super.key,
    required this.deviceId,
    required this.folderId,
  });

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _error;
  List<String> _currentPath = [];
  Folder? _folderInfo;
  Map<String, dynamic>? _syncInfo;
  Timer? _syncTimer;
  bool _fixingPath = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refreshSync());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSync() async {
    // 远程/只读不拉本机 Syncthing 同步状态
    if (_folderInfo?.isLocal != true || _folderInfo?.isReadonlyAccess == true) {
      return;
    }
    try {
      final info = await ApiService.getFolderSyncStatus(widget.folderId);
      if (!mounted) return;
      debugPrint(
        '[sync-ui][android/mobile] folder=${widget.folderId} '
        'status=${info['status']} completion=${info['completion']} '
        'inSync=${info['inSyncFiles']}/${info['globalFiles']} '
        'local=${info['localFiles']} need=${info['needFiles']} '
        'needBytes=${info['needBytes']}',
      );
      final wasSyncing = _syncInfo?['status'] == 'syncing';
      setState(() {
        _syncInfo = info;
        // 列表 path 为空时，用同步状态里的 currentPath 补全，便于识别子目录应用
        final cur = info['currentPath']?.toString() ?? '';
        if (cur.isNotEmpty &&
            (_folderInfo?.path.isEmpty ?? true) &&
            _folderInfo != null) {
          _folderInfo = _folderInfo!.copyWith(path: cur);
        }
      });
      final isSyncing = info['status'] == 'syncing';
      if (isSyncing || (wasSyncing && info['status'] == 'synced')) {
        await _loadFiles();
      }
    } catch (e) {
      debugPrint('[sync-ui][android/mobile] 刷新失败: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 加载文件夹信息
      final folders = await ApiService.getDeviceFolders(widget.deviceId);
      _folderInfo = folders.firstWhere(
        (f) => f.id == widget.folderId,
        orElse: () => Folder(
          id: widget.folderId,
          name: '未知文件夹',
          path: '',
          deviceId: widget.deviceId,
          isLocal: widget.deviceId == 'local',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          status: 'synced',
          fileCount: 0,
          totalSize: 0,
        ),
      );

      // 加载文件列表
      await _refreshSync();
      await _loadFiles();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadFiles() async {
    try {
      final path = _currentPath.isEmpty ? null : _currentPath.join('/');
      final files = await ApiService.getFolderFiles(
        widget.folderId,
        path: path,
        deviceId: widget.deviceId,
      );
      setState(() {
        _files = files;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  void _navigateToFolder(String folderName) {
    setState(() {
      _currentPath = [..._currentPath, folderName];
    });
    _loadFiles();
  }

  void _navigateUp() {
    if (_currentPath.isNotEmpty) {
      setState(() {
        _currentPath = _currentPath.sublist(0, _currentPath.length - 1);
      });
      _loadFiles();
    }
  }

  void _navigateToPath(int index) {
    setState(() {
      _currentPath = _currentPath.sublist(0, index + 1);
    });
    _loadFiles();
  }

  String get _absoluteCurrentPath {
    final root = (_folderInfo?.path.isNotEmpty == true)
        ? _folderInfo!.path
        : (_syncInfo?['currentPath']?.toString() ?? '');
    if (_currentPath.isEmpty) return root;
    return p.join(root, p.joinAll(_currentPath));
  }

  bool get _canAddHere =>
      _folderInfo?.isLocal == true &&
      (_absoluteCurrentPath.isNotEmpty) &&
      _folderInfo?.isReadonlyAccess != true;

  void _showAddDialog() {
    AddItemDialog.show(
      context,
      scope: AddItemScope.insideFolder,
      parentPath: _absoluteCurrentPath,
      parentFolderId: widget.folderId,
      onDone: _loadFiles,
    );
  }

  bool _entryIsApp(String name, [Map<String, dynamic>? file]) {
    if (file != null && file['isApp'] == true) return true;
    if (_folderInfo?.isLocal != true) return false;
    final abs = p.join(_absoluteCurrentPath, name);
    if (abs.isEmpty || abs == name) return false;
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

  Future<void> _previewFile(String filePath) async {
    final images = _files
        .where((f) {
          final t = f['type']?.toString();
          final isDir = t == 'dir' || f['isDir'] == true;
          if (isDir) return false;
          final name = f['name']?.toString() ?? '';
          final path = _currentPath.isEmpty ? name : '${_currentPath.join('/')}/$name';
          return FileTypes.isImage(path);
        })
        .map((f) {
          final name = f['name']?.toString() ?? '';
          return _currentPath.isEmpty ? name : '${_currentPath.join('/')}/$name';
        })
        .toList();

    await openFilePreview(
      context,
      folderId: widget.folderId,
      folderPath: _folderInfo?.path ?? '',
      filePath: filePath,
      deviceId: widget.deviceId,
      siblingImagePaths: images,
    );
  }


  Future<void> _fixFolderPath() async {
    if (_fixingPath) return;
    setState(() => _fixingPath = true);
    try {
      // 先尝试重新扫描（用户可能刚授予 All files access）
      var result = await ApiService.fixFolderPath(widget.folderId);
      await _refreshSync();
      final writable = _syncInfo?['pathWritable'] == true;
      if (!writable && mounted) {
        final picked = await AndroidStorageService.pickSyncFolder();
        if (picked != null && picked.writable) {
          result = await ApiService.fixFolderPath(widget.folderId, path: picked.path);
        } else if (picked != null && !picked.writable) {
          throw Exception('所选目录仍不可写，请授予「所有文件访问」权限');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message']?.toString() ?? '已更新同步目录'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _fixingPath = false);
    }
  }

  Future<void> _requestStorageAccess() async {
    await AndroidStorageService.requestAllFilesAccess();
  }

  Future<void> _rescanFolder() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await ApiService.scanFolder(widget.folderId);
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
      await ApiService.resetFolderIndex(widget.folderId);
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

  Widget _buildSyncBanner(BuildContext context) {
    final info = _syncInfo!;
    final needsPathFix = info['needsPathFix'] == true;
    final pathWritable = info['pathWritable'] != false;
    final stalled =
        info['status']?.toString() == 'stalled' || info['stalled'] == true;

    final actionButtons = <Widget>[];
    if (needsPathFix) {
      actionButtons.addAll([
        FilledButton.icon(
          onPressed: _fixingPath ? null : _requestStorageAccess,
          icon: const Icon(Icons.security, size: 18),
          label: const Text('授予存储权限'),
        ),
        OutlinedButton.icon(
          onPressed: _fixingPath ? null : _fixFolderPath,
          icon: _fixingPath
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_open, size: 18),
          label: Text(_fixingPath ? '处理中…' : '选择/修复目录'),
        ),
      ]);
    } else if (!pathWritable) {
      actionButtons.add(
        Text(
          '路径写入检测中…',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (stalled || needsPathFix) {
      actionButtons.add(
        OutlinedButton.icon(
          onPressed: _scanning ? null : _rescanFolder,
          icon: _scanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          label: Text(_scanning ? '处理中…' : '重新扫描'),
        ),
      );
      actionButtons.add(
        FilledButton.icon(
          onPressed: _scanning ? null : _resetFolderIndex,
          icon: const Icon(Icons.restart_alt, size: 18),
          label: const Text('重建索引'),
        ),
      );
    }

    final Widget? actions = actionButtons.isEmpty
        ? null
        : Wrap(spacing: 8, runSpacing: 8, children: actionButtons);

    return FolderSyncBanner(info: info, actions: actions);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: isDesktop ? null : AppBar(
        title: Text(_folderInfo?.name ?? '文件夹详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: (!isDesktop && _canAddHere && !_isLoading && _error == null)
          ? FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '加载失败',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (_syncInfo != null &&
                        _folderInfo?.isLocal == true &&
                        _folderInfo?.isReadonlyAccess != true)
                      _buildSyncBanner(context),
                    // 桌面端标题栏
                    if (isDesktop)
                      Container(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              tooltip: '返回',
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _folderInfo?.name ?? '文件夹详情',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const Spacer(),
                            if (_canAddHere)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ElevatedButton.icon(
                                  onPressed: _showAddDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加'),
                                ),
                              ),
                            ElevatedButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh),
                              label: const Text('刷新'),
                            ),
                          ],
                        ),
                      ),
                    // 面包屑导航
                    _buildBreadcrumbs(),
                    // 文件列表
                    Expanded(
                      child: _files.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.folder_open,
                                    size: 64,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '该目录为空',
                                    style: Theme.of(context).textTheme.headlineSmall,
                                  ),
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
                            )
                          : _buildFileList(isDesktop),
                    ),
                  ],
                ),
    );
  }

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: _currentPath.isEmpty ? null : () {
              setState(() {
                _currentPath = [];
              });
              _loadFiles();
            },
            tooltip: '返回根目录',
          ),
          if (_currentPath.isNotEmpty) ...[
            const Icon(Icons.chevron_right, size: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _currentPath.asMap().entries.map((entry) {
                    final index = entry.key;
                    final segment = entry.value;
                    final isLast = index == _currentPath.length - 1;
                    return Row(
                      children: [
                        if (isLast)
                          Text(
                            segment,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          )
                        else
                          InkWell(
                            onTap: () => _navigateToPath(index),
                            child: Text(
                              segment,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                        if (!isLast) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 16),
                          const SizedBox(width: 4),
                        ],
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileList(bool isDesktop) {
    bool isDirEntry(Map<String, dynamic> f) {
      final t = f['type'];
      return t == 1 ||
          t == '1' ||
          t == 'dir' ||
          t == true ||
          f['isDir'] == true;
    }

    // 先显示文件夹，再显示文件
    final folders = _files.where(isDirEntry).toList();
    final files = _files.where((f) => !isDirEntry(f)).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: folders.length + files.length,
      itemBuilder: (context, index) {
        if (index < folders.length) {
          return _buildFileItem(folders[index], isDesktop, true);
        } else {
          return _buildFileItem(
            files[index - folders.length],
            isDesktop,
            false,
          );
        }
      },
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file, bool isDesktop, bool isDir) {
    final name = file['name'] as String? ?? '未知';
    final size = file['size'] as int? ?? 0;
    final modTime = file['modTime'] as int? ?? 0;
    final isApp = isDir && _entryIsApp(name, file);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isApp
            ? Theme.of(context).colorScheme.tertiaryContainer
            : (isDir
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.secondaryContainer),
        child: Icon(
          isApp ? Icons.apps : (isDir ? Icons.folder : _getFileIcon(name)),
          color: isApp
              ? Theme.of(context).colorScheme.onTertiaryContainer
              : (isDir
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSecondaryContainer),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(name)),
          if (isApp) ...[
            const SizedBox(width: 8),
            Text(
              '应用',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDir) Text(_formatFileSize(size)),
          Text(_formatDate(modTime)),
        ],
      ),
      trailing: isApp
          ? IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '浏览文件',
              onPressed: () => _navigateToFolder(name),
            )
          : (isDir
              ? const Icon(Icons.chevron_right)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share_outlined),
                      tooltip: '分享到互联网',
                      onPressed: () {
                        final path = _currentPath.isEmpty
                            ? name
                            : '${_currentPath.join('/')}/$name';
                        showShareToCloudSheet(
                          context,
                          folderPath: _folderInfo?.path ?? '',
                          relativePath: path,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.preview),
                      onPressed: () {
                        final path = _currentPath.isEmpty
                            ? name
                            : '${_currentPath.join('/')}/$name';
                        _previewFile(path);
                      },
                    ),
                  ],
                )),
      onTap: () {
        if (isApp && _folderInfo?.isLocal == true) {
          _openEntryApp(name);
        } else if (isDir) {
          _navigateToFolder(name);
        } else {
          final path = _currentPath.isEmpty
              ? name
              : '${_currentPath.join('/')}/$name';
          _previewFile(path);
        }
      },
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp'].contains(ext)) {
      return Icons.image;
    } else if (ext == 'pdf') {
      return Icons.picture_as_pdf;
    } else if (['doc', 'docx', 'txt', 'rtf'].contains(ext)) {
      return Icons.description;
    } else if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv'].contains(ext)) {
      return Icons.video_file;
    } else if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'wma'].contains(ext)) {
      return Icons.audiotrack;
    } else if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.archive;
    } else {
      return Icons.insert_drive_file;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  String _formatDate(int timestamp) {
    if (timestamp == 0) return '未知时间';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

