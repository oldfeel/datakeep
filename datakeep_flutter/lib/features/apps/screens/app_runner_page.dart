import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/utils/open_url_external.dart';

/// 在本地 HTTP 服务上打开应用目录（入口默认 index.html）
///
/// `/__datakeep/data/<rel>`：GET/PUT/DELETE；目录 GET 返回文件列表。
/// `/__datakeep/revision`：`{dataRev,appRev}`（目录内文件最大 mtime，毫秒），供自动刷新。
/// 启动时按 app.json 的 `syncIgnore` 合并写入 `.stignore`。
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
  String? _entryRel;
  String? _error;
  String? _openHint;
  String? _webError;
  WebViewController? _controller;
  bool _useWebView = false;

  Timer? _revTimer;
  int? _lastAppRev;
  int? _lastDataRev;
  DateTime? _localDataWriteAt;
  bool _reloadingApp = false;

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

  /// 由应用路径派生稳定本机端口（18765–19764），冲突则回退随机端口。
  int _stablePortFor(String appPath) {
    var h = 0;
    for (final c in appPath.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return 18765 + (h % 1000);
  }

  /// 将 URL 中 data 相对路径解析到 appPath/data 下；非法则 null。
  String? _resolveDataPath(
    String appPath,
    String requestPath, {
    bool allowRoot = false,
  }) {
    const prefix = '/__datakeep/data/';
    if (!requestPath.startsWith(prefix)) return null;
    var rel = requestPath.substring(prefix.length);
    try {
      rel = Uri.decodeComponent(rel);
    } catch (_) {}
    while (rel.endsWith('/')) {
      rel = rel.substring(0, rel.length - 1);
    }
    if (rel.contains('..') || p.isAbsolute(rel)) {
      return null;
    }
    final dataRoot = p.normalize(p.join(appPath, 'data'));
    if (rel.isEmpty) {
      return allowRoot ? dataRoot : null;
    }
    final full = p.normalize(p.join(dataRoot, rel));
    if (!p.isWithin(dataRoot, full) && full != dataRoot) {
      return null;
    }
    return full;
  }

  Future<Response> _listDataFiles(String dataRoot, String full) async {
    final dir = Directory(full);
    if (!await dir.exists()) {
      return Response.notFound('不存在');
    }
    final files = <String>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: dataRoot).replaceAll('\\', '/');
      if (rel.contains('..')) continue;
      files.add(rel);
    }
    files.sort();
    return Response.ok(
      jsonEncode({'files': files}),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  /// dataRev = data/ 下文件最大 mtime；appRev = 其余应用文件最大 mtime。
  Future<Map<String, int>> _computeRevision(String appPath) async {
    final dataRoot = p.normalize(p.join(appPath, 'data'));
    var dataRev = 0;
    var appRev = 0;
    final root = Directory(appPath);
    if (!await root.exists()) {
      return {'dataRev': 0, 'appRev': 0};
    }
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      try {
        final m = (await entity.stat()).modified.millisecondsSinceEpoch;
        final inData = p.isWithin(dataRoot, entity.path) ||
            p.equals(dataRoot, entity.path);
        if (inData) {
          if (m > dataRev) dataRev = m;
        } else {
          if (m > appRev) appRev = m;
        }
      } catch (_) {}
    }
    return {'dataRev': dataRev, 'appRev': appRev};
  }

  Response _revisionResponse(Map<String, int> rev) {
    return Response.ok(
      jsonEncode({
        'dataRev': rev['dataRev'] ?? 0,
        'appRev': rev['appRev'] ?? 0,
      }),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': 'no-store',
      },
    );
  }

  /// 按 app.json 的 syncIgnore 合并写入应用根目录 .stignore。
  Future<void> _ensureSyncIgnore(String appPath) async {
    final meta = File(p.join(appPath, 'app.json'));
    if (!meta.existsSync()) return;
    List<String> rules = const [];
    try {
      final m = json.decode(await meta.readAsString());
      if (m is Map && m['syncIgnore'] is List) {
        rules = (m['syncIgnore'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty && !e.startsWith('//'))
            .toList();
      }
    } catch (_) {
      return;
    }
    if (rules.isEmpty) return;

    final stignore = File(p.join(appPath, '.stignore'));
    final existing = stignore.existsSync()
        ? (await stignore.readAsLines())
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    final merged = <String>[...existing];
    var changed = false;
    for (final r in rules) {
      if (!merged.contains(r)) {
        merged.add(r);
        changed = true;
      }
    }
    if (!changed) return;
    await stignore.writeAsString('${merged.join('\n')}\n');
    debugPrint('[AppRunner] 已合并 syncIgnore 到 .stignore: $rules');
  }

  Handler _withNoStore(Handler inner) {
    return (Request request) async {
      final res = await inner(request);
      return res.change(headers: {'Cache-Control': 'no-store'});
    };
  }

  Handler _buildHandler(String appPath, String entryRel) {
    final staticHandler = _withNoStore(
      createStaticHandler(
        appPath,
        defaultDocument: entryRel,
        listDirectories: false,
      ),
    );
    final dataRoot = p.normalize(p.join(appPath, 'data'));

    return (Request request) async {
      final path = request.requestedUri.path;
      if (path == '/__datakeep/revision') {
        if (request.method != 'GET') {
          return Response(405, body: '仅支持 GET');
        }
        final rev = await _computeRevision(appPath);
        return _revisionResponse(rev);
      }
      if (path.startsWith('/__datakeep/data/') || path == '/__datakeep/data') {
        final normalized =
            path == '/__datakeep/data' ? '/__datakeep/data/' : path;
        final full = _resolveDataPath(appPath, normalized, allowRoot: true);
        if (full == null) {
          return Response.forbidden('非法路径');
        }
        if (request.method == 'GET') {
          final asDir = Directory(full);
          if (await asDir.exists()) {
            return _listDataFiles(dataRoot, full);
          }
          final f = File(full);
          if (!await f.exists()) {
            return Response.notFound('不存在');
          }
          final bytes = await f.readAsBytes();
          return Response.ok(
            bytes,
            headers: {
              'Content-Type': 'application/octet-stream',
              'Cache-Control': 'no-store',
            },
          );
        }
        if (request.method == 'PUT') {
          if (full == dataRoot || await Directory(full).exists()) {
            return Response.forbidden('不能 PUT 目录');
          }
          final bytes = await request.read().fold<BytesBuilder>(
            BytesBuilder(copy: false),
            (b, chunk) {
              b.add(chunk);
              return b;
            },
          );
          final f = File(full);
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes.takeBytes(), flush: true);
          _localDataWriteAt = DateTime.now();
          return Response.ok(
            '{"ok":true}',
            headers: {'Content-Type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'DELETE') {
          final f = File(full);
          if (await f.exists()) {
            await f.delete();
            _localDataWriteAt = DateTime.now();
            return Response.ok(
              '{"ok":true}',
              headers: {'Content-Type': 'application/json; charset=utf-8'},
            );
          }
          return Response.notFound('不存在');
        }
        return Response(405, body: '仅支持 GET/PUT/DELETE');
      }
      return staticHandler(request);
    };
  }

  Future<void> _reloadWebViewForAppUpdate() async {
    final c = _controller;
    final entry = _entryRel;
    if (c == null || entry == null || _server == null) return;
    _reloadingApp = true;
    try {
      final url =
          'http://127.0.0.1:${_server!.port}/$entry?_r=${DateTime.now().millisecondsSinceEpoch}';
      _url = url;
      await c.loadRequest(Uri.parse(url));
      debugPrint('[AppRunner] 应用文件已更新，重新加载 WebView');
    } catch (e) {
      debugPrint('[AppRunner] 重载失败: $e');
    } finally {
      _reloadingApp = false;
    }
  }

  Future<void> _notifyDataChanged(int dataRev) async {
    final c = _controller;
    if (c == null || !_useWebView) return;
    try {
      await c.runJavaScript(
        'window.dispatchEvent(new CustomEvent("datakeep:data-changed",'
        '{detail:{dataRev:$dataRev}}));',
      );
    } catch (e) {
      debugPrint('[AppRunner] 通知 data-changed 失败: $e');
    }
  }

  Future<void> _checkRevision() async {
    if (!mounted || _reloadingApp) return;
    try {
      final rev = await _computeRevision(widget.appPath);
      final appRev = rev['appRev'] ?? 0;
      final dataRev = rev['dataRev'] ?? 0;
      if (_lastAppRev == null) {
        _lastAppRev = appRev;
        _lastDataRev = dataRev;
        return;
      }
      if (appRev != _lastAppRev) {
        _lastAppRev = appRev;
        _lastDataRev = dataRev;
        if (_useWebView) {
          await _reloadWebViewForAppUpdate();
        }
        return;
      }
      if (dataRev != _lastDataRev) {
        _lastDataRev = dataRev;
        final local = _localDataWriteAt;
        if (local != null &&
            DateTime.now().difference(local) < const Duration(seconds: 3)) {
          // 本机刚写入，避免立刻又触发读盘冲掉未完成的编辑
          return;
        }
        await _notifyDataChanged(dataRev);
      }
    } catch (e) {
      debugPrint('[AppRunner] revision 检查失败: $e');
    }
  }

  void _startRevisionWatch() {
    _revTimer?.cancel();
    _revTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkRevision()),
    );
    unawaited(_checkRevision());
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

      await _ensureSyncIgnore(widget.appPath);

      final handler = _buildHandler(widget.appPath, entryRel);
      final preferred = _stablePortFor(widget.appPath);
      try {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          preferred,
        );
      } catch (_) {
        _server = await shelf_io.serve(
          handler,
          InternetAddress.loopbackIPv4,
          0,
        );
      }
      final url = 'http://127.0.0.1:${_server!.port}/$entryRel';
      _entryRel = entryRel;
      final canWebView = !kIsWeb &&
          (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

      if (canWebView) {
        final c = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onWebResourceError: (err) {
                if (!mounted) return;
                setState(() {
                  _webError =
                      '页面加载失败（${err.errorCode}）：${err.description}\n$url';
                });
              },
              onPageFinished: (_) {
                if (!mounted) return;
                if (_webError != null) setState(() => _webError = null);
              },
            ),
          )
          ..loadRequest(Uri.parse(url));
        setState(() {
          _url = url;
          _controller = c;
          _useWebView = true;
          _webError = null;
        });
      } else {
        setState(() => _url = url);
        await _openBrowser(url);
      }
      _startRevisionWatch();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _revTimer?.cancel();
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
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : _webError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_webError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() => _webError = null);
                            unawaited(_reloadWebViewForAppUpdate());
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
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
