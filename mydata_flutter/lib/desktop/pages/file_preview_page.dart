import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../widgets/file_icon.dart';

class FilePreviewPage extends StatefulWidget {
  final Device device;
  final Folder folder;
  final String filePath;
  final VoidCallback onBack;

  const FilePreviewPage({
    super.key,
    required this.device,
    required this.folder,
    required this.filePath,
    required this.onBack,
  });

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  String? _tempFilePath;
  String? _textContent;
  bool _isLoading = true;
  String? _error;

  String get _ext => widget.filePath.toLowerCase().split('.').lastOrNull ?? '';
  String get _fileName => widget.filePath.split('/').last;

  bool get _isImage => ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico'].contains(_ext);
  bool get _isVideo => ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v'].contains(_ext);
  bool get _isAudio => ['mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a'].contains(_ext);
  bool get _isPdf => _ext == 'pdf';
  bool get _isText => ['txt', 'md', 'json', 'xml', 'yaml', 'yml', 'js', 'ts', 'html', 'css',
                        'py', 'java', 'cpp', 'c', 'go', 'rs', 'dart', 'csv', 'log'].contains(_ext);
  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  Future<void> _loadFile() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final response = await ApiService.previewFile(widget.folder.id, widget.filePath);
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final bytes = response.bodyBytes;
      final tempDir = await Directory.systemTemp.createTemp('mydata_');
      final tempFile = File('${tempDir.path}/$_fileName');
      await tempFile.writeAsBytes(bytes);
      _tempFilePath = tempFile.path;

      if (_isText) {
        _textContent = utf8.decode(bytes);
      }

      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _openInSystemApp() async {
    if (_tempFilePath == null) return;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [_tempFilePath!]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_tempFilePath!]);
      } else if (Platform.isWindows) {
        await Process.run('start', [_tempFilePath!], runInShell: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开文件失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _downloadFile() async {
    if (_tempFilePath == null) return;
    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final downloadDir = Directory('$home/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final dest = File('${downloadDir.path}/$_fileName');
      await File(_tempFilePath!).copy(dest.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已下载到: ${dest.path}'), backgroundColor: Colors.green, duration: const Duration(seconds: 4)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_tempFilePath != null) {
      try { Directory(_tempFilePath!).parent.deleteSync(recursive: true); } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          Expanded(child: _buildPreview(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack, tooltip: '返回'),
        const SizedBox(width: 12),
        Icon(getFileIcon(widget.filePath), color: getFileIconColor(widget.filePath)),
        const SizedBox(width: 12),
        Expanded(child: Text(_fileName, style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text(_fileTypeLabel(), style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        )),
        const Spacer(),
        IconButton(icon: const Icon(Icons.open_in_new), tooltip: '系统打开', onPressed: _tempFilePath != null ? _openInSystemApp : null),
        IconButton(icon: const Icon(Icons.download), tooltip: '下载到 Downloads', onPressed: _tempFilePath != null ? _downloadFile : null),
      ],
    );
  }

  String _fileTypeLabel() {
    if (_isImage) return '图片';
    if (_isVideo) return '视频';
    if (_isAudio) return '音频';
    if (_isPdf) return 'PDF';
    if (_isText) return '文本';
    return '文件';
  }

  Widget _buildPreview(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    // 图片
    if (_isImage && _tempFilePath != null) {
      return InteractiveViewer(
        child: Center(child: Image.file(File(_tempFilePath!), fit: BoxFit.contain)),
      );
    }

    // 文本
    if (_isText && _textContent != null) {
      return Card(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(_textContent!, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ),
      );
    }

    // 视频 / 音频 / PDF / 其他 => 预览占位 + 系统打开
    final icon = _isVideo ? Icons.videocam : (_isAudio ? Icons.audiotrack : (_isPdf ? Icons.picture_as_pdf : Icons.help_outline));
    final label = _isVideo ? '视频文件' : (_isAudio ? '音频文件' : (_isPdf ? 'PDF 文档' : '不支持预览此类型的文件'));
    final hint = _isVideo || _isAudio || _isPdf ? '点击右侧"系统打开"按钮查看' : '请使用下载功能获取文件';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 80, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 24),
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(hint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openInSystemApp,
            icon: const Icon(Icons.open_in_new),
            label: const Text('系统打开'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: const Text('下载'),
          ),
        ],
      ),
    );
  }
}
