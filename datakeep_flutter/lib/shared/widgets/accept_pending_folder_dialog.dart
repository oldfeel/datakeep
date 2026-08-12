import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/services/android_storage_service.dart';
import '../utils/sync_folder_paths.dart';

class AcceptPendingFolderResult {
  final bool accepted;
  final String? path;

  const AcceptPendingFolderResult({required this.accepted, this.path});
}

/// 接受共享文件夹：选择本机同步目录（Android 用 SAF，与 Syncthing Android 一致）
Future<AcceptPendingFolderResult?> showAcceptPendingFolderDialog({
  required BuildContext context,
  required String folderId,
  required String deviceName,
  required String label,
}) {
  return showDialog<AcceptPendingFolderResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AcceptPendingFolderDialog(
      folderId: folderId,
      deviceName: deviceName,
      label: label,
    ),
  );
}

class _AcceptPendingFolderDialog extends StatefulWidget {
  final String folderId;
  final String deviceName;
  final String label;

  const _AcceptPendingFolderDialog({
    required this.folderId,
    required this.deviceName,
    required this.label,
  });

  @override
  State<_AcceptPendingFolderDialog> createState() => _AcceptPendingFolderDialogState();
}

class _AcceptPendingFolderDialogState extends State<_AcceptPendingFolderDialog> {
  final _pathController = TextEditingController();
  bool _loadingDefault = true;
  bool _checkingWrite = false;
  bool? _pathWritable;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultPath();
  }

  Future<void> _loadDefaultPath() async {
    final path = await defaultSyncFolderPath(widget.folderId);
    if (!mounted) return;
    _pathController.text = path;
    await _checkWrite(path);
    if (mounted) setState(() => _loadingDefault = false);
  }

  Future<void> _checkWrite(String path) async {
    if (path.isEmpty) {
      setState(() => _pathWritable = null);
      return;
    }
    setState(() => _checkingWrite = true);
    final writable = await isSyncPathWritable(path);
    if (mounted) {
      setState(() {
        _checkingWrite = false;
        _pathWritable = writable;
      });
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    if (Platform.isAndroid) {
      setState(() => _picking = true);
      try {
        final picked = await AndroidStorageService.pickSyncFolder();
        if (picked != null && picked.path.isNotEmpty) {
          _pathController.text = picked.path;
          setState(() => _pathWritable = picked.writable);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('选择目录失败: $e'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _picking = false);
      }
      return;
    }
    final picked = await FilePicker.platform.getDirectoryPath();
    if (picked != null && picked.isNotEmpty) {
      _pathController.text = picked;
      await _checkWrite(picked);
    }
  }

  Future<void> _submit(bool accepted) async {
    if (!accepted) {
      Navigator.of(context).pop(const AcceptPendingFolderResult(accepted: false));
      return;
    }
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择本机同步目录')),
      );
      return;
    }
    final writable = _pathWritable ?? await isSyncPathWritable(path);
    if (!writable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isAndroid
                ? '该目录 Syncthing 无法写入。请授予「所有文件访问」权限，或选择 Android/media 下的目录。'
                : '该目录不可写，请重新选择',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
          action: Platform.isAndroid
              ? SnackBarAction(
                  label: '授权',
                  onPressed: () => AndroidStorageService.requestAllFilesAccess(),
                )
              : null,
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(AcceptPendingFolderResult(accepted: true, path: path));
  }

  @override
  Widget build(BuildContext context) {
    final displayLabel = widget.label.isNotEmpty ? widget.label : widget.folderId;

    return AlertDialog(
      title: const Text('收到共享文件夹'),
      content: SizedBox(
        width: 420,
        child: _loadingDefault
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('设备 "${widget.deviceName}" 邀请你同步文件夹：'),
                    const SizedBox(height: 12),
                    Text(displayLabel, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('文件夹 ID', style: Theme.of(context).textTheme.labelMedium),
                    SelectableText(
                      widget.folderId,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Text('本机同步目录', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pathController,
                            readOnly: Platform.isAndroid,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: '选择本机目录',
                              isDense: true,
                              suffixIcon: _checkingWrite
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : _pathWritable == true
                                      ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                      : _pathWritable == false
                                          ? const Icon(Icons.error_outline, color: Colors.red, size: 20)
                                          : null,
                            ),
                            style: const TextStyle(fontSize: 13),
                            minLines: 1,
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: _picking
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.folder_open),
                          tooltip: '浏览目录',
                          onPressed: _picking ? null : _pickDirectory,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Platform.isAndroid
                          ? '默认使用 Android/media 下目录（无需额外权限）。同步到 DCIM、下载等公共目录需授予「所有文件访问」权限。'
                          : '文件将同步到此目录，接受前请确认路径正确。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_pathWritable == false) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () => AndroidStorageService.requestAllFilesAccess(),
                        icon: const Icon(Icons.security, size: 18),
                        label: const Text('打开「所有文件访问」设置'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => _submit(false),
          child: const Text('忽略'),
        ),
        ElevatedButton(
          onPressed: (_loadingDefault || _checkingWrite) ? null : () => _submit(true),
          child: const Text('接受'),
        ),
      ],
    );
  }
}
