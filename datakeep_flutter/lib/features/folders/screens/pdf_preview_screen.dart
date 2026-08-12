import 'package:flutter/material.dart';
import '../../../shared/utils/open_system_file.dart';

/// PDF 预览：调用系统应用打开（避免 pdfrx/pdfium 在 Linux 拉取失败导致无法编译）
class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final String filePath;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.filePath,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  String? _error;
  bool _opening = true;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final err = await openSystemFile(widget.filePath);
    if (!mounted) return;
    setState(() {
      _opening = false;
      _error = err;
    });
    if (err == null) {
      // 已交给系统应用，返回上一页
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: _opening
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在用系统应用打开 PDF…'),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.picture_as_pdf,
                      size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(_error ?? '已尝试打开'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _opening = true;
                        _error = null;
                      });
                      _open();
                    },
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('再次系统打开'),
                  ),
                ],
              ),
      ),
    );
  }
}
