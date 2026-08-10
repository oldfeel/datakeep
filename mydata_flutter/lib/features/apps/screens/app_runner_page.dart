import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/utils/open_url_external.dart';

/// 在本地 HTTP 服务上打开应用目录（入口默认 index.html）
class AppRunnerPage extends StatefulWidget {
  final String appPath;
  final String title;
  final String entry;

  const AppRunnerPage({
    super.key,
    required this.appPath,
    required this.title,
    this.entry = 'index.html',
  });

  @override
  State<AppRunnerPage> createState() => _AppRunnerPageState();
}

class _AppRunnerPageState extends State<AppRunnerPage> {
  HttpServer? _server;
  String? _url;
  String? _error;
  String? _openHint;
  WebViewController? _controller;
  bool _useWebView = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _openBrowser(String url) async {
    final ok = await openUrlExternal(url);
    if (!mounted) return;
    setState(() {
      _openHint = ok
          ? '已在系统浏览器打开'
          : '无法自动打开浏览器，可复制地址手动打开';
    });
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制地址：$url')),
      );
    }
  }

  Future<void> _start() async {
    try {
      final root = Directory(widget.appPath);
      if (!root.existsSync()) {
        setState(() => _error = '应用目录不存在: ${widget.appPath}');
        return;
      }

      var entryRel = widget.entry;
      final meta = File(p.join(widget.appPath, 'app.json'));
      if (meta.existsSync()) {
        try {
          final m = json.decode(await meta.readAsString());
          if (m is Map && m['entry'] != null) {
            entryRel = m['entry'].toString();
          }
        } catch (_) {}
      }

      final entryFile = File(p.join(widget.appPath, entryRel));
      if (!entryFile.existsSync()) {
        setState(() => _error = '缺少入口文件: $entryRel');
        return;
      }

      final handler = createStaticHandler(
        widget.appPath,
        defaultDocument: entryRel,
        listDirectories: false,
      );
      _server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);
      final url = 'http://127.0.0.1:${_server!.port}/$entryRel';
      final canWebView = !kIsWeb &&
          (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

      if (canWebView) {
        final c = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(url));
        setState(() {
          _url = url;
          _controller = c;
          _useWebView = true;
        });
      } else {
        setState(() => _url = url);
        await _openBrowser(url);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    unawaited(_server?.close(force: true) ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_url != null)
            IconButton(
              tooltip: '浏览器打开',
              icon: const Icon(Icons.open_in_browser),
              onPressed: () => _openBrowser(_url!),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : _useWebView && _controller != null
              ? WebViewWidget(controller: _controller!)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_url == null) const CircularProgressIndicator(),
                      if (_url == null) const SizedBox(height: 16),
                      Text(
                        _url == null
                            ? '正在启动…'
                            : '${_openHint ?? '应用已就绪'}\n$_url',
                        textAlign: TextAlign.center,
                      ),
                      if (_url != null) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _openBrowser(_url!),
                          child: const Text('再次打开'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _url!));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制地址')),
                            );
                          },
                          child: const Text('复制地址'),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
