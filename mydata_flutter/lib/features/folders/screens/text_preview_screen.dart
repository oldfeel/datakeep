import 'dart:io';
import 'package:flutter/material.dart';
import '../../../shared/utils/open_system_file.dart';
import '../../../shared/utils/preview_limits.dart';

/// 只读文本预览（大文件截断提示）
class TextPreviewScreen extends StatefulWidget {
  final String title;
  final String filePath;

  const TextPreviewScreen({
    super.key,
    required this.title,
    required this.filePath,
  });

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  static const int _maxChars = 500000; // ~500KB 字符
  String? _content;
  bool _truncated = false;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      final size = await file.length();
      if (size > kMaxPreviewBytes) {
        throw PreviewTooLargeException(size);
      }
      var text = await file.readAsString();
      var truncated = false;
      if (text.length > _maxChars) {
        text = text.substring(0, _maxChars);
        truncated = true;
      }
      if (mounted) {
        setState(() {
          _content = text;
          _truncated = truncated;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '系统打开',
            onPressed: () async {
              final err = await openSystemFile(widget.filePath);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err), backgroundColor: Colors.red),
                );
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    if (_truncated)
                      MaterialBanner(
                        content: const Text('文件较大，仅显示前一部分内容'),
                        actions: [
                          TextButton(
                            onPressed: () {},
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _content ?? '',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
