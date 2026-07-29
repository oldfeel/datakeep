import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/android_storage_service.dart';
import '../../../core/models/folder.dart';
import '../../../shared/utils/file_types.dart';
import '../../../shared/utils/local_file_path.dart';
import '../../../shared/utils/media_file_opener.dart';
import 'image_preview_screen.dart';

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
      final wasSyncing = _syncInfo?['status'] == 'syncing';
      setState(() => _syncInfo = info);
      final isSyncing = info['status'] == 'syncing';
      if (isSyncing || (wasSyncing && info['status'] == 'synced')) {
        await _loadFiles();
      }
    } catch (_) {}
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

  Future<void> _openMediaPreview(String filePath) async {
    await openMediaPreview(
      context,
      folderId: widget.folderId,
      folderPath: _folderInfo?.path ?? '',
      filePath: filePath,
      deviceId: widget.deviceId,
    );
  }

  Future<void> _openImagePreview(String filePath) async {
    final fileName = filePath.split('/').last;
    final folderPath = _folderInfo?.path ?? '';

    if (folderPath.isNotEmpty) {
      final localPath = joinLocalFilePath(folderPath, filePath);
      if (await File(localPath).exists()) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImagePreviewScreen(
              title: fileName,
              filePath: localPath,
            ),
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiService.previewFile(
        widget.folderId,
        filePath,
        deviceId: widget.deviceId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            title: fileName,
            bytes: response.bodyBytes,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('图片加载失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _previewFile(String filePath) async {
    if (FileTypes.isVideo(filePath) || FileTypes.isAudio(filePath)) {
      await _openMediaPreview(filePath);
      return;
    }

    if (FileTypes.isImage(filePath)) {
      await _openImagePreview(filePath);
      return;
    }

    try {
      final response = await ApiService.previewFile(
        widget.folderId,
        filePath,
        deviceId: widget.deviceId,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? 'text/plain';
        
        if (contentType.startsWith('image/')) {
          final fileName = filePath.split('/').last;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImagePreviewScreen(
                title: fileName,
                bytes: response.bodyBytes,
              ),
            ),
          );
        } else if (contentType.startsWith('text/') ||
            contentType.contains('json') ||
            contentType.contains('xml') ||
            contentType.contains('javascript')) {
          // 文本预览
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(filePath.split('/').last),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.6,
                child: SingleChildScrollView(
                  child: Text(
                    response.body,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          );
        } else {
          // 其他文件类型，显示信息
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('文件预览'),
              content: Text('文件类型: $contentType\n文件大小: ${_formatFileSize(response.bodyBytes.length)}'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('预览失败: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('预览失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  Widget _buildSyncBanner(BuildContext context) {
    final info = _syncInfo!;
    final status = info['status']?.toString() ?? 'unknown';
    final completion = (info['completion'] as num?)?.toDouble() ?? 0.0;
    final needFiles = (info['needFiles'] as num?)?.toInt() ?? 0;
    final localFiles = (info['localFiles'] as num?)?.toInt() ?? 0;
    final pullErrors = (info['pullErrors'] as num?)?.toInt() ?? 0;
    final state = info['state']?.toString() ?? '';
    final pathError = info['pathError']?.toString() ?? '';
    final needsPathFix = info['needsPathFix'] == true;
    final pathWritable = info['pathWritable'] != false;

    Color color;
    String title;
    IconData icon;
    if (status == 'error' || pullErrors > 0 || needsPathFix) {
      color = Colors.red;
      title = needsPathFix ? '目录无写入权限' : '同步出错';
      icon = Icons.error_outline;
    } else if (status == 'syncing') {
      color = Colors.orange;
      title = '正在同步…';
      icon = Icons.sync;
    } else if (status == 'waiting') {
      color = Colors.blue;
      title = '等待同步';
      icon = Icons.hourglass_empty;
    } else {
      color = Colors.green;
      title = '已同步';
      icon = Icons.check_circle_outline;
    }

    final showProgress = status == 'syncing' ||
        status == 'waiting' ||
        needFiles > 0 ||
        (completion > 0 && completion < 100);
    final progress = (completion / 100).clamp(0.0, 1.0);

    return Material(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                const Spacer(),
                Text(
                  status == 'synced'
                      ? '${completion.toStringAsFixed(0)}%'
                      : (completion > 0 ? '${completion.toStringAsFixed(0)}%' : ''),
                  style: TextStyle(color: color, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            if (showProgress) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                color: color,
              ),
              const SizedBox(height: 6),
              Text(
                status == 'waiting'
                    ? '正在等待与对端建立连接并获取文件列表…'
                    : '本地 $localFiles 个文件，待同步 $needFiles 个${state.isNotEmpty ? ' · $state' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (status == 'synced') ...[
              const SizedBox(height: 4),
              Text(
                '本地 $localFiles 个文件',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (pathError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(pathError, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
            ],
            if (needsPathFix) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _fixingPath ? null : _requestStorageAccess,
                    icon: const Icon(Icons.security, size: 18),
                    label: const Text('授予存储权限'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _fixingPath ? null : _fixFolderPath,
                    icon: _fixingPath
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.folder_open, size: 18),
                    label: Text(_fixingPath ? '处理中…' : '选择/修复目录'),
                  ),
                ],
              ),
            ] else if (!pathWritable) ...[
              const SizedBox(height: 4),
              Text('路径写入检测中…', style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
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

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isDir
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        child: Icon(
          isDir ? Icons.folder : _getFileIcon(name),
          color: isDir
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDir) Text(_formatFileSize(size)),
          Text(_formatDate(modTime)),
        ],
      ),
      trailing: isDir
          ? const Icon(Icons.chevron_right)
          : IconButton(
              icon: const Icon(Icons.preview),
              onPressed: () {
                final path = _currentPath.isEmpty
                    ? name
                    : '${_currentPath.join('/')}/$name';
                _previewFile(path);
              },
            ),
      onTap: () {
        if (isDir) {
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

