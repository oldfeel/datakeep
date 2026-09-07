import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:webview_cef/webview_cef.dart' as cef;
import 'package:webview_flutter/webview_flutter.dart' as wf;

import '../../../core/services/api_service.dart';
import '../../folders/providers/folder_provider.dart';
import '../delete_app.dart';
import '../app_about.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../shared/utils/app_dir.dart';
import '../../../shared/utils/app_manifest.dart';
import '../../../shared/utils/dev_app_source.dart';
import '../../../shared/utils/open_url_external.dart';
import '../../folders/screens/video_preview_screen.dart';

/// 在本地 HTTP 服务上打开应用目录（入口默认 index.html）
///
/// `/__datakeep/data/<rel>`：GET/PUT/DELETE；目录 GET 返回文件列表。
/// `/__datakeep/revision`：`{dataRev,appRev}`（目录内文件最大 mtime，毫秒），供自动刷新。
/// 启动时按 app.json 的 `syncIgnore` 合并写入 `.stignore`。
///
/// Debug（[kDebugMode]）下若仓库 `examples/*/app.json` 存在同 id，静态代码从该源码目录
/// 提供，`data/` 仍用安装目录（见 [resolveDevAppSource]）。
///
/// 对端模式：传入 [peerDeviceId] + [peerFolderId]，经局域网 peer API 拉/写文件。
/// [peerWritable]=true（ACL 同步）时可写 data/；只读则注入拦截并禁止 PUT。
class AppRunnerPage extends StatefulWidget {
  final String appPath;
  final String title;
  final String entry;

  /// 对端设备 ID（非本机时启用 peer 模式）
  final String? peerDeviceId;

  /// 对端/本机同步文件夹 ID（peer 模式必填）
  final String? peerFolderId;

  /// 文件夹内应用根相对路径（如 `todo`；顶层应用为空）
  final String appRelPath;

  /// 对端 ACL 为「同步」时可写；「只读」为 false
  final bool peerWritable;

  /// 已注册的 Syncthing 文件夹 id（本机顶层应用删除用）
  final String? folderId;

  const AppRunnerPage({
    super.key,
    required this.appPath,
    required this.title,
    this.entry = 'index.html',
    this.peerDeviceId,
    this.peerFolderId,
    this.appRelPath = '',
    this.peerWritable = false,
    this.folderId,
  });

  bool get isPeerMode =>
      peerDeviceId != null &&
      peerDeviceId!.isNotEmpty &&
      peerFolderId != null &&
      peerFolderId!.isNotEmpty;

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
  wf.WebViewController? _wfController;
  cef.WebViewController? _cefController;
  bool _useWebView = false;
  bool _useCef = false;
  bool _pulling = false;
  bool _deleting = false;

  Timer? _revTimer;
  int? _lastAppRev;
  int? _lastDataRev;
  DateTime? _localDataWriteAt;
  bool _reloadingApp = false;
  AppManifest? _manifest;

  /// 安装目录（data/、syncIgnore、删除）
  String _installPath = '';

  /// 静态代码根（Debug 直连 examples 时与安装目录不同）
  String _codeRoot = '';

  static bool _cefManagerReady = false;

  /// Linux / Windows：CEF Texture 内嵌；移动端与 macOS：系统 WebView。
  bool get _preferCef =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows);

  bool get _preferPlatformWebView =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

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

  bool get _isPeer => widget.isPeerMode;
  bool get _peerWritable => _isPeer && widget.peerWritable;

  String get _peerDeviceId => widget.peerDeviceId!;
  String get _peerFolderId => widget.peerFolderId!;

  /// 应用根下相对路径 → 同步文件夹内完整相对路径
  String _folderRel(String appRelative) {
    final base = widget.appRelPath.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '');
    final rel = appRelative.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (base.isEmpty) return rel;
    if (rel.isEmpty) return base;
    return '$base/$rel';
  }

  String _guessMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'html':
      case 'htm':
        return 'text/html; charset=utf-8';
      case 'css':
        return 'text/css; charset=utf-8';
      case 'js':
      case 'mjs':
        return 'text/javascript; charset=utf-8';
      case 'wasm':
        return 'application/wasm';
      case 'json':
        return 'application/json; charset=utf-8';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'svg':
        return 'image/svg+xml';
      case 'webp':
        return 'image/webp';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'ogv':
      case 'ogg':
        return 'video/ogg';
      case 'mov':
        return 'video/quicktime';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'ts':
      case 'm2ts':
        return 'video/mp2t';
      default:
        return 'application/octet-stream';
    }
  }

  /// 本地文件流式响应；支持 Range，避免大视频整文件进内存导致 CEF `<video>` 失败
  Future<Response> _serveLocalFile(Request request, File file) async {
    final length = await file.length();
    final mime = _guessMime(file.path);
    final baseHeaders = <String, String>{
      'Content-Type': mime,
      'Accept-Ranges': 'bytes',
      'Cache-Control': 'no-store',
    };

    if (request.method == 'HEAD') {
      return Response.ok(null, headers: {
        ...baseHeaders,
        'Content-Length': '$length',
      });
    }

    final rangeHeader = request.headers['range'];
    if (rangeHeader == null || !rangeHeader.startsWith('bytes=')) {
      return Response.ok(
        file.openRead(),
        headers: {
          ...baseHeaders,
          'Content-Length': '$length',
        },
      );
    }

    final spec = rangeHeader.substring(6).trim();
    // 仅处理单段 bytes=start-end / bytes=start- / bytes=-suffix
    final parts = spec.split(',');
    if (parts.length != 1) {
      return Response(
        416,
        headers: {'Content-Range': 'bytes */$length'},
      );
    }
    final unit = parts.first.trim();
    int start;
    int end;
    if (unit.startsWith('-')) {
      final suffix = int.tryParse(unit.substring(1));
      if (suffix == null || suffix <= 0) {
        return Response(
          416,
          headers: {'Content-Range': 'bytes */$length'},
        );
      }
      start = length - suffix;
      if (start < 0) start = 0;
      end = length - 1;
    } else {
      final se = unit.split('-');
      if (se.isEmpty) {
        return Response(
          416,
          headers: {'Content-Range': 'bytes */$length'},
        );
      }
      start = int.tryParse(se[0]) ?? -1;
      if (start < 0 || start >= length) {
        return Response(
          416,
          headers: {'Content-Range': 'bytes */$length'},
        );
      }
      if (se.length > 1 && se[1].isNotEmpty) {
        end = int.tryParse(se[1]) ?? (length - 1);
      } else {
        end = length - 1;
      }
      if (end >= length) end = length - 1;
      if (end < start) {
        return Response(
          416,
          headers: {'Content-Range': 'bytes */$length'},
        );
      }
    }

    final contentLength = end - start + 1;
    return Response(
      206,
      body: file.openRead(start, end + 1),
      headers: {
        ...baseHeaders,
        'Content-Length': '$contentLength',
        'Content-Range': 'bytes $start-$end/$length',
      },
    );
  }

  Future<Response> _peerFetchResponse(String appRelative) async {
    final folderPath = _folderRel(appRelative);
    if (folderPath.contains('..')) {
      return Response.forbidden('非法路径');
    }
    try {
      final file = await ApiService.fetchFolderFile(
        _peerFolderId,
        folderPath,
        deviceId: _peerDeviceId,
      );
      if (!file.ok) {
        final msg = file.errorBody ?? '对端文件不可用';
        if (file.statusCode == 404) return Response.notFound(msg);
        if (file.statusCode == 503) {
          return Response(503, body: msg.isNotEmpty ? msg : '对端离线或不可达');
        }
        return Response(file.statusCode, body: msg);
      }
      var ct = file.contentType;
      if (ct.contains('octet-stream') || ct.contains('text/plain')) {
        ct = _guessMime(appRelative);
      }
      var body = file.body;
      if (_isHtmlPath(appRelative) && !_peerWritable) {
        body = _injectReadonlyHtml(body);
        ct = 'text/html; charset=utf-8';
      }
      return Response.ok(
        body,
        headers: {
          'Content-Type': ct,
          'Cache-Control': 'no-store',
        },
      );
    } catch (e) {
      return Response(
        503,
        body: '对端不可达：$e（需同网且对端已打开数据管理）',
      );
    }
  }

  bool _isHtmlPath(String rel) {
    final lower = rel.toLowerCase();
    return lower.endsWith('.html') || lower.endsWith('.htm');
  }

  /// 注入只读拦截：不发起 PUT/DELETE，避免 CEF 对未排空请求异常；兼容旧版 db.js
  Uint8List _injectReadonlyHtml(Uint8List body) {
    final s = utf8.decode(body, allowMalformed: true);
    if (s.contains('__DATAKEEP_READONLY')) return body;
    const flag = '''
<script>
window.__DATAKEEP_READONLY=true;
(function(){
  var orig=window.fetch;
  if(typeof orig!=="function")return;
  window.fetch=function(input,init){
    init=init||{};
    var method=String(init.method||"GET").toUpperCase();
    var url=typeof input==="string"?input:(input&&input.url)||"";
    if((method==="PUT"||method==="DELETE")&&String(url).indexOf("/__datakeep/data")===0){
      return Promise.resolve(new Response(JSON.stringify({ok:false,readonly:true,error:"对端只读"}),{
        status:403,
        headers:{"Content-Type":"application/json"}
      }));
    }
    return orig.apply(this,arguments);
  };
})();
</script>''';
    final lower = s.toLowerCase();
    final head = lower.indexOf('<head');
    if (head >= 0) {
      final gt = s.indexOf('>', head);
      if (gt >= 0) {
        return Uint8List.fromList(
          utf8.encode('${s.substring(0, gt + 1)}$flag${s.substring(gt + 1)}'),
        );
      }
    }
    return Uint8List.fromList(utf8.encode('$flag$s'));
  }

  Handler _buildPeerHandler(String entryRel) {
    return (Request request) async {
      final path = request.requestedUri.path;
      if (path == '/__datakeep/revision') {
        if (request.method != 'GET') {
          return Response(405, body: '仅支持 GET');
        }
        // 对端只读：不做自动刷新
        return _revisionResponse({'dataRev': 0, 'appRev': 0});
      }
      if (path.startsWith('/__datakeep/data/') || path == '/__datakeep/data') {
        if (request.method != 'GET') {
          if (!_peerWritable) {
            // 必须排空 body，否则 CEF/浏览器对未读完的 PUT 可能异常退出
            try {
              await request.read().drain<void>();
            } catch (_) {}
            return Response(
              403,
              body: jsonEncode({
                'ok': false,
                'readonly': true,
                'error': '对端应用为只读，无法写入 data/',
              }),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
            );
          }
          var rel = path == '/__datakeep/data'
              ? ''
              : path.substring('/__datakeep/data/'.length);
          try {
            rel = Uri.decodeComponent(rel);
          } catch (_) {}
          while (rel.endsWith('/')) {
            rel = rel.substring(0, rel.length - 1);
          }
          if (rel.isEmpty || rel.contains('..')) {
            try {
              await request.read().drain<void>();
            } catch (_) {}
            return Response.forbidden('非法路径');
          }
          final dataRel = 'data/$rel';
          final folderPath = _folderRel(dataRel);
          try {
            if (request.method == 'PUT') {
              final bytes = await request.read().fold<BytesBuilder>(
                BytesBuilder(copy: false),
                (b, chunk) {
                  b.add(chunk);
                  return b;
                },
              );
              await ApiService.putFolderFile(
                _peerFolderId,
                folderPath,
                bytes.takeBytes(),
                deviceId: _peerDeviceId,
              );
              return Response.ok(
                '{"ok":true}',
                headers: {'Content-Type': 'application/json; charset=utf-8'},
              );
            }
            if (request.method == 'DELETE') {
              await ApiService.deleteFolderFile(
                _peerFolderId,
                folderPath,
                deviceId: _peerDeviceId,
              );
              return Response.ok(
                '{"ok":true}',
                headers: {'Content-Type': 'application/json; charset=utf-8'},
              );
            }
            try {
              await request.read().drain<void>();
            } catch (_) {}
            return Response(405, body: '仅支持 GET/PUT/DELETE');
          } catch (e) {
            return Response(503, body: '对端写入失败: $e');
          }
        }
        var rel = path == '/__datakeep/data'
            ? ''
            : path.substring('/__datakeep/data/'.length);
        try {
          rel = Uri.decodeComponent(rel);
        } catch (_) {}
        while (rel.endsWith('/')) {
          rel = rel.substring(0, rel.length - 1);
        }
        if (rel.contains('..')) return Response.forbidden('非法路径');

        final dataRel = rel.isEmpty ? 'data' : 'data/$rel';
        // 先当文件
        final asFile = await _peerFetchResponse(dataRel);
        if (asFile.statusCode == 200) return asFile;

        // 再当目录：列一层文件名（供部分应用探测）
        try {
          final entries = await ApiService.getFolderFiles(
            _peerFolderId,
            path: _folderRel(dataRel),
            deviceId: _peerDeviceId,
          );
          final files = <String>[];
          for (final e in entries) {
            final name = e['name']?.toString() ?? '';
            if (name.isEmpty) continue;
            final t = e['type'];
            final isDir = t == 'dir' || t == 1 || t == '1' || e['isDir'] == true;
            if (isDir) continue;
            files.add(rel.isEmpty ? name : '$rel/$name');
          }
          files.sort();
          return Response.ok(
            jsonEncode({'files': files}),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Cache-Control': 'no-store',
            },
          );
        } catch (_) {
          return asFile;
        }
      }

      var rel = path;
      if (rel.startsWith('/')) rel = rel.substring(1);
      try {
        rel = Uri.decodeComponent(rel);
      } catch (_) {}
      if (rel.isEmpty || rel.endsWith('/')) {
        rel = entryRel;
      }
      if (rel.contains('..')) return Response.forbidden('非法路径');
      return _peerFetchResponse(rel);
    };
  }

  Future<String> _resolvePeerEntry() async {
    var entryRel = widget.entry;
    try {
      final meta = await ApiService.fetchFolderFile(
        _peerFolderId,
        _folderRel('app.json'),
        deviceId: _peerDeviceId,
      );
      if (meta.ok) {
        final m = json.decode(utf8.decode(meta.body));
        if (m is Map && m['entry'] != null) {
          entryRel = m['entry'].toString();
        }
      }
    } catch (_) {}

    if (await ApiService.folderFileExists(
      _peerFolderId,
      _folderRel(entryRel),
      deviceId: _peerDeviceId,
    )) {
      return entryRel;
    }
    if (entryRel != 'index.html' &&
        await ApiService.folderFileExists(
          _peerFolderId,
          _folderRel('index.html'),
          deviceId: _peerDeviceId,
        )) {
      return 'index.html';
    }
    throw Exception('缺少入口文件（$entryRel / index.html），或对端离线');
  }

  Future<void> _serveAndOpen(Handler handler, String entryRel, String portKey) async {
    final preferred = _stablePortFor(portKey);
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

    if (_preferCef) {
      final ok = await _startCefWebView(url);
      if (!ok) {
        // 不自动打开系统浏览器：Clash 等代理常把 127.0.0.1 代理掉导致空白页；
        // CEF 多实例冲突时也会失败。留在应用内展示地址，由用户点「浏览器打开」。
        setState(() {
          _url = url;
          _openHint =
              '内嵌页面启动失败（常见原因：同时开了多个 DataKeep，或本机代理干扰 localhost）。'
              '可点右上角「浏览器打开」；若仍空白，请关掉多余进程，或给浏览器设置 bypass 127.0.0.1。';
        });
      }
    } else if (_preferPlatformWebView) {
      await _startPlatformWebView(url);
    } else {
      setState(() => _url = url);
      await _openBrowser(url);
    }
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
      // 不把宿主暂存目录暴露给应用扫描（直接按路径 GET 仍可用）
      if (rel == '.staging' || rel.startsWith('.staging/')) continue;
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

  /// dataRev = 安装目录 data/ 最大 mtime；appRev = 代码根非 data/ 最大 mtime。
  Future<Map<String, int>> _computeRevision({
    required String codeRoot,
    required String installPath,
  }) async {
    var dataRev = 0;
    var appRev = 0;

    final codeDataRoot = p.normalize(p.join(codeRoot, 'data'));
    final codeDir = Directory(codeRoot);
    if (await codeDir.exists()) {
      await for (final entity
          in codeDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          final m = (await entity.stat()).modified.millisecondsSinceEpoch;
          final inData = p.isWithin(codeDataRoot, entity.path) ||
              p.equals(codeDataRoot, entity.path);
          if (!inData && m > appRev) appRev = m;
        } catch (_) {}
      }
    }

    final dataRoot = p.normalize(p.join(installPath, 'data'));
    final dataDir = Directory(dataRoot);
    if (await dataDir.exists()) {
      await for (final entity
          in dataDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          // 暂存与封面画廊临时帧不计入 dataRev，避免选封面时整页刷新
          if (_ignorePathForDataRev(dataRoot, entity.path)) continue;
          final m = (await entity.stat()).modified.millisecondsSinceEpoch;
          if (m > dataRev) dataRev = m;
        } catch (_) {}
      }
    }
    return {'dataRev': dataRev, 'appRev': appRev};
  }

  /// `.staging/`、任意 `covers/` 下的临时截帧不参与同步刷新判定
  bool _ignorePathForDataRev(String dataRoot, String filePath) {
    final rel = p
        .normalize(p.relative(filePath, from: dataRoot))
        .replaceAll('\\', '/');
    if (rel == '.staging' || rel.startsWith('.staging/')) return true;
    if (rel == 'covers' || rel.startsWith('covers/')) return true;
    if (rel.contains('/covers/')) return true;
    return false;
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

  Handler _buildHandler(
    String codeRoot,
    String installPath,
    String entryRel,
  ) {
    final staticHandler = _withNoStore(
      createStaticHandler(
        codeRoot,
        defaultDocument: entryRel,
        listDirectories: false,
      ),
    );
    final dataRoot = p.normalize(p.join(installPath, 'data'));

    return (Request request) async {
      final path = request.requestedUri.path;
      if (path == '/__datakeep/revision') {
        if (request.method != 'GET') {
          return Response(405, body: '仅支持 GET');
        }
        final rev = await _computeRevision(
          codeRoot: codeRoot,
          installPath: installPath,
        );
        return _revisionResponse(rev);
      }
      if (path.startsWith('/__datakeep/data/') || path == '/__datakeep/data') {
        final normalized =
            path == '/__datakeep/data' ? '/__datakeep/data/' : path;
        final full = _resolveDataPath(installPath, normalized, allowRoot: true);
        if (full == null) {
          return Response.forbidden('非法路径');
        }
        if (request.method == 'GET' || request.method == 'HEAD') {
          final asDir = Directory(full);
          if (await asDir.exists()) {
            if (request.method == 'HEAD') {
              return Response.ok(null, headers: {
                'Content-Type': 'application/json; charset=utf-8',
                'Cache-Control': 'no-store',
              });
            }
            return _listDataFiles(dataRoot, full);
          }
          final f = File(full);
          if (!await f.exists()) {
            return Response.notFound('不存在');
          }
          return _serveLocalFile(request, f);
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
        return Response(405, body: '仅支持 GET/HEAD/PUT/DELETE');
      }
      return staticHandler(request);
    };
  }

  Future<bool> _ensureCefManager() async {
    if (_cefManagerReady) return true;
    try {
      await cef.WebviewManager().initialize(userAgent: 'DataKeep-AppRunner');
      _cefManagerReady = true;
      return true;
    } catch (e) {
      _cefManagerReady = false;
      debugPrint('[AppRunner] CEF 初始化失败: $e');
      return false;
    }
  }

  Future<void> _reloadWebViewForAppUpdate() async {
    final entry = _entryRel;
    if (entry == null || _server == null || !_useWebView) return;
    _reloadingApp = true;
    try {
      final url =
          'http://127.0.0.1:${_server!.port}/$entry?_r=${DateTime.now().millisecondsSinceEpoch}';
      _url = url;
      if (_useCef) {
        await _cefController?.loadUrl(url);
      } else {
        await _wfController?.loadRequest(Uri.parse(url));
      }
      debugPrint('[AppRunner] 应用文件已更新，重新加载 WebView');
    } catch (e) {
      debugPrint('[AppRunner] 重载失败: $e');
    } finally {
      _reloadingApp = false;
    }
  }

  Future<void> _notifyDataChanged(int dataRev) async {
    if (!_useWebView) return;
    const js =
        'window.dispatchEvent(new CustomEvent("datakeep:data-changed",'
        '{detail:{dataRev:__REV__}}));';
    final code = js.replaceFirst('__REV__', '$dataRev');
    try {
      if (_useCef) {
        await _cefController?.executeJavaScript(code);
      } else {
        await _wfController?.runJavaScript(code);
      }
    } catch (e) {
      debugPrint('[AppRunner] 通知 data-changed 失败: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showAbout() async {
    final manifest = _manifest ??
        AppManifest.tryReadFromDirectory(
          _codeRoot.isNotEmpty ? _codeRoot : widget.appPath,
        );
    if (manifest == null) {
      _snack('无法读取应用信息（app.json）');
      return;
    }
    if (!mounted) return;
    await showAppAboutDialog(
      context,
      manifest: manifest,
      installPath: _isPeer ? null : widget.appPath,
    );
  }

  /// 触发所属同步文件夹扫描，等待局域网对端同步落盘后对比 revision。
  Future<void> _refreshFromPeers() async {
    if (_isPeer) {
      _snack('对端只读打开，无法从本机触发同步刷新');
      return;
    }
    if (_pulling) return;
    setState(() => _pulling = true);
    try {
      final before = await _computeRevision(
        codeRoot: _codeRoot,
        installPath: _installPath,
      );
      final folders = await ApiService.getFolders();
      final folder = findEnclosingSyncFolder(folders, widget.appPath);
      if (folder == null) {
        _snack('当前应用不在同步文件夹内，无法对比其他设备');
        return;
      }

      await ApiService.scanFolder(folder.id);

      var sawActivity = false;
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final st = await ApiService.getFolderSyncStatus(folder.id);
        final status = st['status']?.toString() ?? '';
        final state = st['state']?.toString() ?? '';
        final needFiles = (st['needFiles'] as num?)?.toInt() ?? 0;
        final busy = status == 'syncing' ||
            state == 'syncing' ||
            state == 'scanning' ||
            state == 'scan-waiting' ||
            needFiles > 0;
        if (busy) {
          sawActivity = true;
          continue;
        }
        if (sawActivity) break;
        // 尚未看到同步活动：多等一会儿，给对端 index 交换时间
        if (DateTime.now()
            .isAfter(deadline.subtract(const Duration(seconds: 10)))) {
          break;
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 400));
      final after = await _computeRevision(
        codeRoot: _codeRoot,
        installPath: _installPath,
      );
      final dataRev = after['dataRev'] ?? 0;
      final appRev = after['appRev'] ?? 0;
      final dataChanged = dataRev != (before['dataRev'] ?? 0);
      final appChanged = appRev != (before['appRev'] ?? 0);
      _lastDataRev = dataRev;
      _lastAppRev = appRev;

      if (appChanged && _useWebView) {
        await _reloadWebViewForAppUpdate();
        _snack('已从其他设备更新应用文件');
      } else if (dataChanged) {
        await _notifyDataChanged(dataRev);
        _snack('已从其他设备拉取到新数据');
      } else {
        // 即使 mtime 未变，也通知一次，便于应用重跑冲突合并等逻辑
        await _notifyDataChanged(dataRev);
        _snack(sawActivity ? '同步已完成，暂无新数据' : '暂无来自其他设备的更新');
      }
    } catch (e) {
      _snack('刷新失败：$e');
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  Future<void> _checkRevision() async {
    if (_isPeer) return;
    if (!mounted || _reloadingApp) return;
    if (_codeRoot.isEmpty || _installPath.isEmpty) return;
    try {
      final rev = await _computeRevision(
        codeRoot: _codeRoot,
        installPath: _installPath,
      );
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
      if (_isPeer) {
        final entryRel = await _resolvePeerEntry();
        final portKey =
            'peer:${_peerDeviceId}:${_peerFolderId}:${widget.appRelPath}';
        await _serveAndOpen(_buildPeerHandler(entryRel), entryRel, portKey);
        // 对端只读：不轮询 revision
        return;
      }

      final installPath = widget.appPath;
      final root = Directory(installPath);
      if (!root.existsSync()) {
        setState(() => _error = '应用目录不存在: $installPath');
        return;
      }

      _installPath = installPath;
      _manifest = AppManifest.tryReadFromDirectory(installPath);
      final appId = _manifest?.id ?? '';
      final codeRoot = resolveDevAppSource(appId) ?? installPath;
      _codeRoot = codeRoot;

      if (codeRoot != installPath) {
        debugPrint('[AppRunner] 开发源码直连: $codeRoot');
        // 优先用源码目录的清单（版本/入口）
        _manifest = AppManifest.tryReadFromDirectory(codeRoot) ?? _manifest;
      }

      var entryRel = widget.entry;
      final meta = File(p.join(codeRoot, 'app.json'));
      if (meta.existsSync()) {
        try {
          final m = json.decode(await meta.readAsString());
          if (m is Map && m['entry'] != null) {
            entryRel = m['entry'].toString();
          }
        } catch (_) {}
      }

      final entryFile = File(p.join(codeRoot, entryRel));
      if (!entryFile.existsSync()) {
        setState(() => _error = '缺少入口文件: $entryRel');
        return;
      }

      await _ensureSyncIgnore(installPath);
      // data/ 可能尚未创建（新装或未放媒体）；列目录 API 需要目录存在
      await Directory(p.join(installPath, 'data')).create(recursive: true);

      await _serveAndOpen(
        _buildHandler(codeRoot, installPath, entryRel),
        entryRel,
        installPath,
      );
      _startRevisionWatch();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _startPlatformWebView(String url) async {
    final c = wf.WebViewController()
      ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        wf.NavigationDelegate(
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
      _wfController = c;
      _useWebView = true;
      _useCef = false;
      _webError = null;
    });
  }

  /// 内嵌 CEF（Chromium Texture）。失败返回 false，由调用方展示地址（不自动外开浏览器）。
  Future<bool> _startCefWebView(String url) async {
    if (!await _ensureCefManager()) return false;
    try {
      final c = cef.WebviewManager().createWebView(
        loading: const Center(child: CircularProgressIndicator()),
      );
      c.setWebviewListener(cef.WebviewEventsListener(
        onLoadEnd: (_, __) {
          if (!mounted) return;
          if (_webError != null) setState(() => _webError = null);
          unawaited(_ensureCefHostBridge(c));
        },
      ));
      await c.initialize(url);
      if (!mounted) {
        await c.dispose();
        return false;
      }
      await _ensureCefHostBridge(c);
      setState(() {
        _url = url;
        _cefController = c;
        _useWebView = true;
        _useCef = true;
        _webError = null;
        _openHint = null;
      });
      return true;
    } catch (e) {
      debugPrint('[AppRunner] CEF WebView 启动失败: $e');
      return false;
    }
  }

  /// CEF 无系统文件对话框：通过 JS 通道 + Flutter FilePicker 选文件并暂存到 data/.staging
  Future<void> _ensureCefHostBridge(cef.WebViewController c) async {
    try {
      await c.setJavaScriptChannels({
        cef.JavascriptChannel(
          name: 'DataKeepHost',
          onMessageReceived: (msg) {
            unawaited(_onDataKeepHostMessage(c, msg));
          },
        ),
      });
      await c.executeJavaScript(_datakeepPickFileHelperJs);
    } catch (e) {
      debugPrint('[AppRunner] 注册 DataKeepHost 失败: $e');
    }
  }

  static const _datakeepPickFileHelperJs = r'''
window.__datakeepPickFile=function(accept){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"pickFile",accept:accept||""},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.cancelled){reject(new Error("cancelled"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
window.__datakeepGenerateCover=function(rel){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"generateCover",rel:rel||""},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
window.__datakeepListCoverFrames=function(rel){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"listCoverFrames",rel:rel||""},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
window.__datakeepPrepareCoverFrames=function(rel){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"prepareCoverFrames",rel:rel||""},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
window.__datakeepExtractCoverFrame=function(rel,sec,index){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"extractCoverFrame",rel:rel||"",sec:sec||0,index:index||0},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
window.__datakeepPlayVideo=function(rel,title){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"playVideo",rel:rel||"",title:title||""},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
window.__datakeepProbeDuration=function(rel){
  return new Promise(function(resolve,reject){
    if(typeof DataKeepHost!=="function"){
      reject(new Error("NO_HOST"));
      return;
    }
    try{
      DataKeepHost({method:"probeDuration",rel:rel||""},function(res){
        try{
          var j=res;
          if(typeof res==="string"){
            try{j=JSON.parse(res);}catch(_){}
          }
          if(!j){reject(new Error("empty"));return;}
          if(j.error){reject(new Error(j.error));return;}
          resolve(j);
        }catch(e){reject(e);}
      });
    }catch(e){reject(e);}
  });
};
''';

  Future<void> _onDataKeepHostMessage(
    cef.WebViewController c,
    cef.JavascriptMessage msg,
  ) async {
    void reply(Map<String, dynamic> payload) {
      unawaited(
        c.sendJavaScriptChannelCallBack(
          false,
          jsonEncode(payload),
          msg.callbackId,
          msg.frameId,
        ),
      );
    }

    try {
      // CEF 通道会对参数再 JSON.stringify：若 JS 已传字符串会双重编码
      dynamic raw = msg.message;
      if (raw is String) {
        raw = json.decode(raw);
        if (raw is String) {
          raw = json.decode(raw);
        }
      }
      if (raw is! Map) {
        debugPrint('[AppRunner] DataKeepHost 无效消息: ${msg.message}');
        reply({'error': 'invalid message'});
        return;
      }
      final method = raw['method']?.toString() ?? '';
      if (_isPeer || _installPath.isEmpty) {
        reply({'error': '当前模式不支持选文件'});
        return;
      }

      if (method == 'pickFile') {
        final accept = raw['accept']?.toString() ?? '';
        final picked = await _pickFileForAccept(accept);
        if (picked == null) {
          reply({'cancelled': true});
          return;
        }
        final staged = await _stagePickedFile(picked);
        if (staged == null) {
          reply({'error': '暂存失败'});
          return;
        }
        reply(staged);
        return;
      }

      if (method == 'generateCover') {
        final rel = raw['rel']?.toString() ?? '';
        final cover = await _generateCoverFromDataRel(rel);
        if (cover == null) {
          reply({
            'error':
                '无法从该视频截取封面（桌面需 ffmpeg）。请改用「选择封面图」。',
          });
          return;
        }
        reply(cover);
        return;
      }

      if (method == 'listCoverFrames') {
        final rel = raw['rel']?.toString() ?? '';
        final gallery = await _listCoverFramesFromDataRel(rel);
        if (gallery == null) {
          reply({
            'error':
                '无法从该视频提取封面候选（桌面需 ffmpeg）。请改用「选择封面图」。',
          });
          return;
        }
        reply(gallery);
        return;
      }

      if (method == 'prepareCoverFrames') {
        final rel = raw['rel']?.toString() ?? '';
        final plan = await _prepareCoverFramesFromDataRel(rel);
        if (plan == null) {
          reply({
            'error':
                '无法准备封面画廊（桌面需 ffmpeg）。请改用「上传封面」。',
          });
          return;
        }
        reply(plan);
        return;
      }

      if (method == 'extractCoverFrame') {
        final rel = raw['rel']?.toString() ?? '';
        final sec = (raw['sec'] is num)
            ? (raw['sec'] as num).toDouble()
            : double.tryParse('${raw['sec']}') ?? 0;
        final index = (raw['index'] is num)
            ? (raw['index'] as num).toInt()
            : int.tryParse('${raw['index']}') ?? 0;
        final frame = await _extractCoverFrameFromDataRel(rel, sec, index);
        if (frame == null) {
          reply({'error': '截取该帧失败'});
          return;
        }
        reply(frame);
        return;
      }

      if (method == 'playVideo') {
        final rel = raw['rel']?.toString() ?? '';
        final titleRaw = raw['title']?.toString() ?? '';
        final cleaned =
            rel.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
        if (cleaned.isEmpty || cleaned.contains('..')) {
          reply({'error': '非法路径'});
          return;
        }
        final file = File(p.join(_installPath, 'data', cleaned));
        if (!await file.exists()) {
          reply({'error': '文件不存在'});
          return;
        }
        final title =
            titleRaw.trim().isNotEmpty ? titleRaw.trim() : p.basename(cleaned);
        // 先回 OK，再打开与文件浏览相同的 media_kit 全屏页
        reply({'ok': true, 'path': file.path});
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPreviewScreen(
              title: title,
              filePath: file.path,
            ),
          ),
        );
        return;
      }

      if (method == 'probeDuration') {
        final rel = raw['rel']?.toString() ?? '';
        final cleaned =
            rel.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
        if (cleaned.isEmpty || cleaned.contains('..')) {
          reply({'error': '非法路径'});
          return;
        }
        final file = File(p.join(_installPath, 'data', cleaned));
        if (!await file.exists()) {
          reply({'error': '文件不存在'});
          return;
        }
        final sec =
            await ThumbnailService.instance.probeDurationSeconds(file.path);
        if (sec == null || !sec.isFinite || sec <= 0) {
          reply({'error': '无法探测时长'});
          return;
        }
        reply({'ok': true, 'duration': sec});
        return;
      }

      reply({'error': 'unknown method'});
    } catch (e) {
      debugPrint('[AppRunner] DataKeepHost: $e');
      reply({'error': '$e'});
    }
  }

  /// 从 data/ 下已暂存视频截帧，写出同目录 cover_gen.jpg（CEF 无法播 mkv 等格式）
  Future<Map<String, dynamic>?> _generateCoverFromDataRel(String rel) async {
    final cleaned = rel.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (cleaned.isEmpty || cleaned.contains('..')) return null;
    final video = File(p.join(_installPath, 'data', cleaned));
    if (!await video.exists()) return null;

    final parentRel = p.posix.dirname(cleaned);
    final outRel =
        parentRel == '.' ? 'cover_gen.jpg' : '$parentRel/cover_gen.jpg';
    final out = File(p.join(_installPath, 'data', outRel));

    // 多点取样跳过片头黑场（桌面 ffmpeg；失败再 video_thumbnail）
    try {
      final path = await ThumbnailService.instance.extractVideoCover(
        videoPath: video.path,
        outputPath: out.path,
        maxWidth: 640,
      );
      if (path != null && await out.exists() && await out.length() > 0) {
        return {
          'rel': outRel,
          'name': 'cover_gen.jpg',
          'mime': 'image/jpeg',
          'size': await out.length(),
        };
      }
    } catch (e) {
      debugPrint('[AppRunner] 封面截帧失败: $e');
    }
    return null;
  }

  /// 封面画廊：均匀抽帧到同目录 covers/，返回相对 data 的路径列表
  Future<Map<String, dynamic>?> _listCoverFramesFromDataRel(String rel) async {
    final cleaned = rel.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (cleaned.isEmpty || cleaned.contains('..')) return null;
    final video = File(p.join(_installPath, 'data', cleaned));
    if (!await video.exists()) return null;

    final parentRel = p.posix.dirname(cleaned);
    final coversRel =
        parentRel == '.' ? 'covers' : '$parentRel/covers';
    final coversDir = p.join(_installPath, 'data', coversRel);

    try {
      final frames = await ThumbnailService.instance.extractVideoCoverCandidates(
        videoPath: video.path,
        outputDir: coversDir,
        maxWidth: 480,
        maxFrames: 20,
      );
      if (frames.isEmpty) return null;
      return {
        'frames': [
          for (final f in frames)
            {
              'rel': '$coversRel/${p.basename(f.path)}',
              'sec': f.sec,
              'luma': f.luma,
              'recommended': f.recommended,
            },
        ],
      };
    } catch (e) {
      debugPrint('[AppRunner] 封面画廊失败: $e');
      return null;
    }
  }

  /// 准备画廊目录 + 取样时间点（不截帧，供前端逐帧拉取）
  Future<Map<String, dynamic>?> _prepareCoverFramesFromDataRel(String rel) async {
    final cleaned = rel.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (cleaned.isEmpty || cleaned.contains('..')) return null;
    final video = File(p.join(_installPath, 'data', cleaned));
    if (!await video.exists()) return null;

    final parentRel = p.posix.dirname(cleaned);
    final coversRel = parentRel == '.' ? 'covers' : '$parentRel/covers';
    final coversDir = p.join(_installPath, 'data', coversRel);

    try {
      final prepared = await ThumbnailService.instance.prepareCoverGallery(
        videoPath: video.path,
        outputDir: coversDir,
        maxFrames: 20,
      );
      return {
        'coversRel': coversRel,
        'duration': prepared.duration,
        'seeks': prepared.seeks,
      };
    } catch (e) {
      debugPrint('[AppRunner] 准备封面画廊失败: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _extractCoverFrameFromDataRel(
    String rel,
    double sec,
    int index,
  ) async {
    final cleaned = rel.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (cleaned.isEmpty || cleaned.contains('..')) return null;
    final video = File(p.join(_installPath, 'data', cleaned));
    if (!await video.exists()) return null;

    final parentRel = p.posix.dirname(cleaned);
    final coversRel = parentRel == '.' ? 'covers' : '$parentRel/covers';
    final name = 'f_${index.toString().padLeft(3, '0')}.jpg';
    final outRel = '$coversRel/$name';
    final outPath = p.join(_installPath, 'data', outRel);

    try {
      final frame = await ThumbnailService.instance.extractSingleCoverFrame(
        videoPath: video.path,
        outputPath: outPath,
        sec: sec,
        maxWidth: 480,
      );
      if (frame == null) return null;
      return {
        'rel': outRel,
        'sec': frame.sec,
        'luma': frame.luma,
        'index': index,
      };
    } catch (e) {
      debugPrint('[AppRunner] 单帧封面失败: $e');
      return null;
    }
  }

  Future<PlatformFile?> _pickFileForAccept(String accept) async {
    final a = accept.toLowerCase();
    FileType type = FileType.any;
    List<String>? exts;
    if (a.contains('video')) {
      type = FileType.custom;
      exts = const ['mp4', 'webm', 'mkv', 'mov', 'm4v', 'avi', 'ogv', 'mpeg', 'mpg'];
    } else if (a.contains('image')) {
      type = FileType.custom;
      exts = const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
    }
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: exts,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  /// 复制到 installPath/data/.staging/<id>/<name>，返回相对 data 的路径信息
  Future<Map<String, dynamic>?> _stagePickedFile(PlatformFile picked) async {
    final srcPath = picked.path;
    if (srcPath == null || srcPath.isEmpty) return null;
    final src = File(srcPath);
    if (!await src.exists()) return null;

    var name = picked.name.trim();
    if (name.isEmpty) name = p.basename(srcPath);
    name = name.replaceAll(RegExp(r'[/\\]'), '_');
    if (name.isEmpty || name == '.' || name == '..') {
      name = 'file';
    }

    final id =
        '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    final relDir = '.staging/$id';
    final rel = '$relDir/$name';
    final dest = File(p.join(_installPath, 'data', relDir, name));
    await dest.parent.create(recursive: true);
    await src.copy(dest.path);

    String? mime;
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4')) {
      mime = 'video/mp4';
    } else if (lower.endsWith('.webm')) {
      mime = 'video/webm';
    } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      mime = 'image/jpeg';
    } else if (lower.endsWith('.png')) {
      mime = 'image/png';
    }

    return {
      'rel': rel,
      'name': name,
      'size': await dest.length(),
      if (mime != null) 'mime': mime,
    };
  }

  Future<void> _deleteApp() async {
    if (_isPeer || widget.appPath.isEmpty || _deleting) return;
    final ok = await confirmDeleteApp(context, widget.title);
    if (!ok || !mounted) return;

    final folderProvider = context.read<FolderProvider>();
    setState(() => _deleting = true);
    _revTimer?.cancel();
    await _server?.close(force: true);
    _server = null;

    try {
      await deleteAppInstallation(
        folderProvider,
        appPath: widget.appPath,
        folderId: widget.folderId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除「${widget.title}」')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
      setState(() => _deleting = false);
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    _revTimer?.cancel();
    unawaited(_server?.close(force: true) ?? Future.value());
    final cefCtrl = _cefController;
    _cefController = null;
    if (cefCtrl != null) {
      unawaited(cefCtrl.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_manifest?.displayName(fallback: widget.title) ?? widget.title),
            if (_isPeer)
              Text(
                _peerWritable ? '对端同步（可写）' : '对端只读',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.7),
                    ),
              ),
          ],
        ),
        actions: [
          if (!_isPeer && widget.appPath.isNotEmpty)
            IconButton(
              tooltip: '关于',
              onPressed: _showAbout,
              icon: const Icon(Icons.info_outline),
            ),
          if (!_isPeer && widget.appPath.isNotEmpty)
            IconButton(
              tooltip: '删除应用',
              onPressed: _deleting ? null : () => unawaited(_deleteApp()),
              icon: _deleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
            ),
          if (_url != null && !_isPeer)
            IconButton(
              tooltip: _pulling ? '正在对比其他设备…' : '刷新：对比其他设备数据',
              onPressed: _pulling ? null : () => unawaited(_refreshFromPeers()),
              icon: _pulling
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
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
          : _useWebView && _useCef && _cefController != null
              ? ValueListenableBuilder<bool>(
                  valueListenable: _cefController!,
                  builder: (context, ready, _) {
                    return ready
                        ? _cefController!.webviewWidget
                        : _cefController!.loadingWidget;
                  },
                )
              : _useWebView && _wfController != null
                  ? wf.WebViewWidget(controller: _wfController!)
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

