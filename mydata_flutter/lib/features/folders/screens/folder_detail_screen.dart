import 'package:flutter/material.dart';
import '../../../core/services/api_service.dart';
import '../../../core/models/folder.dart';

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

  @override
  void initState() {
    super.initState();
    _loadData();
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

  void _previewFile(String filePath) async {
    try {
      final response = await ApiService.previewFile(
        widget.folderId,
        filePath,
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? 'text/plain';
        
        // 根据内容类型显示不同的预览
        if (contentType.startsWith('image/')) {
          // 图片预览
          showDialog(
            context: context,
            builder: (context) => Dialog(
              child: InteractiveViewer(
                child: Image.memory(
                  response.bodyBytes,
                  fit: BoxFit.contain,
                ),
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
    // 先显示文件夹，再显示文件
    final folders = _files.where((f) => f['isDir'] == true).toList();
    final files = _files.where((f) => f['isDir'] != true).toList();

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

