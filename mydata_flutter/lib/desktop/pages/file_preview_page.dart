import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/device.dart';
import '../../core/models/folder.dart';
import '../../core/services/api_service.dart';
import '../../shared/utils/file_types.dart';
import '../../shared/utils/local_file_path.dart';
import '../../shared/utils/open_system_file.dart';
import '../../shared/utils/preview_limits.dart';
import '../../shared/widgets/audio_preview.dart';
import '../../shared/widgets/video_preview.dart';
import '../../features/folders/screens/image_preview_screen.dart';
import '../widgets/file_icon.dart';

class FilePreviewPage extends StatefulWidget {
  final Device device;
  final Folder folder;
  final String filePath;
  final VoidCallback onBack;
  final List<String>? siblingImagePaths;

  const FilePreviewPage({
    super.key,
    required this.device,
    required this.folder,
    required this.filePath,
    required this.onBack,
    this.siblingImagePaths,
  });

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  String? _tempFilePath;
  String? _tempDirPath;
  String? _textContent;
  String? _mediaPlayPath;
  bool _isLoading = false;
  bool _mediaLoading = false;
  String? _error;
  double? _progress;

  String get _fileName => widget.filePath.split('/').last;
  bool get _isImage => FileTypes.isImage(widget.filePath);
  bool get _isVideo => FileTypes.isVideo(widget.filePath);
  bool get _isAudio => FileTypes.isAudio(widget.filePath);
  bool get _isPdf => FileTypes.isPdf(widget.filePath);
  bool get _isText => FileTypes.isText(widget.filePath);
  bool get _isPlayableMedia => _isVideo || _isAudio;
  bool get _needsDownloadPreview =>
      FileTypes.needsDownloadPreview(widget.filePath) || _isPdf;

  String get _localFilePath =>
      joinLocalFilePath(widget.folder.path, widget.filePath);

  bool get _canUseLocalFile =>
      widget.device.isLocal &&
      widget.folder.path.isNotEmpty &&
      !widget.folder.isReadonlyAccess &&
      File(_localFilePath).existsSync();

  String? get _accessibleFilePath {
    if (_tempFilePath != null) return _tempFilePath;
    if (_canUseLocalFile) return _localFilePath;
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_needsDownloadPreview) {
      if (_canUseLocalFile) {
        if (_isText) {
          _loadLocalText();
        }
      } else {
        _loadFile();
      }
    }
    if (_isPlayableMedia && _accessibleFilePath != null) {
      _mediaPlayPath = _accessibleFilePath;
    }
  }

  Future<void> _loadLocalText() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final size = await File(_localFilePath).length();
      if (size > kMaxPreviewBytes) throw PreviewTooLargeException(size);
      var text = await File(_localFilePath).readAsString();
      if (text.length > 500000) {
        text = '${text.substring(0, 500000)}\n\n…（已截断）';
      }
      _textContent = text;
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      await _loadFile();
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _progress = null;
    });
    try {
      await _fetchToTemp(decodeText: _isText);
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMediaForPlayback() async {
    setState(() {
      _mediaLoading = true;
      _error = null;
    });
    try {
      await _fetchToTemp();
      if (mounted) {
        setState(() {
          _mediaPlayPath = _tempFilePath;
          _mediaLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _mediaLoading = false;
        });
      }
    }
  }

  Future<void> _fetchToTemp({bool decodeText = false}) async {
    if (_tempFilePath != null) return;
    final result = await ApiService.previewFileToTemp(
      widget.folder.id,
      widget.filePath,
      deviceId: widget.device.id,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _progress = total != null && total > 0 ? received / total : null;
        });
      },
    );
    _tempFilePath = result.path;
    _tempDirPath = result.tempDirPath;
    if (decodeText) {
      var text = await File(result.path).readAsString();
      if (text.length > 500000) {
        text = '${text.substring(0, 500000)}\n\n…（已截断）';
      }
      _textContent = text;
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
    final err = await openSystemFile(path);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('打开文件失败: $err'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _downloadFile() async {
    final src = await _ensureAccessiblePath();
    if (src == null) return;
    try {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
      final downloadDir = Directory('$home/Downloads');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
      final dest = File('${downloadDir.path}/$_fileName');
      await File(src).copy(dest.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已下载到: ${dest.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
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

  Future<void> _openFullscreenImage() async {
    final path = _accessibleFilePath;
    if (path == null) return;
    final siblings = widget.siblingImagePaths ?? [path];
    final idx = siblings.indexOf(widget.filePath);
    await showDesktopImageFullscreen(
      context,
      filePath: path,
      siblingPaths: siblings.map((p) {
        if (p.startsWith('/') || (p.length > 2 && p[1] == ':')) return p;
        final local = joinLocalFilePath(widget.folder.path, p);
        return File(local).existsSync() ? local : p;
      }).toList(),
      initialIndex: idx >= 0 ? idx : 0,
    );
  }

  @override
  void dispose() {
    if (_tempDirPath != null) {
      try {
        Directory(_tempDirPath!).deleteSync(recursive: true);
      } catch (_) {}
    } else if (_tempFilePath != null) {
      try {
        Directory(_tempFilePath!).parent.deleteSync(recursive: true);
      } catch (_) {}
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
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
          tooltip: '返回',
        ),
        const SizedBox(width: 12),
        Icon(
          getFileIcon(widget.filePath),
          color: getFileIconColor(widget.filePath),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _fileName,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _fileTypeLabel(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const Spacer(),
        if (_isImage && _accessibleFilePath != null)
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: '全屏',
            onPressed: _openFullscreenImage,
          ),
        IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: '系统打开',
          onPressed: _openInSystemApp,
        ),
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: '下载到 Downloads',
          onPressed: _downloadFile,
        ),
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

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_progress != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: _progress),
              ),
              const SizedBox(height: 8),
              Text('${(_progress! * 100).toStringAsFixed(0)}%'),
            ],
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _openInSystemApp,
              icon: const Icon(Icons.open_in_new),
              label: const Text('系统打开'),
            ),
          ],
        ),
      );
    }

    if (_isImage) {
      final path = _accessibleFilePath;
      if (path != null) {
        return GestureDetector(
          onDoubleTap: _openFullscreenImage,
          child: InteractiveViewer(
            child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
          ),
        );
      }
    }

    if (_isPdf) {
      final path = _accessibleFilePath;
      if (path != null) {
        return _buildExternalOnlyPreview(context);
      }
    }

    if (_isText && _textContent != null) {
      return Card(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              _textContent!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_progress != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(value: _progress),
              ),
            ],
          ],
        ),
      );
    }

    final icon = _isVideo ? Icons.videocam : Icons.audiotrack;
    final label = _isVideo ? '视频未在本地找到' : '音频未在本地找到';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
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
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

  Widget _buildExternalOnlyPreview(BuildContext context) {
    final icon = _isPdf ? Icons.picture_as_pdf : Icons.help_outline;
    final label = _isPdf ? 'PDF 文档' : '不支持预览此类型的文件';
    final hint = _isPdf ? '点击「系统打开」或下载后查看' : '请使用下载或系统打开';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 24),
          Text(label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
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
