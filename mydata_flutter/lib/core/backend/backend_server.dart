import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'cert_manager.dart';
import 'syncthing_api.dart';

class BackendServer {
  final SyncthingApi _api = SyncthingApi();
  late CertManager _certMgr;
  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<void> start({int port = 8443}) async {
    if (_server != null) return;
    _api.init();

    final dataDir = Platform.environment['MYDATA_DATA_DIR'] ?? '.';
    _certMgr = CertManager('$dataDir/certs');

    final router = Router()
      ..get('/api/devices', _handleDevices)
      ..get('/api/device/<deviceId>/folders', _handleDeviceFolders)
      ..get('/api/deviceid', _handleDeviceId)
      ..get('/api/folder/<folderId>', _handleFolderFiles)
      ..get('/api/folder/<folderId>/preview', _handleFilePreview)
      ..get('/api/wifi', _handleWifiInfo)
      ..get('/api/wifi-info', _handleWifiInfo)
      ..post('/api/folder/<folderId>/sharing', _handleSharing)
      ..get('/api/syncthing/events', _handleSyncthingEvents)
      ..get('/api/syncthing/discovery', _handleSyncthingDiscovery)
      ..get('/api/syncthing/deviceid', _handleSyncthingDeviceId)
      ..post('/api/syncthing/config/devices', _handleSyncthingAddDevice)
      ..get('/health', _handleHealth);

    final handler = Pipeline()
        .addMiddleware(_corsMiddleware())
        .addHandler(router);

    final ctx = _certMgr.createSecurityContext();
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port,
        securityContext: ctx);
    _server!.autoCompress = true;
    debugPrint('Backend HTTPS 服务器已启动: https://0.0.0.0:$port');
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware _corsMiddleware() {
    return (Handler innerHandler) => (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(null, headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': '*',
          'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        });
      }
      final response = await innerHandler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        if (!response.headers.containsKey('Access-Control-Allow-Headers'))
          'Access-Control-Allow-Headers': '*',
        if (!response.headers.containsKey('Access-Control-Allow-Methods'))
          'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      });
    };
  }

  Map<String, dynamic> _localDevice() => {
    'deviceID': 'local', 'name': '本机设备', 'addresses': [],
    'connected': true, 'connectionType': 'local', 'clientVersion': 'local',
    'inBytesTotal': 0, 'outBytesTotal': 0, 'isLocalNetwork': true, 'crypto': 'local',
  };

  Response _json(dynamic data, {int status = 200}) =>
      Response(status, body: json.encode(data),
          headers: {'Content-Type': 'application/json'});

  // ─── Handlers ─────────────────────────────────────────────

  Future<Response> _handleDevices(Request request) async {
    final result = await _api.proxyGet('/rest/config/devices');
    final devices = <Map<String, dynamic>>[];

    if (result.containsKey('error') || result.isEmpty) {
      devices.addAll(_configDevices());
    } else if (result['data'] is List) {
      for (final d in result['data'] as List) {
        if (d is Map) devices.add(Map<String, dynamic>.from(d));
      }
    }
    devices.insert(0, _localDevice());
    return _json({'code': 0, 'data': devices});
  }

  List<Map<String, dynamic>> _configDevices() {
    try {
      final xml = File(_api.configPath).readAsStringSync();
      final reg = RegExp(r'<device\s+id="(.*?)"\s+name="(.*?)"');
      return reg.allMatches(xml).map<Map<String, dynamic>>((m) => <String, dynamic>{
        'deviceID': m.group(1) ?? '',
        'name': m.group(2) ?? m.group(1) ?? '',
        'addresses': <String>[],
        'connected': false,
        'isLocalNetwork': false,
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Response> _handleDeviceFolders(Request request, String deviceId) async {
    if (deviceId == 'local') {
      final result = await _api.proxyGet('/rest/config/folders');
      if (result.containsKey('error') || result.isEmpty) {
        final folders = _api.getFoldersFromConfig();
        return _json({'code': 0, 'data': folders});
      }
      final folders = (result['data'] as List?)?.map((f) => {
        'id': f['id'] ?? '', 'label': f['label'] ?? f['id'] ?? '', 'path': f['path'] ?? '',
      }).toList() ?? [];
      return _json({'code': 0, 'data': folders});
    }
    final result = await _api.proxyGet('/rest/config/folders',
        queryParams: {'device': deviceId});
    return _json({'code': 0, 'data': result['data'] ?? []});
  }

  Future<Response> _handleDeviceId(Request request) async {
    try {
      final xml = File(_api.configPath).readAsStringSync();
      final m = RegExp(r'<device id="(.*?)"').firstMatch(xml);
      return _json({'code': 0, 'data': {'deviceID': m?.group(1) ?? 'local'}});
    } catch (_) {
      return _json({'code': 0, 'data': {'deviceID': 'local'}});
    }
  }

  Future<Response> _handleFolderFiles(Request request, String folderId) async {
    final path = request.url.queryParameters['path'] ?? '';
    final params = <String, String>{'folder': folderId};
    if (path.isNotEmpty) params['path'] = path;
    final result = await _api.proxyGet('/rest/db/browse', queryParams: params);
    if (result.containsKey('error') || result.isEmpty) {
      final folders = _api.getFoldersFromConfig();
      final folder = folders.cast<Map<String, dynamic>?>().firstWhere(
        (f) => f?['id'] == folderId,
        orElse: () => null,
      );
      if (folder != null) {
        final files = _api.browseLocalDirectory(folder['path'] as String, path);
        return _json({'code': 0, 'data': files});
      }
      return _json({'code': 1005, 'data': '文件夹未找到'});
    }
    return _json({'code': 0, 'data': result['data'] ?? []});
  }

  Future<Response> _handleFilePreview(Request request, String folderId) async {
    final path = request.url.queryParameters['path'] ?? '';
    if (path.isEmpty) return Response(400, body: '缺少 path 参数');
    final bytes = await _api.proxyGetRaw('/rest/db/file', queryParams: {
      'folder': folderId, 'file': path,
    });
    if (bytes.isEmpty) return Response(404, body: '文件未找到');
    final ext = path.split('.').last.toLowerCase();
    return Response.ok(bytes, headers: {'Content-Type': _mimeType(ext)});
  }

  String _mimeType(String ext) {
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'svg': return 'image/svg+xml';
      case 'pdf': return 'application/pdf';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'txt': case 'md': case 'json': case 'xml': case 'csv': case 'log':
      case 'html': case 'css': case 'js': case 'dart': case 'py':
        return 'text/plain; charset=utf-8';
      default: return 'application/octet-stream';
    }
  }

  Future<Response> _handleWifiInfo(Request request) async {
    try {
      final result = await Process.run('nmcli', ['-t', '-f', 'SSID', 'dev', 'wifi']);
      if (result.exitCode == 0) {
        final ssid = result.stdout.toString().trim().split('\n').first;
        return _json({'code': 0, 'data': {'wifiName': ssid}});
      }
    } catch (_) {}
    return _json({'code': 0, 'data': {'wifiName': ''}});
  }

  Future<Response> _handleSharing(Request request, String folderId) async =>
      _json({'code': 0, 'data': 'ok'});

  Future<Response> _handleSyncthingEvents(Request request) async {
    final since = request.url.queryParameters['since'] ?? '0';
    final timeout = request.url.queryParameters['timeout'] ?? '60';
    final result = await _api.proxyGet('/rest/events',
        queryParams: {'since': since, 'timeout': timeout});
    if (result.containsKey('error') || result.isEmpty) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    return _json(result);
  }

  Future<Response> _handleSyncthingDiscovery(Request request) async {
    final result = await _api.proxyGet('/rest/system/discovery');
    return _json(result);
  }

  Future<Response> _handleSyncthingDeviceId(Request request) async {
    final id = request.url.queryParameters['id'] ?? '';
    final result = await _api.proxyGet('/rest/svc/deviceid',
        queryParams: {'id': id});
    return _json(result);
  }

  Future<Response> _handleSyncthingAddDevice(Request request) async {
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    final result = await _api.proxyPost('/rest/config/devices', data);
    return _json(result);
  }

  Future<Response> _handleHealth(Request request) async =>
      _json({'status': 'ok', 'service': 'mydata-api'});
}
