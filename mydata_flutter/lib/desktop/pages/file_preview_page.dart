import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../../shared/utils/file_types.dart';
import '../../shared/utils/local_file_path.dart';
import '../../shared/widgets/audio_preview.dart';
import '../../shared/widgets/video_preview.dart';
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
  String? _mediaPlayPath;
  bool _isLoading = false;
  bool _mediaLoading = false;
  String? _error;

  String get _fileName => widget.filePath.split('/').last;
  bool get _isImage => FileTypes.isImage(widget.filePath);
  bool get _isVideo => FileTypes.isVideo(widget.filePath);
  bool get _isAudio => FileTypes.isAudio(widget.filePath);
  bool get _isPdf => FileTypes.isPdf(widget.filePath);
  bool get _isText => FileTypes.isText(widget.filePath);
  bool get _isPlayableMedia => _isVideo || _isAudio;
  bool get _needsDownloadPreview => FileTypes.needsDownloadPreview(widget.filePath);

  String get _localFilePath => joinLocalFilePath(widget.folder.path, widget.filePath);

  String? get _accessibleFilePath {
    if (_tempFilePath != null) return _tempFilePath;
    if (File(_localFilePath).existsSync()) return _localFilePath;
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_needsDownloadPreview) _loadFile();
    if (_isPlayableMedia && _accessibleFilePath != null) {
      _mediaPlayPath = _accessibleFilePath;
    }
  }

  Future<void> _loadFile() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      await _fetchToTemp(decodeText: _isText);
      if (mounted) setState(() { _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadMediaForPlayback() async {
    setState(() { _mediaLoading = true; _error = null; });
    try {
      await _fetchToTemp();
      if (mounted) {
        setState(() {
          _mediaPlayPath = _tempFilePath;
          _mediaLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _mediaLoading = false; });
    }
  }

  Future<void> _fetchToTemp({bool decodeText = false}) async {
    if (_tempFilePath != null) return;
    final response = await ApiService.previewFile(widget.folder.id, widget.filePath);
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

    final bytes = response.bodyBytes;
    final tempDir = await Directory.systemTemp.createTemp('mydata_');
    final tempFile = File('${tempDir.path}/$_fileName');
    await tempFile.writeAsBytes(bytes);
    _tempFilePath = tempFile.path;

    if (decodeText) {
      _textContent = utf8.decode(bytes);
    }
  }

  Future<String?> _ensureAccessiblePath() async {
    final existing = _accessibleFilePath;
    if (existing != null) return existing;
    try {
      await _fetchToTemp();
      return _tempFilePath;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取文件失败: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  Future<void> _openInSystemApp() async {
    final path = await _ensureAccessiblePath();
    if (path == null) return;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('start', [path], runInShell: true);
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
    final src = await _ensureAccessiblePath();
    if (src == null) return;
    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final downloadDir = Directory('$home/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final dest = File('${downloadDir.path}/$_fileName');
      await File(src).copy(dest.path);
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
        IconButton(icon: const Icon(Icons.open_in_new), tooltip: '系统打开', onPressed: _openInSystemApp),
        IconButton(icon: const Icon(Icons.download), tooltip: '下载到 Downloads', onPressed: _downloadFile),
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
    if (_isPlayableMedia) return _buildMediaPreview(context);

    if (!_needsDownloadPreview) {
      return _buildExternalOnlyPreview(context);
    }

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

    if (_isImage && _tempFilePath != null) {
      return InteractiveViewer(
        child: Center(child: Image.file(File(_tempFilePath!), fit: BoxFit.contain)),
      );
    }

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

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildMediaPreview(BuildContext context) {
    if (_mediaPlayPath != null) {
      if (_isVideo) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.expand(
            child: VideoPreview(filePath: _mediaPlayPath!),
          ),
        );
      }
      return Center(
        child: AudioPreview(filePath: _mediaPlayPath!, title: _fileName),
      );
    }

    if (_mediaLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final icon = _isVideo ? Icons.videocam : Icons.audiotrack;
    final label = _isVideo ? '视频未在本地找到' : '音频未在本地找到';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 80, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 24),
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '文件可能尚未同步完成，可尝试下载后播放',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadMediaForPlayback,
            icon: const Icon(Icons.play_arrow),
            label: const Text('下载并播放'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openInSystemApp,
            icon: const Icon(Icons.open_in_new),
            label: const Text('系统打开'),
          ),
        ],
      ),
    );
  }

  /// PDF / dump 等：占位提示 + 操作按钮
  Widget _buildExternalOnlyPreview(BuildContext context) {
    final icon = _isPdf ? Icons.picture_as_pdf : Icons.help_outline;
    final label = _isPdf ? 'PDF 文档' : '不支持预览此类型的文件';
    final hint = _isPdf ? '点击"系统打开"按钮查看' : '请使用下载或系统打开';

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
