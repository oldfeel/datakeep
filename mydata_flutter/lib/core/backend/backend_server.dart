import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'cert_manager.dart';
import 'syncthing_api.dart';

class BackendServer {
  final SyncthingApi _api = SyncthingApi();
  late CertManager _certMgr;
  HttpServer? _server;
  String? _defaultLocalDeviceName;

  bool get isRunning => _server != null;

  Future<void> start({int port = 8443, String? syncthingConfigPath, String? defaultLocalDeviceName}) async {
    if (_server != null) return;
    _defaultLocalDeviceName = defaultLocalDeviceName;
    _api.init(configPath: syncthingConfigPath, defaultLocalDeviceName: defaultLocalDeviceName);

    final dataDir = await _resolveDataDir();
    _certMgr = CertManager('$dataDir/certs');
    await _certMgr.ensureReady();

    final router = Router()
      ..get('/api/devices', _handleDevices)
      ..get('/api/device/<deviceId>/folders', _handleDeviceFolders)
      ..post('/api/device/local/folders', _handleCreateFolder)
      ..delete('/api/device/<deviceId>/folders/<folderId>', _handleDeleteFolder)
      ..delete('/api/device/<deviceId>', _handleRemoveDevice)
      ..get('/api/deviceid', _handleDeviceId)
      ..get('/api/folder/<folderId>', _handleFolderFiles)
      ..get('/api/folder/<folderId>/preview', _handleFilePreview)
      ..get('/api/wifi', _handleWifiInfo)
      ..get('/api/wifi-info', _handleWifiInfo)
      ..post('/api/folder/<folderId>/sharing', _handleSharing)
      ..get('/api/syncthing/events', _handleSyncthingEvents)
      ..get('/api/syncthing/discovery', _handleSyncthingDiscovery)
      ..get('/api/syncthing/cluster/pending/devices', _handlePendingDevices)
      ..delete('/api/syncthing/cluster/pending/devices', _handleDismissPendingDevice)
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

  Future<String> _resolveDataDir() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return (await getApplicationSupportDirectory()).path;
    }
    return Platform.environment['MYDATA_DATA_DIR'] ?? '.';
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

  Map<String, dynamic> _localDevice({String? id, String? name}) => {
    'deviceID': id ?? 'local',
    'name': name ?? '本机设备',
    'addresses': [],
    'connected': true,
    'connectionType': 'local',
    'clientVersion': 'local',
    'inBytesTotal': 0,
    'outBytesTotal': 0,
    'isLocalNetwork': true,
    'crypto': 'local',
  };

  Future<bool> _isLocalDeviceId(String deviceId) async {
    if (deviceId == 'local') return true;
    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) return false;
    final norm = (String id) => id.replaceAll(RegExp(r'[\s-]'), '');
    return norm(localId) == norm(deviceId);
  }

  Response _json(dynamic data, {int status = 200}) =>
      Response(status, body: json.encode(data),
          headers: {'Content-Type': 'application/json'});

  // ─── Handlers ─────────────────────────────────────────────

  Future<Response> _handleDevices(Request request) async {
    final localId = await _api.getLocalDeviceId();

    // Syncthing 运行中若 config 仍是 localhost，通过 API 写入手机型号
    if (localId != null &&
        _defaultLocalDeviceName != null &&
        _defaultLocalDeviceName!.isNotEmpty) {
      final configName = _api.getDeviceNameFromConfig(localId) ?? '';
      if (SyncthingApi.isPlaceholderName(configName, localId)) {
        debugPrint('[devices] config 名仍为占位符 "$configName"，尝试写入 $_defaultLocalDeviceName');
        await _api.ensureLocalDeviceName(_defaultLocalDeviceName!);
      }
    }

    final localName = localId != null ? _api.getLocalDeviceName(localId) : '本机设备';
    debugPrint('[devices] localId=$localId, localName=$localName, config=${_api.configPath}');

    final result = await _api.proxyGet('/rest/config/devices');
    final devices = <Map<String, dynamic>>[];

    if (result.containsKey('error') || result.isEmpty) {
      debugPrint('[devices] REST /config/devices 不可用，回退解析 config.xml');
      devices.addAll(_configDevices());
    } else if (result['data'] is List) {
      for (final d in result['data'] as List) {
        if (d is Map) devices.add(Map<String, dynamic>.from(d));
      }
    }

    for (final d in devices) {
      debugPrint('[devices] 原始: id=${d['deviceID']}, name=${d['name']}');
    }

    await _api.enrichDevicesWithConnections(devices);
    await _api.normalizeDeviceNames(devices);

    for (final d in devices) {
      debugPrint('[devices] 归一化后: id=${d['deviceID']}, name=${d['name']}');
    }

    // 去掉与本机 ID 重复的远程设备条目（忽略连字符差异）
    if (localId != null && localId.isNotEmpty) {
      final localNorm = SyncthingApi.formatDeviceId(localId)
          .replaceAll(RegExp(r'[\s-]'), '')
          .toUpperCase();
      devices.removeWhere((d) {
        final id = d['deviceID']?.toString() ?? '';
        return id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase() == localNorm;
      });
    }

    devices.insert(0, _localDevice(id: localId, name: localName));
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
    if (await _isLocalDeviceId(deviceId)) {
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
    final localId = await _api.getLocalDeviceId();
    return _json({'code': 0, 'data': {'deviceID': localId ?? 'local'}});
  }

  Future<Response> _handleFolderFiles(Request request, String folderId) async {
    final path = request.url.queryParameters['path'] ?? '';
    // 从 config.xml 获取文件夹真实路径
    final folders = _api.getFoldersFromConfig();
    final folderCfg = folders.cast<Map<String, dynamic>?>().firstWhere(
      (f) => f?['id'] == folderId, orElse: () => null,
    );
    if (folderCfg == null) {
      return _json({'code': 1005, 'data': '文件夹未找到'});
    }
    final files = _api.browseLocalDirectory(folderCfg['path'] as String, path);
    return _json({'code': 0, 'data': files});
  }

  Future<Response> _handleFilePreview(Request request, String folderId) async {
    final filePath = request.url.queryParameters['path'] ?? '';
    if (filePath.isEmpty) return Response(400, body: '缺少 path 参数');
    // 从 config.xml 获取文件夹真实路径，直接读本地文件
    final folders = _api.getFoldersFromConfig();
    final folderCfg = folders.cast<Map<String, dynamic>?>().firstWhere(
      (f) => f?['id'] == folderId, orElse: () => null,
    );
    if (folderCfg == null) return Response(404, body: '文件夹未找到');
    final fullPath = '${folderCfg['path']}/$filePath';
    final file = File(fullPath);
    if (!file.existsSync()) return Response(404, body: '文件未找到');
    final bytes = await file.readAsBytes();
    final ext = filePath.split('.').last.toLowerCase();
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

  Future<Response> _handleSharing(Request request, String folderId) async {
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    var sharedDevices = (data['sharedDevices'] as List?)?.cast<String>() ?? [];

    // 自动加入本机设备
    final localId = await _api.getLocalDeviceId();
    if (localId != null && !sharedDevices.contains(localId)) {
      sharedDevices = [localId, ...sharedDevices];
    }

    // 获取当前文件夹配置
    final folder = await _api.proxyGet('/rest/config/folders/$folderId');
    if (folder.containsKey('error')) {
      return _json({'code': 1004, 'data': '文件夹不存在'}, status: 404);
    }
    // 更新 devices 列表
    folder['devices'] = sharedDevices.map((id) => <String, dynamic>{
      'deviceID': id, 'introducedBy': '',
    }).toList();
    final result = await _api.proxyPut('/rest/config/folders/$folderId', folder);
    if (result.containsKey('error')) {
      return _json({'code': 1005, 'data': '保存失败: ${result['error']}'}, status: 500);
    }
    return _json({'code': 0, 'data': {'message': '共享设置已更新'}});
  }

  Future<Response> _handleSyncthingEvents(Request request) async {
    final since = request.url.queryParameters['since'] ?? '0';
    final timeout = request.url.queryParameters['timeout'] ?? '60';
    final timeoutSec = int.tryParse(timeout) ?? 60;
    final result = await _api.proxyGet('/rest/events',
        queryParams: {'since': since, 'timeout': timeout},
        timeout: Duration(seconds: timeoutSec + 15),
        silent: true);
    if (result.containsKey('error') || result.isEmpty) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    return _json({'code': 0, 'data': result['data'] ?? result});
  }

  Future<Response> _handleSyncthingDiscovery(Request request) async {
    final result = await _api.proxyGet('/rest/system/discovery');
    if (result.containsKey('error')) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    final data = result.containsKey('data') ? result['data'] : result;
    return _json({'code': 0, 'data': data});
  }

  Future<Response> _handlePendingDevices(Request request) async {
    final result = await _api.proxyGet('/rest/cluster/pending/devices', silent: true);
    if (result.containsKey('error')) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    final raw = result.containsKey('data') ? result['data'] : result;
    if (raw is! Map) {
      return _json({'code': 0, 'data': {}});
    }

    final pending = Map<String, dynamic>.from(raw);
    final configured = await _configuredDeviceNormIds();
    final filtered = <String, dynamic>{};

    for (final entry in pending.entries) {
      if (configured.contains(_normDeviceId(entry.key))) {
        // 已在 config 中但 pending 未清除（常见于重启后）
        await _api.proxyDelete(
          '/rest/cluster/pending/devices',
          queryParams: {'device': entry.key},
        );
        debugPrint('[pending] 已忽略并清除 stale pending: ${entry.key}');
        continue;
      }
      filtered[entry.key] = entry.value;
    }

    return _json({'code': 0, 'data': filtered});
  }

  String _normDeviceId(String id) =>
      id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  Future<Set<String>> _configuredDeviceNormIds() async {
    final ids = <String>{};
    final result = await _api.proxyGet('/rest/config/devices', silent: true);
    final list = result['data'];
    if (list is List) {
      for (final d in list) {
        if (d is Map) {
          final id = d['deviceID']?.toString() ?? '';
          if (id.isNotEmpty) ids.add(_normDeviceId(id));
        }
      }
    }
    return ids;
  }

  Future<Response> _handleDismissPendingDevice(Request request) async {
    final deviceId = request.url.queryParameters['device'] ?? '';
    if (deviceId.isEmpty) {
      return _json({'code': 1001, 'data': '缺少 device 参数'});
    }
    final result = await _api.proxyDelete('/rest/cluster/pending/devices',
        queryParams: {'device': deviceId});
    if (result.containsKey('error')) {
      return _json({'code': 1006, 'data': result['error']}, status: 503);
    }
    return _json({'code': 0, 'data': 'ok'});
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
    final deviceId = data['deviceID']?.toString() ?? '';
    final name = data['name']?.toString() ?? '';
    if (deviceId.isEmpty) {
      return _json({'code': 1001, 'data': '缺少 deviceID'}, status: 400);
    }
    final result = await _api.addDeviceToConfig(deviceId, name);
    if (result.containsKey('error')) {
      final err = result['error'].toString();
      if (err.contains('Syncthing 未运行') ||
          err.contains('连接被拒绝') ||
          err.contains('Connection refused')) {
        return _json({'code': 1006, 'data': 'Syncthing 未运行，请重启应用'}, status: 503);
      }
      return _json({'code': 1003, 'data': '添加设备失败: $err'}, status: 500);
    }
    return _json({'code': 0, 'data': result});
  }

  Future<Response> _handleRemoveDevice(Request request, String deviceId) async {
    if (deviceId.isEmpty || deviceId == 'local') {
      return _json({'code': 1001, 'data': '无法删除本机设备'}, status: 400);
    }
    if (await _isLocalDeviceId(deviceId)) {
      return _json({'code': 1001, 'data': '无法删除本机设备'}, status: 400);
    }

    final result = await _api.proxyDelete('/rest/config/devices/$deviceId');
    if (result.containsKey('error')) {
      return _json({'code': 1003, 'data': '删除设备失败: ${result['error']}'}, status: 500);
    }
    return _json({'code': 0, 'data': {'message': '设备移除成功', 'deviceID': deviceId}});
  }

  Future<Response> _handleCreateFolder(Request request) async {
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    final id = data['id'] ?? '';
    final label = data['label'] ?? data['name'] ?? id;
    final path = data['path'] ?? '';
    if (id.isEmpty || path.isEmpty) {
      return _json({'code': 1002, 'data': '缺少必填字段'}, status: 400);
    }

    // 检查是否已存在相同路径或 ID 的文件夹
    final existing = _api.getFoldersFromConfig();
    for (final f in existing) {
      if (f['id'] == id) {
        return _json({'code': 1003, 'data': '文件夹 ID 已存在: $id'}, status: 400);
      }
      final normPath = path.replaceAll(RegExp(r'/+$'), '');
      final existPath = (f['path'] ?? '').replaceAll(RegExp(r'/+$'), '');
      if (normPath == existPath) {
        return _json({'code': 1003, 'data': '该路径已存在同步文件夹'}, status: 400);
      }
    }

    final folderData = <String, dynamic>{
      'id': id, 'label': label, 'path': path, 'type': data['type'] ?? 'sendreceive',
      'filesystemType': 'basic', 'rescanIntervalS': 3600, 'ignorePerms': false,
      'autoNormalize': true, 'devices': [],
    };
    final result = await _api.proxyPost('/rest/config/folders', folderData);
    if (result.containsKey('error')) {
      return _json({'code': 1003, 'data': '添加文件夹失败: ${result['error']}'}, status: 500);
    }
    return _json({'code': 0, 'data': {'id': id, 'label': label, 'path': path}});
  }

  Future<Response> _handleDeleteFolder(Request request, String deviceId, String folderId) async {
    final result = await _api.proxyDelete('/rest/config/folders/$folderId');
    if (result.containsKey('error')) {
      return _json({'code': 1003, 'data': '删除文件夹失败: ${result['error']}'}, status: 500);
    }
    return _json({'code': 0, 'data': {'message': '文件夹已删除'}});
  }

  Future<Response> _handleHealth(Request request) async =>
      _json({'status': 'ok', 'service': 'mydata-api'});
}
