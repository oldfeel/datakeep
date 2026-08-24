import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'cert_manager.dart';
import 'syncthing_api.dart';
import 'peer_client.dart';
import 'folder_acl_store.dart';
import 'folder_kind_store.dart';
import '../../shared/utils/file_types.dart';
import '../../shared/utils/preview_limits.dart';
import '../../shared/utils/sync_folder_paths.dart';
import '../../shared/utils/app_manifest.dart';
import '../services/thumbnail_service.dart';

class BackendServer {
  final SyncthingApi _api = SyncthingApi();
  final FolderAclStore _acl = FolderAclStore();
  final FolderKindStore _kind = FolderKindStore();
  late CertManager _certMgr;
  HttpServer? _server;
  String? _defaultLocalDeviceName;
  bool _deviceNameEnsureAttempted = false;

  bool get isRunning => _server != null;

  Future<void> start({int port = 8443, String? syncthingConfigPath, String? defaultLocalDeviceName}) async {
    if (_server != null) return;
    _defaultLocalDeviceName = defaultLocalDeviceName;
    _api.init(configPath: syncthingConfigPath, defaultLocalDeviceName: defaultLocalDeviceName);

    final dataDir = await _resolveDataDir();
    _certMgr = CertManager('$dataDir/certs');
    await _certMgr.ensureReady();
    await _acl.init(dataDir);
    await _kind.init(dataDir);

    final router = Router()
      ..get('/api/devices', _handleDevices)
      ..get('/api/device/<deviceId>/folders', _handleDeviceFolders)
      ..get('/api/device/<deviceId>/folder/<folderId>/files', _handleDeviceFolderFiles)
      ..get('/api/device/<deviceId>/folder/<folderId>/preview', _handleDeviceFolderPreview)
      ..get('/api/device/<deviceId>/folder/<folderId>/thumbnail', _handleDeviceFolderThumbnail)
      ..put('/api/device/<deviceId>/folder/<folderId>/file', _handleDeviceFolderPutFile)
      ..delete('/api/device/<deviceId>/folder/<folderId>/file', _handleDeviceFolderDeleteFile)
      ..post('/api/device/local/folders', _handleCreateFolder)
      ..delete('/api/device/<deviceId>/folders/<folderId>', _handleDeleteFolder)
      ..delete('/api/device/<deviceId>', _handleRemoveDevice)
      ..get('/api/deviceid', _handleDeviceId)
      ..get('/api/folder/<folderId>', _handleFolderFiles)
      ..get('/api/folder/<folderId>/status', _handleFolderStatus)
      ..get('/api/folder/<folderId>/acl', _handleGetFolderAcl)
      ..post('/api/folder/<folderId>/acl', _handleSetFolderAcl)
      ..post('/api/folder/<folderId>/kind', _handleSetFolderKind)
      ..get('/api/folder/<folderId>/settings', _handleGetFolderSettings)
      ..put('/api/folder/<folderId>/settings', _handlePutFolderSettings)
      ..get('/api/folder/<folderId>/ignores', _handleGetFolderIgnores)
      ..post('/api/folder/<folderId>/ignores', _handleSetFolderIgnores)
      ..post('/api/folder/<folderId>/scan', _handleFolderScan)
      ..post('/api/folder/<folderId>/reset-index', _handleFolderResetIndex)
      ..get('/api/folder/<folderId>/issues', _handleFolderIssues)
      ..post('/api/folder/<folderId>/fix-path', _handleFixFolderPath)
      ..get('/api/folder/<folderId>/preview', _handleFilePreview)
      ..get('/api/folder/<folderId>/thumbnail', _handleFolderThumbnail)
      ..get('/api/wifi', _handleWifiInfo)
      ..get('/api/wifi-info', _handleWifiInfo)
      ..post('/api/folder/<folderId>/sharing', _handleSharing)
      ..get('/api/syncthing/events', _handleSyncthingEvents)
      ..get('/api/syncthing/discovery', _handleSyncthingDiscovery)
      ..get('/api/syncthing/cluster/pending/devices', _handlePendingDevices)
      ..delete('/api/syncthing/cluster/pending/devices', _handleDismissPendingDevice)
      ..get('/api/syncthing/cluster/pending/folders', _handlePendingFolders)
      ..delete('/api/syncthing/cluster/pending/folders', _handleDismissPendingFolder)
      ..post('/api/syncthing/cluster/pending/folders/accept', _handleAcceptPendingFolder)
      ..get('/api/syncthing/deviceid', _handleSyncthingDeviceId)
      ..post('/api/syncthing/config/devices', _handleSyncthingAddDevice)
      ..get('/api/peer/folders', _handlePeerFolders)
      ..get('/api/peer/folder/<folderId>/files', _handlePeerFolderFiles)
      ..get('/api/peer/folder/<folderId>/preview', _handlePeerFolderPreview)
      ..get('/api/peer/folder/<folderId>/thumbnail', _handlePeerFolderThumbnail)
      ..put('/api/peer/folder/<folderId>/file', _handlePeerFolderPutFile)
      ..delete('/api/peer/folder/<folderId>/file', _handlePeerFolderDeleteFile)
      ..get('/api/peer/health', _handlePeerHealth)
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
    // 桌面：优先已有运行目录下的数据（兼容旧 cwd）；否则用应用支持目录，避免 cwd 变化丢 ACL
    final cwd = Directory.current.path;
    final cwdAcl = File('$cwd/folder_acl.json');
    final cwdCerts = Directory('$cwd/certs');
    if (cwdAcl.existsSync() || cwdCerts.existsSync()) {
      debugPrint('[dataDir] 使用当前目录: $cwd');
      return cwd;
    }
    final support = await getApplicationSupportDirectory();
    debugPrint('[dataDir] 使用应用支持目录: ${support.path}');
    return support.path;
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
          'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
        });
      }
      final response = await innerHandler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        if (!response.headers.containsKey('Access-Control-Allow-Headers'))
          'Access-Control-Allow-Headers': '*',
        if (!response.headers.containsKey('Access-Control-Allow-Methods'))
          'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
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

    // Syncthing 运行中若 config 仍是 localhost，通过 API 写入手机型号（仅尝试一次，避免 ConfigSaved 循环）
    if (!_deviceNameEnsureAttempted &&
        localId != null &&
        _defaultLocalDeviceName != null &&
        _defaultLocalDeviceName!.isNotEmpty) {
      _deviceNameEnsureAttempted = true;
      final configName = await _api.getEffectiveDeviceName(localId);
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
    final isLocal = await _isLocalDeviceId(deviceId);
    if (!isLocal) {
      return _handleRemoteDeviceFolders(deviceId);
    }
    return _json({'code': 0, 'data': await _buildLocalFoldersPayload()});
  }

  /// 本机文件夹列表（含同步统计）；隐藏嵌套在其他同步文件夹内的项（如装在 test/ 下的应用）
  Future<List<Map<String, dynamic>>> _buildLocalFoldersPayload() async {
    final localId = await _api.getLocalDeviceId();
    final result = await _api.proxyGet('/rest/config/folders', silent: true);
    if (result.containsKey('error')) {
      return _filterNestedFolders(_localFoldersPayload());
    }

    final rawList = result['data'] as List? ?? [];
    if (rawList.isEmpty) return _filterNestedFolders(_localFoldersPayload());

    final folders = <Map<String, dynamic>>[];
    for (final f in rawList) {
      if (f is! Map) continue;
      final map = Map<String, dynamic>.from(f);
      final devices = (map['devices'] as List?) ?? [];
      final sharedDevices = devices
          .whereType<Map>()
          .map((d) => d['deviceID']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .where((id) =>
              localId == null || _normDeviceId(id) != _normDeviceId(localId))
          .toList();
      map['sharedDevices'] = sharedDevices;
      folders.add(await _folderPayload(map));
    }
    return _filterNestedFolders(folders);
  }

  /// 路径落在另一同步文件夹内部的项不出现在首页列表
  List<Map<String, dynamic>> _filterNestedFolders(
    List<Map<String, dynamic>> folders,
  ) {
    String norm(String path) {
      var s = path.trim();
      while (s.length > 1 && (s.endsWith('/') || s.endsWith('\\'))) {
        s = s.substring(0, s.length - 1);
      }
      return s;
    }

    bool inside(String child, String parent) {
      final c = norm(child);
      final p = norm(parent);
      if (c.isEmpty || p.isEmpty || c == p) return false;
      return c.startsWith('$p/') || c.startsWith('$p\\');
    }

    return folders.where((f) {
      final path = f['path']?.toString() ?? '';
      if (path.isEmpty) return true;
      for (final other in folders) {
        if (identical(f, other)) continue;
        if ((f['id']?.toString() ?? '') == (other['id']?.toString() ?? '')) {
          continue;
        }
        final op = other['path']?.toString() ?? '';
        if (op.isEmpty) continue;
        if (inside(path, op)) return false;
      }
      return true;
    }).toList();
  }

  /// 经局域网 HTTPS 拉取对端真实文件夹列表
  Future<Response> _handleRemoteDeviceFolders(String deviceId) async {
    if (!await _api.isRunning()) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    final conn = await _api.getDeviceConnection(deviceId);
    if (!conn.connected) {
      return _json({'code': 1007, 'data': '设备离线'}, status: 503);
    }
    final ip = PeerClient.extractLanIp(conn.address);
    if (ip == null) {
      return _json({
        'code': 1007,
        'data': '无法解析对端局域网地址（可能经中继连接）',
      }, status: 503);
    }

    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      return _json({'code': 1007, 'data': '本机设备 ID 未知'}, status: 503);
    }

    debugPrint('[peer] 拉取对端文件夹: device=$deviceId ip=$ip');
    final peer = await PeerClient.getJson(
      ip,
      '/api/peer/folders',
      headers: {PeerClient.deviceIdHeader: localId},
    );
    if (peer.containsKey('error')) {
      return _json({
        'code': 1008,
        'data': peer['error']?.toString() ?? '对端文件管理不可达',
      }, status: 503);
    }
    if (peer['code'] != 0) {
      return _json({
        'code': peer['code'] ?? 1008,
        'data': peer['data']?.toString() ?? '对端返回错误',
      }, status: 503);
    }
    final data = peer['data'];
    if (data is! List) {
      return _json({'code': 1008, 'data': '对端响应格式错误'}, status: 502);
    }
    return _json({'code': 0, 'data': data});
  }

  /// 对端探活
  Future<Response> _handlePeerHealth(Request request) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final localId = await _api.getLocalDeviceId();
    return _json({
      'code': 0,
      'data': {'ok': true, 'deviceID': localId ?? ''},
    });
  }

  /// 对端拉取本机文件夹（按 ACL：仅 sync/readonly）
  Future<Response> _handlePeerFolders(Request request) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    final folders = await _buildLocalFoldersPayload();
    final filtered = <Map<String, dynamic>>[];
    for (final f in folders) {
      final folderId = f['id']?.toString() ?? '';
      if (folderId.isEmpty) continue;
      final sharedIds = (f['sharedDevices'] as List?) ?? [];
      final syncthingShared = sharedIds.any(
        (id) => _normDeviceId(id.toString()) == _normDeviceId(callerId),
      );
      final access = _acl.resolve(
        folderId,
        callerId,
        syncthingShared: syncthingShared,
      );
      if (!access.isPeerVisible) continue;
      final copy = Map<String, dynamic>.from(f);
      copy['access'] = access.apiValue;
      filtered.add(copy);
    }
    return _json({'code': 0, 'data': filtered});
  }

  /// 对端只读浏览本机文件夹文件
  Future<Response> _handlePeerFolderFiles(Request request, String folderId) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    final access = await _resolveAccessForCaller(folderId, callerId);
    if (!access.isPeerVisible) {
      return _json({'code': 1403, 'data': '无权限访问该文件夹'}, status: 403);
    }
    return _browseFolderFiles(folderId, request.url.queryParameters['path'] ?? '');
  }

  /// 对端只读预览本机文件
  Future<Response> _handlePeerFolderPreview(Request request, String folderId) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    final access = await _resolveAccessForCaller(folderId, callerId);
    if (!access.isPeerVisible) {
      return Response(403, body: '无权限访问该文件夹');
    }
    return _serveLocalFilePreview(folderId, request.url.queryParameters['path'] ?? '');
  }

  /// 对端拉取本机文件缩略图（只读 ACL 即可）
  Future<Response> _handlePeerFolderThumbnail(Request request, String folderId) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    final access = await _resolveAccessForCaller(folderId, callerId);
    if (!access.isPeerVisible) {
      return Response(403, body: '无权限访问该文件夹');
    }
    return _serveLocalFolderThumbnail(folderId, request.url.queryParameters['path'] ?? '');
  }

  /// 对端写入本机文件（仅 ACL=sync）
  Future<Response> _handlePeerFolderPutFile(Request request, String folderId) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    final access = await _resolveAccessForCaller(folderId, callerId);
    if (access != FolderAccess.sync) {
      return Response(403, body: '无写入权限（需要同步权限）');
    }
    final path = request.url.queryParameters['path'] ?? '';
    return _writeLocalFolderFile(folderId, path, request);
  }

  /// 对端删除本机文件（仅 ACL=sync）
  Future<Response> _handlePeerFolderDeleteFile(Request request, String folderId) async {
    final auth = await _authorizePeer(request);
    if (auth != null) return auth;
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    final access = await _resolveAccessForCaller(folderId, callerId);
    if (access != FolderAccess.sync) {
      return Response(403, body: '无写入权限（需要同步权限）');
    }
    final path = request.url.queryParameters['path'] ?? '';
    return _deleteLocalFolderFile(folderId, path);
  }

  Future<FolderAccess> _resolveAccessForCaller(String folderId, String callerId) async {
    final folders = await _buildLocalFoldersPayload();
    Map<String, dynamic>? match;
    for (final f in folders) {
      if (f['id']?.toString() == folderId) {
        match = f;
        break;
      }
    }
    final sharedIds = (match?['sharedDevices'] as List?) ?? [];
    final syncthingShared = sharedIds.any(
      (id) => _normDeviceId(id.toString()) == _normDeviceId(callerId),
    );
    return _acl.resolve(folderId, callerId, syncthingShared: syncthingShared);
  }

  /// 本机或代理对端的文件列表
  Future<Response> _handleDeviceFolderFiles(
    Request request,
    String deviceId,
    String folderId,
  ) async {
    final isLocal = await _isLocalDeviceId(deviceId);
    if (isLocal) {
      return _browseFolderFiles(folderId, request.url.queryParameters['path'] ?? '');
    }
    return _proxyPeerFolderFiles(deviceId, folderId, request.url.queryParameters['path'] ?? '');
  }

  /// 本机或代理对端的文件预览
  Future<Response> _handleDeviceFolderPreview(
    Request request,
    String deviceId,
    String folderId,
  ) async {
    final path = request.url.queryParameters['path'] ?? '';
    final isLocal = await _isLocalDeviceId(deviceId);
    if (isLocal) {
      return _serveLocalFilePreview(folderId, path);
    }
    return _proxyPeerFolderPreview(deviceId, folderId, path);
  }

  Future<Response> _handleDeviceFolderThumbnail(
    Request request,
    String deviceId,
    String folderId,
  ) async {
    final path = request.url.queryParameters['path'] ?? '';
    final isLocal = await _isLocalDeviceId(deviceId);
    if (isLocal) {
      return _serveLocalFolderThumbnail(folderId, path);
    }
    return _proxyPeerFolderThumbnail(deviceId, folderId, path);
  }

  Future<Response> _handleDeviceFolderPutFile(
    Request request,
    String deviceId,
    String folderId,
  ) async {
    final path = request.url.queryParameters['path'] ?? '';
    final isLocal = await _isLocalDeviceId(deviceId);
    if (isLocal) {
      return _writeLocalFolderFile(folderId, path, request);
    }
    return _proxyPeerFolderPutFile(deviceId, folderId, path, request);
  }

  Future<Response> _handleDeviceFolderDeleteFile(
    Request request,
    String deviceId,
    String folderId,
  ) async {
    final path = request.url.queryParameters['path'] ?? '';
    final isLocal = await _isLocalDeviceId(deviceId);
    if (isLocal) {
      return _deleteLocalFolderFile(folderId, path);
    }
    return _proxyPeerFolderDeleteFile(deviceId, folderId, path);
  }

  Future<Response> _proxyPeerFolderFiles(
    String deviceId,
    String folderId,
    String path,
  ) async {
    if (!await _api.isRunning()) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    final conn = await _api.getDeviceConnection(deviceId);
    if (!conn.connected) {
      return _json({'code': 1007, 'data': '设备离线'}, status: 503);
    }
    final ip = PeerClient.extractLanIp(conn.address);
    if (ip == null) {
      return _json({'code': 1007, 'data': '无法解析对端局域网地址'}, status: 503);
    }
    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      return _json({'code': 1007, 'data': '本机设备 ID 未知'}, status: 503);
    }
    final encoded = Uri.encodeComponent(folderId);
    final q = path.isEmpty ? '' : '?path=${Uri.encodeComponent(path)}';
    final peer = await PeerClient.getJson(
      ip,
      '/api/peer/folder/$encoded/files$q',
      headers: {PeerClient.deviceIdHeader: localId},
    );
    if (peer.containsKey('error')) {
      return _json({
        'code': 1008,
        'data': peer['error']?.toString() ?? '对端不可达',
      }, status: 503);
    }
    if (peer['code'] != 0) {
      return _json({
        'code': peer['code'] ?? 1008,
        'data': peer['data']?.toString() ?? '对端返回错误',
      }, status: peer['statusCode'] is int ? peer['statusCode'] as int : 503);
    }
    return _json({'code': 0, 'data': peer['data'] ?? []});
  }

  Future<Response> _proxyPeerFolderPreview(
    String deviceId,
    String folderId,
    String path,
  ) async {
    if (path.isEmpty) return Response(400, body: '缺少 path 参数');
    if (!await _api.isRunning()) {
      return Response(503, body: 'Syncthing 未运行');
    }
    final conn = await _api.getDeviceConnection(deviceId);
    if (!conn.connected) {
      return Response(503, body: '设备离线');
    }
    final ip = PeerClient.extractLanIp(conn.address);
    if (ip == null) {
      return Response(
        503,
        body: '无法解析对端局域网地址（需同网且对端已打开文件管理）',
      );
    }
    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      return Response(503, body: '本机设备 ID 未知');
    }
    final encoded = Uri.encodeComponent(folderId);
    final q = '?path=${Uri.encodeComponent(path)}';
    debugPrint('[peer] 拉取对端预览: device=$deviceId folder=$folderId path=$path');

    final temp = await Directory.systemTemp.createTemp('datakeep_peer_proxy_');
    final dest = '${temp.path}/file.bin';
    final peer = await PeerClient.downloadToFile(
      ip,
      '/api/peer/folder/$encoded/preview$q',
      dest,
      headers: {PeerClient.deviceIdHeader: localId},
    );
    if (peer.containsKey('error')) {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
      final code = peer['statusCode'] is int ? peer['statusCode'] as int : 503;
      return Response(code, body: peer['error']?.toString() ?? '对端不可达');
    }
    final contentType =
        peer['contentType']?.toString() ?? 'application/octet-stream';
    final file = File(dest);
    final size = await file.length();
    final stream = file.openRead().transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          sink.close();
          try {
            temp.deleteSync(recursive: true);
          } catch (_) {}
        },
        handleError: (e, st, sink) {
          try {
            temp.deleteSync(recursive: true);
          } catch (_) {}
          sink.addError(e, st);
        },
      ),
    );
    return Response.ok(
      stream,
      headers: {
        'Content-Type': contentType,
        'Content-Length': '$size',
      },
    );
  }

  Future<Response> _proxyPeerFolderThumbnail(
    String deviceId,
    String folderId,
    String path,
  ) async {
    if (path.isEmpty) return Response(400, body: '缺少 path 参数');
    if (!await _api.isRunning()) {
      return Response(503, body: 'Syncthing 未运行');
    }
    final conn = await _api.getDeviceConnection(deviceId);
    if (!conn.connected) {
      return Response(503, body: '设备离线');
    }
    final ip = PeerClient.extractLanIp(conn.address);
    if (ip == null) {
      return Response(
        503,
        body: '无法解析对端局域网地址（需同网且对端已打开文件管理）',
      );
    }
    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      return Response(503, body: '本机设备 ID 未知');
    }
    final encoded = Uri.encodeComponent(folderId);
    final q = '?path=${Uri.encodeComponent(path)}';
    debugPrint('[peer] 拉取对端缩略图: device=$deviceId folder=$folderId path=$path');

    final peer = await PeerClient.getBytes(
      ip,
      '/api/peer/folder/$encoded/thumbnail$q',
      headers: {PeerClient.deviceIdHeader: localId},
      maxBytes: kMaxThumbnailProxyBytes,
      timeout: const Duration(seconds: 90),
    );
    if (peer.containsKey('error')) {
      final code = peer['statusCode'] is int ? peer['statusCode'] as int : 503;
      return Response(code, body: peer['error']?.toString() ?? '对端不可达');
    }
    final bytes = peer['bytes'];
    if (bytes is! List<int> || bytes.isEmpty) {
      return Response(404, body: '无缩略图');
    }
    return Response.ok(
      bytes,
      headers: {'Content-Type': 'image/png'},
    );
  }

  Future<Response> _proxyPeerFolderPutFile(
    String deviceId,
    String folderId,
    String path,
    Request request,
  ) async {
    if (path.isEmpty) return Response(400, body: '缺少 path 参数');
    if (!await _api.isRunning()) {
      return Response(503, body: 'Syncthing 未运行');
    }
    final conn = await _api.getDeviceConnection(deviceId);
    if (!conn.connected) {
      return Response(503, body: '设备离线');
    }
    final ip = PeerClient.extractLanIp(conn.address);
    if (ip == null) {
      return Response(
        503,
        body: '无法解析对端局域网地址（需同网且对端已打开文件管理）',
      );
    }
    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      return Response(503, body: '本机设备 ID 未知');
    }
    final bytes = await request.read().fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (b, chunk) {
        b.add(chunk);
        return b;
      },
    );
    final data = bytes.takeBytes();
    if (data.length > _maxPreviewBytes) {
      return Response(413, body: '文件过大，超过写入上限');
    }
    final encoded = Uri.encodeComponent(folderId);
    final q = '?path=${Uri.encodeComponent(path)}';
    debugPrint('[peer] 写入对端: device=$deviceId folder=$folderId path=$path bytes=${data.length}');
    final peer = await PeerClient.putBytes(
      ip,
      '/api/peer/folder/$encoded/file$q',
      data,
      headers: {PeerClient.deviceIdHeader: localId},
    );
    if (peer.containsKey('error')) {
      final code = peer['statusCode'] is int ? peer['statusCode'] as int : 503;
      return Response(code, body: peer['error']?.toString() ?? '对端不可达');
    }
    return Response.ok(
      '{"ok":true}',
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _proxyPeerFolderDeleteFile(
    String deviceId,
    String folderId,
    String path,
  ) async {
    if (path.isEmpty) return Response(400, body: '缺少 path 参数');
    if (!await _api.isRunning()) {
      return Response(503, body: 'Syncthing 未运行');
    }
    final conn = await _api.getDeviceConnection(deviceId);
    if (!conn.connected) {
      return Response(503, body: '设备离线');
    }
    final ip = PeerClient.extractLanIp(conn.address);
    if (ip == null) {
      return Response(
        503,
        body: '无法解析对端局域网地址（需同网且对端已打开文件管理）',
      );
    }
    final localId = await _api.getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      return Response(503, body: '本机设备 ID 未知');
    }
    final encoded = Uri.encodeComponent(folderId);
    final q = '?path=${Uri.encodeComponent(path)}';
    final peer = await PeerClient.delete(
      ip,
      '/api/peer/folder/$encoded/file$q',
      headers: {PeerClient.deviceIdHeader: localId},
    );
    if (peer.containsKey('error')) {
      final code = peer['statusCode'] is int ? peer['statusCode'] as int : 503;
      return Response(code, body: peer['error']?.toString() ?? '对端不可达');
    }
    return Response.ok(
      '{"ok":true}',
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    );
  }

  Future<Response> _handleGetFolderAcl(Request request, String folderId) async {
    var decodedId = folderId;
    try {
      decodedId = Uri.decodeComponent(folderId);
    } catch (_) {}

    final devices = await _api.proxyGet('/rest/config/devices', silent: true);
    final deviceList = devices['data'] is List ? devices['data'] as List : [];
    final localId = await _api.getLocalDeviceId();

    // 当前 Syncthing 共享设备
    final folderCfg = await _api.proxyGet(
      '/rest/config/folders/${Uri.encodeComponent(decodedId)}',
      silent: true,
    );
    final sharedNorm = <String>{};
    if (!folderCfg.containsKey('error')) {
      for (final d in (folderCfg['devices'] as List? ?? [])) {
        if (d is! Map) continue;
        final id = d['deviceID']?.toString() ?? '';
        if (id.isNotEmpty) sharedNorm.add(_normDeviceId(id));
      }
    }

    final permissions = <String, String>{};
    for (final d in deviceList) {
      if (d is! Map) continue;
      final id = d['deviceID']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (localId != null && _normDeviceId(id) == _normDeviceId(localId)) continue;
      final access = _acl.resolve(
        decodedId,
        id,
        syncthingShared: sharedNorm.contains(_normDeviceId(id)),
      );
      permissions[id] = access.apiValue;
    }

    return _json({
      'code': 0,
      'data': {
        'folderId': decodedId,
        'permissions': permissions,
      },
    });
  }

  Future<Response> _handleSetFolderAcl(Request request, String folderId) async {
    var decodedId = folderId;
    try {
      decodedId = Uri.decodeComponent(folderId);
    } catch (_) {}

    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    final rawPerms = data['permissions'];
    if (rawPerms is! Map) {
      return _json({'code': 1001, 'data': '缺少 permissions'}, status: 400);
    }

    final permissions = <String, FolderAccess>{};
    for (final e in rawPerms.entries) {
      final access = FolderAccess.tryParse(e.value?.toString());
      if (access == null) {
        return _json({
          'code': 1001,
          'data': '无效权限: ${e.value}',
        }, status: 400);
      }
      permissions[e.key.toString()] = access;
    }

    await _acl.setFolderPermissions(decodedId, permissions);
    debugPrint(
      '[acl] 已写入 ${_acl.filePath} folder=$decodedId '
      'perms=${permissions.map((k, v) => MapEntry(k, v.apiValue))}',
    );

    // 对齐 Syncthing：仅 sync 设备加入共享
    final localId = await _api.getLocalDeviceId();
    final syncIds = permissions.entries
        .where((e) => e.value == FolderAccess.sync)
        .map((e) => e.key)
        .toList();
    var sharedDevices = [...syncIds];
    if (localId != null &&
        !sharedDevices.any((id) => _normDeviceId(id) == _normDeviceId(localId))) {
      sharedDevices = [localId, ...sharedDevices];
    }

    final encoded = Uri.encodeComponent(decodedId);
    final folder = await _api.proxyGet('/rest/config/folders/$encoded');
    if (folder.containsKey('error')) {
      return _json({'code': 1004, 'data': '文件夹不存在'}, status: 404);
    }

    final oldRemoteIds = <String>{};
    for (final d in (folder['devices'] as List? ?? [])) {
      if (d is! Map) continue;
      final id = d['deviceID']?.toString() ?? '';
      if (id.isEmpty || localId == null) continue;
      if (_normDeviceId(id) != _normDeviceId(localId)) {
        oldRemoteIds.add(id);
      }
    }

    folder['devices'] = _folderDeviceList(sharedDevices);
    final result = await _api.proxyPut('/rest/config/folders/$encoded', folder);
    if (result.containsKey('error')) {
      return _json({'code': 1005, 'data': '保存失败: ${result['error']}'}, status: 500);
    }

    // 对仍为 sync 且原本已共享的设备，强制重发邀请
    if (localId != null) {
      for (final remoteId in syncIds) {
        if (_normDeviceId(remoteId) == _normDeviceId(localId)) continue;
        final wasShared =
            oldRemoteIds.any((id) => _normDeviceId(id) == _normDeviceId(remoteId));
        if (!wasShared) continue;
        debugPrint('[acl] 重新向 $remoteId 发送文件夹 $decodedId 邀请');
        final withoutRemote = sharedDevices
            .where((id) => _normDeviceId(id) != _normDeviceId(remoteId))
            .toList();
        folder['devices'] = _folderDeviceList(withoutRemote);
        await _api.proxyPut('/rest/config/folders/$encoded', folder);
        await Future.delayed(const Duration(milliseconds: 300));
        folder['devices'] = _folderDeviceList(sharedDevices);
        await _api.proxyPut('/rest/config/folders/$encoded', folder);
      }
    }

    await _api.triggerFolderScan(decodedId);
    return _json({'code': 0, 'data': {'message': '权限已更新'}});
  }

  String _decodeFolderId(String folderId) {
    var id = folderId;
    // shelf 有时留下未解码的 %XX；中文 folder id 需还原，否则 Syncthing 404
    for (var i = 0; i < 2; i++) {
      try {
        final decoded = Uri.decodeComponent(id);
        if (decoded == id) break;
        id = decoded;
      } catch (_) {
        break;
      }
    }
    return id;
  }

  Future<Response> _handleGetFolderSettings(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final encoded = Uri.encodeComponent(id);
    final folder = await _api.proxyGet('/rest/config/folders/$encoded', silent: true);
    if (folder.containsKey('error')) {
      return _json({'code': 1004, 'data': '文件夹不存在'}, status: 404);
    }
    return _json({
      'code': 0,
      'data': {
        'id': folder['id'] ?? id,
        'label': folder['label'] ?? id,
        'path': folder['path'] ?? '',
        'type': folder['type']?.toString() ?? 'sendreceive',
        'paused': folder['paused'] == true,
      },
    });
  }

  Future<Response> _handlePutFolderSettings(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final encoded = Uri.encodeComponent(id);
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;

    final folder = await _api.proxyGet('/rest/config/folders/$encoded');
    if (folder.containsKey('error')) {
      return _json({'code': 1004, 'data': '文件夹不存在'}, status: 404);
    }

    const allowedTypes = {'sendreceive', 'sendonly', 'receiveonly'};
    if (data.containsKey('type')) {
      final t = data['type']?.toString() ?? '';
      if (!allowedTypes.contains(t)) {
        return _json({'code': 1001, 'data': '无效文件夹类型: $t'}, status: 400);
      }
      folder['type'] = t;
    }
    if (data.containsKey('paused')) {
      folder['paused'] = data['paused'] == true;
    }

    final result = await _api.proxyPut('/rest/config/folders/$encoded', folder);
    if (result.containsKey('error')) {
      return _json({'code': 1005, 'data': '保存失败: ${result['error']}'}, status: 500);
    }
    return _json({
      'code': 0,
      'data': {
        'id': folder['id'] ?? id,
        'type': folder['type'] ?? 'sendreceive',
        'paused': folder['paused'] == true,
      },
    });
  }

  Future<Response> _handleGetFolderIgnores(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final result = await _api.proxyGet(
      '/rest/db/ignores',
      queryParams: {'folder': id},
      silent: true,
    );
    if (_apiIsError(result)) {
      return _json({
        'code': 1005,
        'data': result['error']?.toString() ?? '读取忽略规则失败',
      }, status: 503);
    }
    final ignore = (result['ignore'] as List?)?.map((e) => e.toString()).toList() ?? [];
    return _json({'code': 0, 'data': {'ignore': ignore}});
  }

  Future<Response> _handleSetFolderIgnores(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    final raw = data['ignore'];
    final lines = <String>[];
    if (raw is List) {
      lines.addAll(raw.map((e) => e.toString()));
    } else if (raw is String) {
      lines.addAll(raw.split('\n'));
    } else {
      return _json({'code': 1001, 'data': '缺少 ignore'}, status: 400);
    }

    final result = await _api.proxyPost(
      '/rest/db/ignores?folder=${Uri.encodeComponent(id)}',
      {'ignore': lines},
    );
    if (_apiIsError(result)) {
      return _json({
        'code': 1005,
        'data': result['error']?.toString() ?? '保存忽略规则失败',
      }, status: 500);
    }
    final ignore = (result['ignore'] as List?)?.map((e) => e.toString()).toList() ?? lines;
    return _json({'code': 0, 'data': {'ignore': ignore}});
  }

  Future<Response> _handleFolderScan(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    await _api.triggerFolderScan(id);
    return _json({'code': 0, 'data': {'message': '已触发扫描'}});
  }

  Future<Response> _handleFolderResetIndex(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final result = await _api.resetFolderIndex(id);
    if (result['ok'] == null &&
        (_apiIsError(result) ||
            (result['error'] != null &&
                result['error'].toString().isNotEmpty))) {
      final err = result['error']?.toString() ?? '未知错误';
      return _json({'code': 1003, 'data': '重建索引失败: $err'}, status: 500);
    }
    return _json({
      'code': 0,
      'data': {
        'message': '已重建索引并触发扫描',
        'folderId': id,
      },
    });
  }

  Future<Response> _handleFolderIssues(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final sync = await _api.getFolderSyncSummary(id);
    final errorsRes = await _api.proxyGet(
      '/rest/folder/errors',
      queryParams: {'folder': id},
      silent: true,
    );
    final needRes = await _api.proxyGet(
      '/rest/db/need',
      queryParams: {'folder': id, 'perpage': '20', 'page': '1'},
      silent: true,
    );

    final errors = <Map<String, String>>[];
    if (!_apiIsError(errorsRes)) {
      final list = errorsRes['errors'] ?? errorsRes['folderErrors'] ?? errorsRes['data'];
      if (list is List) {
        for (final e in list.take(20)) {
          if (e is Map) {
            errors.add({
              'path': e['path']?.toString() ?? e['name']?.toString() ?? '',
              'error': e['error']?.toString() ?? e['message']?.toString() ?? '',
            });
          }
        }
      }
    }

    final pending = <String>[];
    final conflicts = <String>[];
    void collectNeed(dynamic list) {
      if (list is! List) return;
      for (final e in list.take(30)) {
        String name = '';
        if (e is Map) {
          name = e['name']?.toString() ?? e['path']?.toString() ?? '';
        } else {
          name = e.toString();
        }
        if (name.isEmpty) continue;
        if (name.contains('.sync-conflict-')) {
          conflicts.add(name);
        } else {
          pending.add(name);
        }
      }
    }

    if (!_apiIsError(needRes)) {
      collectNeed(needRes['progress']);
      collectNeed(needRes['queued']);
      collectNeed(needRes['rest']);
      collectNeed(needRes['data']);
    }

    final pathError = sync['pathError']?.toString() ?? '';
    if (pathError.isNotEmpty) {
      errors.insert(0, {
        'path': sync['currentPath']?.toString() ?? id,
        'error': pathError,
      });
    }

    return _json({
      'code': 0,
      'data': {
        'pullErrors': sync['pullErrors'] ?? 0,
        'needFiles': sync['needFiles'] ?? 0,
        'needBytes': sync['needBytes'] ?? 0,
        'status': sync['status'] ?? 'unknown',
        'pathError': pathError.isEmpty ? null : pathError,
        'needsPathFix': sync['needsPathFix'] == true,
        'pathMissing': sync['pathMissing'] == true,
        'currentPath': sync['currentPath'],
        'errors': errors,
        'pending': pending.take(20).toList(),
        'conflicts': conflicts.take(20).toList(),
      },
    });
  }

  bool _apiIsError(Map<String, dynamic> result) {
    if (result.containsKey('error') &&
        result['error'] != null &&
        result['error'].toString().isNotEmpty) {
      // Syncthing 成功响应也可能带 error:""
      final err = result['error'].toString();
      if (err == 'null' || err.isEmpty) return false;
      // proxy 失败时 error 是网络/HTTP 信息
      if (result.length <= 2 && result.containsKey('error')) return true;
      if (err.startsWith('HTTP') || err.contains('Exception') || err.contains('Socket')) {
        return true;
      }
    }
    return false;
  }

  /// 校验 X-DataKeep-Device-ID 是否为已配对设备（或本机）
  Future<Response?> _authorizePeer(Request request) async {
    // shelf 将 header 名规范为小写
    final callerId = request.headers['x-datakeep-device-id'] ?? '';
    if (callerId.isEmpty) {
      return _json({'code': 1401, 'data': '缺少设备身份'}, status: 401);
    }
    if (await _isLocalDeviceId(callerId)) return null;
    final known = await _configuredDeviceNormIds();
    final localId = await _api.getLocalDeviceId();
    if (localId != null) known.add(_normDeviceId(localId));
    if (!known.contains(_normDeviceId(callerId))) {
      return _json({'code': 1403, 'data': '设备未配对'}, status: 403);
    }
    return null;
  }

  Future<Response> _handleDeviceId(Request request) async {
    final localId = await _api.getLocalDeviceId();
    return _json({'code': 0, 'data': {'deviceID': localId ?? 'local'}});
  }

  Future<Response> _handleFolderStatus(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final sync = await _api.getFolderSyncSummary(id);
    if (sync['status'] == 'unknown') {
      return _json({'code': 1005, 'data': '无法获取文件夹状态'}, status: 503);
    }
    final folderPath = await _api.getFolderPath(id);
    if (folderPath != null) {
      sync['currentPath'] = folderPath;
    }
    debugPrint(
      '[sync-api] GET /folder/$id/status → '
      '${sync['status']} ${sync['completion']}% '
      'inSync=${sync['inSyncFiles']}/${sync['globalFiles']} '
      'local=${sync['localFiles']} need=${sync['needFiles']}',
    );
    return _json({'code': 0, 'data': sync});
  }

  Future<Response> _handleFixFolderPath(Request request, String folderId) async {
    final folderPath = await _api.getFolderPath(folderId);
    if (folderPath == null) {
      return _json({'code': 1005, 'data': '文件夹未找到'}, status: 404);
    }

    var newPath = folderPath;
    final body = await request.read().expand((e) => e).toList();
    if (body.isNotEmpty) {
      try {
        final data = json.decode(utf8.decode(body)) as Map<String, dynamic>;
        final custom = data['path']?.toString() ?? '';
        if (custom.isNotEmpty) newPath = custom;
      } catch (_) {}
    }

    final encoded = Uri.encodeComponent(folderId);
    final existing = await _api.proxyGet('/rest/config/folders/$encoded', silent: true);
    if (existing.containsKey('error')) {
      return _json({'code': 1005, 'data': '文件夹未找到'}, status: 404);
    }
    final folderCfg = Map<String, dynamic>.from(existing);
    if (newPath != folderPath) {
      folderCfg['path'] = newPath;
    }
    folderCfg['paused'] = false;
    folderCfg['ignorePerms'] = true;
    final updated = await _api.proxyPut('/rest/config/folders/$encoded', folderCfg);
    if (updated.containsKey('error')) {
      return _json({'code': 1005, 'data': '更新路径失败: ${updated['error']}'}, status: 500);
    }

    await Directory(newPath).create(recursive: true);
    await _preCreateFolderMarker(newPath);
    await _api.triggerFolderScan(folderId);
    debugPrint('[folder] 已更新路径: $folderId $folderPath -> $newPath');
    return _json({
      'code': 0,
      'data': {'message': '已更新同步目录', 'oldPath': folderPath, 'newPath': newPath},
    });
  }

  /// 预建 .stfolder marker（与 Syncthing Android 一致）
  Future<void> _preCreateFolderMarker(String path) async {
    try {
      await Directory('$path/.stfolder').create(recursive: true);
    } catch (e) {
      debugPrint('[folder] 预建 .stfolder 失败: $e');
    }
  }

  Future<Response> _handleFolderFiles(Request request, String folderId) async {
    return _browseFolderFiles(folderId, request.url.queryParameters['path'] ?? '');
  }

  Future<Response> _browseFolderFiles(String folderId, String path) async {
    var folderPath = await _api.getFolderPath(folderId);
    if (folderPath == null || folderPath.isEmpty) {
      var decodedId = folderId;
      try {
        decodedId = Uri.decodeComponent(folderId);
      } catch (_) {}
      for (final f in _api.getFoldersFromConfig()) {
        final fid = f['id']?.toString() ?? '';
        if (fid == folderId || fid == decodedId) {
          folderPath = f['path']?.toString();
          break;
        }
      }
    }
    if (folderPath == null || folderPath.isEmpty) {
      return _json({'code': 1005, 'data': '文件夹未找到'});
    }
    final files = _api.browseLocalDirectory(folderPath, path);
    return _json({'code': 0, 'data': files});
  }

  Future<Response> _handleFilePreview(Request request, String folderId) async {
    return _serveLocalFilePreview(folderId, request.url.queryParameters['path'] ?? '');
  }

  Future<Response> _handleFolderThumbnail(Request request, String folderId) async {
    return _serveLocalFolderThumbnail(folderId, request.url.queryParameters['path'] ?? '');
  }

  static const int _maxPreviewBytes = 200 * 1024 * 1024; // 200MB

  Future<String?> _resolveFolderRootPath(String folderId) async {
    var folderPath = await _api.getFolderPath(folderId);
    if (folderPath == null || folderPath.isEmpty) {
      var decodedId = folderId;
      try {
        decodedId = Uri.decodeComponent(folderId);
      } catch (_) {}
      for (final f in _api.getFoldersFromConfig()) {
        final fid = f['id']?.toString() ?? '';
        if (fid == folderId || fid == decodedId) {
          folderPath = f['path']?.toString();
          break;
        }
      }
    }
    if (folderPath == null || folderPath.isEmpty) return null;
    return folderPath;
  }

  /// 写入本机同步文件夹内文件（创建父目录）；path 为相对路径
  Future<Response> _writeLocalFolderFile(
    String folderId,
    String filePath,
    Request request,
  ) async {
    if (filePath.isEmpty) return Response(400, body: '缺少 path 参数');
    final folderPath = await _resolveFolderRootPath(folderId);
    if (folderPath == null) return Response(404, body: '文件夹未找到');
    final safe = _resolveWritePath(folderPath, filePath);
    if (safe == null) return Response(403, body: '非法路径');

    final builder = await request.read().fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (b, chunk) {
        b.add(chunk);
        return b;
      },
    );
    final data = builder.takeBytes();
    if (data.length > _maxPreviewBytes) {
      return Response(413, body: '文件过大，超过写入上限');
    }
    try {
      final f = File(safe);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(data, flush: true);
      unawaited(_api.triggerFolderScan(folderId));
      debugPrint('[peer-write] 已写入 $safe (${data.length} bytes)');
      return Response.ok(
        '{"ok":true}',
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response(500, body: '写入失败: $e');
    }
  }

  Future<Response> _deleteLocalFolderFile(String folderId, String filePath) async {
    if (filePath.isEmpty) return Response(400, body: '缺少 path 参数');
    final folderPath = await _resolveFolderRootPath(folderId);
    if (folderPath == null) return Response(404, body: '文件夹未找到');
    final safe = _resolveWritePath(folderPath, filePath);
    if (safe == null) return Response(403, body: '非法路径');
    try {
      final f = File(safe);
      if (!await f.exists()) {
        return Response.notFound('不存在');
      }
      await f.delete();
      unawaited(_api.triggerFolderScan(folderId));
      return Response.ok(
        '{"ok":true}',
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response(500, body: '删除失败: $e');
    }
  }

  /// 写路径解析：允许尚不存在的文件，但必须落在 folder root 下
  String? _resolveWritePath(String folderPath, String filePath) {
    try {
      final baseDir = Directory(folderPath);
      if (!baseDir.existsSync()) return null;
      final baseCanon = baseDir.resolveSymbolicLinksSync();
      final rel = filePath
          .replaceAll('\\', '/')
          .replaceAll(RegExp(r'^/+'), '')
          .split('/')
          .where((s) => s.isNotEmpty && s != '.' && s != '..')
          .join(Platform.pathSeparator);
      if (rel.isEmpty || filePath.contains('..')) return null;
      final candidate = '$baseCanon${Platform.pathSeparator}$rel';
      final normalized = File(candidate).absolute.path;
      final prefix = baseCanon.endsWith(Platform.pathSeparator)
          ? baseCanon
          : '$baseCanon${Platform.pathSeparator}';
      if (normalized != baseCanon && !normalized.startsWith(prefix)) {
        return null;
      }
      return normalized;
    } catch (e) {
      debugPrint('[write] resolve 失败: $e');
      return null;
    }
  }

  Future<Response> _serveLocalFilePreview(String folderId, String filePath) async {
    if (filePath.isEmpty) return Response(400, body: '缺少 path 参数');

    // 与目录浏览一致：兼容 URL 编码的 folderId
    var folderPath = await _resolveFolderRootPath(folderId);
    if (folderPath == null || folderPath.isEmpty) {
      var decodedId = folderId;
      try {
        decodedId = Uri.decodeComponent(folderId);
      } catch (_) {}
      for (final f in _api.getFoldersFromConfig()) {
        final fid = f['id']?.toString() ?? '';
        if (fid == folderId || fid == decodedId) {
          folderPath = f['path']?.toString();
          break;
        }
      }
    }
    if (folderPath == null || folderPath.isEmpty) {
      return Response(404, body: '文件夹未找到');
    }

    final safe = _resolvePreviewPath(folderPath, filePath);
    if (safe == null) {
      debugPrint('[preview] 路径非法或越界: folder=$folderPath path=$filePath');
      return Response(403, body: '非法路径');
    }
    final file = File(safe);
    if (!file.existsSync()) {
      debugPrint('[preview] 文件未找到: $safe');
      return Response(404, body: '文件未找到');
    }
    final size = await file.length();
    if (size > _maxPreviewBytes) {
      return Response(
        413,
        body: '文件过大（${(size / (1024 * 1024)).toStringAsFixed(1)} MB），'
            '超过应用内预览上限 200 MB，请使用下载或系统打开',
      );
    }
    final ext = filePath.split('.').last.toLowerCase();
    final stream = file.openRead();
    return Response.ok(
      stream,
      headers: {
        'Content-Type': _mimeType(ext),
        'Content-Length': '$size',
      },
    );
  }

  /// 本机同步目录内图片/视频缩略图（PNG）
  Future<Response> _serveLocalFolderThumbnail(String folderId, String filePath) async {
    if (filePath.isEmpty) return Response(400, body: '缺少 path 参数');

    var folderPath = await _resolveFolderRootPath(folderId);
    if (folderPath == null || folderPath.isEmpty) {
      return Response(404, body: '文件夹未找到');
    }

    final safe = _resolvePreviewPath(folderPath, filePath);
    if (safe == null) {
      return Response(403, body: '非法路径');
    }
    final file = File(safe);
    if (!file.existsSync()) {
      return Response(404, body: '文件未找到');
    }
    if (!FileTypes.isImage(safe) && !FileTypes.isVideo(safe)) {
      return Response(404, body: '非图片或视频');
    }

    final size = await file.length();
    if (FileTypes.isVideo(safe) && size > kMaxThumbnailSourceBytes) {
      return Response(413, body: '视频过大，无法生成缩略图');
    }
    if (FileTypes.isImage(safe) && size > _maxPreviewBytes) {
      return Response(413, body: '图片过大，无法生成缩略图');
    }

    final thumb = await ThumbnailService.instance.thumbnailPath(safe);
    if (thumb == null) {
      return Response(404, body: '无法生成缩略图');
    }
    final bytes = await File(thumb).readAsBytes();
    return Response.ok(
      bytes,
      headers: {'Content-Type': 'image/png'},
    );
  }

  /// 规范化路径并确保落在 folder root 内，防止目录穿越
  String? _resolvePreviewPath(String folderPath, String filePath) {
    try {
      final baseDir = Directory(folderPath);
      if (!baseDir.existsSync()) return null;
      final baseCanon = baseDir.resolveSymbolicLinksSync();
      final rel = filePath
          .replaceAll('\\', '/')
          .replaceAll(RegExp(r'^/+'), '')
          .split('/')
          .where((s) => s.isNotEmpty && s != '.' && s != '..')
          .join('/');
      if (rel.isEmpty || filePath.contains('..')) {
        // 含 .. 直接拒绝；空相对路径也不合法
        if (filePath.contains('..')) return null;
      }
      final candidate = File('$baseCanon${Platform.pathSeparator}$rel');
      if (!candidate.existsSync()) {
        // 仍返回候选路径供 exists 检查（也可能是未同步）
        final parent = candidate.parent;
        if (!parent.existsSync()) return null;
        final parentCanon = parent.resolveSymbolicLinksSync();
        if (!parentCanon.startsWith(baseCanon)) return null;
        return candidate.path;
      }
      final fileCanon = candidate.resolveSymbolicLinksSync();
      if (!fileCanon.startsWith(baseCanon)) return null;
      return fileCanon;
    } catch (e) {
      debugPrint('[preview] resolve 失败: $e');
      return null;
    }
  }

  String _mimeType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'ico':
        return 'image/x-icon';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      case 'mov':
        return 'video/quicktime';
      case 'wmv':
        return 'video/x-ms-wmv';
      case 'flv':
        return 'video/x-flv';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'flac':
        return 'audio/flac';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'wma':
        return 'audio/x-ms-wma';
      case 'm4a':
        return 'audio/mp4';
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
      case 'txt':
      case 'md':
      case 'xml':
      case 'yaml':
      case 'yml':
      case 'ts':
      case 'py':
      case 'java':
      case 'cpp':
      case 'c':
      case 'go':
      case 'rs':
      case 'dart':
      case 'csv':
      case 'log':
        return 'text/plain; charset=utf-8';
      default:
        return 'application/octet-stream';
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
    if (localId != null &&
        !sharedDevices.any((id) => _normDeviceId(id) == _normDeviceId(localId))) {
      sharedDevices = [localId, ...sharedDevices];
    }

    // 获取当前文件夹配置
    final folder = await _api.proxyGet('/rest/config/folders/$folderId');
    if (folder.containsKey('error')) {
      return _json({'code': 1004, 'data': '文件夹不存在'}, status: 404);
    }

    final oldRemoteIds = <String>{};
    for (final d in (folder['devices'] as List? ?? [])) {
      if (d is! Map) continue;
      final id = d['deviceID']?.toString() ?? '';
      if (id.isEmpty || localId == null) continue;
      if (_normDeviceId(id) != _normDeviceId(localId)) {
        oldRemoteIds.add(id);
      }
    }

    folder['devices'] = _folderDeviceList(sharedDevices);
    final result = await _api.proxyPut('/rest/config/folders/$folderId', folder);
    if (result.containsKey('error')) {
      return _json({'code': 1005, 'data': '保存失败: ${result['error']}'}, status: 500);
    }

    // 对端已删除文件夹后再次共享：设备仍在列表中，Syncthing 不会重新发 pending。
    // 对已共享的远程设备做一次「移除再添加」，强制对端重新收到邀请。
    if (localId != null) {
      for (final remoteId in sharedDevices) {
        if (_normDeviceId(remoteId) == _normDeviceId(localId)) continue;
        final wasShared = oldRemoteIds.any((id) => _normDeviceId(id) == _normDeviceId(remoteId));
        if (!wasShared) continue;

        debugPrint('[sharing] 重新向 $remoteId 发送文件夹 $folderId 邀请');
        final withoutRemote = sharedDevices
            .where((id) => _normDeviceId(id) != _normDeviceId(remoteId))
            .toList();
        folder['devices'] = _folderDeviceList(withoutRemote);
        await _api.proxyPut('/rest/config/folders/$folderId', folder);
        await Future.delayed(const Duration(milliseconds: 300));
        folder['devices'] = _folderDeviceList(sharedDevices);
        await _api.proxyPut('/rest/config/folders/$folderId', folder);
      }
    }

    await _api.triggerFolderScan(folderId);
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

  List<Map<String, dynamic>> _localFoldersPayload() {
    return _api.getFoldersFromConfig().map((f) {
      return {
        'id': f['id'] ?? '',
        'label': f['label'] ?? f['id'] ?? '',
        'path': f['path'] ?? '',
        'sharedDevices': <String>[],
        'localFiles': 0,
        'localBytes': 0,
        'globalFiles': 0,
        'globalBytes': 0,
        'status': 'unknown',
        'completion': 0.0,
        'needBytes': 0,
        'needFiles': 0,
        'state': 'unknown',
        'pullErrors': 0,
        'inSyncFiles': 0,
        'inSyncBytes': 0,
        'inBps': 0,
        'outBps': 0,
      };
    }).where((f) => (f['id'] as String).isNotEmpty).toList();
  }

  String _normDeviceId(String id) =>
      id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  Map<String, dynamic> _folderDeviceEntry(String deviceId) => {
        'deviceID': SyncthingApi.formatDeviceId(deviceId),
        'introducedBy': '',
      };

  List<Map<String, dynamic>> _folderDeviceList(List<String> ids) =>
      ids.map(_folderDeviceEntry).toList();

  Future<Map<String, dynamic>> _folderPayload(Map folderMap) async {
    final map = Map<String, dynamic>.from(folderMap);
    final folderId = map['id']?.toString() ?? '';
    final sync = folderId.isNotEmpty
        ? await _api.getFolderSyncSummary(folderId)
        : <String, dynamic>{'status': 'unknown', 'completion': 0.0};
    var label = map['label']?.toString() ?? map['id']?.toString() ?? '';
    final path = map['path']?.toString() ?? '';
    final kind = _kind.getKind(folderId);
    Map<String, dynamic>? appMeta;
    if (kind == 'app' && path.isNotEmpty) {
      final manifest = AppManifest.tryReadFromDirectory(path);
      if (manifest != null) {
        final display = manifest.displayName(fallback: label);
        if (display.isNotEmpty) label = display;
        appMeta = manifest.toJson();
      }
    }
    return {
      'id': folderId,
      'label': label,
      'path': path,
      'type': map['type']?.toString() ?? 'sendreceive',
      'paused': map['paused'] == true,
      'sharedDevices': (map['sharedDevices'] as List?) ?? [],
      'localFiles': sync['localFiles'] ?? 0,
      'localBytes': sync['localBytes'] ?? 0,
      'globalFiles': sync['globalFiles'] ?? 0,
      'globalBytes': sync['globalBytes'] ?? 0,
      'status': sync['status'] ?? 'unknown',
      'completion': sync['completion'] ?? 0.0,
      'needBytes': sync['needBytes'] ?? 0,
      'needFiles': sync['needFiles'] ?? 0,
      'state': sync['state'] ?? 'unknown',
      'pullErrors': sync['pullErrors'] ?? 0,
      'inSyncFiles': sync['inSyncFiles'] ?? 0,
      'inSyncBytes': sync['inSyncBytes'] ?? 0,
      'inBps': sync['inBps'] ?? 0,
      'outBps': sync['outBps'] ?? 0,
      'kind': kind,
      if (appMeta != null) 'appMeta': appMeta,
    };
  }

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
    if (ids.isEmpty) {
      for (final d in _configDevices()) {
        final id = d['deviceID']?.toString() ?? '';
        if (id.isNotEmpty) ids.add(_normDeviceId(id));
      }
    }
    return ids;
  }

  Future<Response> _handleDismissPendingDevice(Request request) async {
    final deviceId = request.url.queryParameters['device'] ?? '';
    if (deviceId.isEmpty) {
      return _json({'code': 1001, 'data': '缺少 device 参数'});
    }
    // ignore=true：对齐 Syncthing「忽略」，写入 remoteIgnoredDevices，避免对端反复连入弹窗
    // 接受设备后的清理只 DELETE pending，勿带 ignore（否则会把刚接受的设备又忽略掉）
    final doIgnore = request.url.queryParameters['ignore'] == '1' ||
        request.url.queryParameters['ignore'] == 'true';
    if (doIgnore) {
      final ignore = await _api.ignoreRemoteDevice(
        deviceId,
        name: request.url.queryParameters['name'] ?? '',
        address: request.url.queryParameters['address'] ?? '',
      );
      if (ignore.containsKey('error')) {
        return _json({'code': 1006, 'data': ignore['error']}, status: 503);
      }
    }
    await _api.proxyDelete(
      '/rest/cluster/pending/devices',
      queryParams: {'device': deviceId},
    );
    return _json({'code': 0, 'data': 'ok'});
  }

  Future<Response> _handlePendingFolders(Request request) async {
    final deviceId = request.url.queryParameters['device'] ?? '';
    final queryParams = deviceId.isNotEmpty ? {'device': deviceId} : null;
    final result = await _api.proxyGet(
      '/rest/cluster/pending/folders',
      queryParams: queryParams,
      silent: true,
    );
    if (result.containsKey('error')) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    final data = result.containsKey('data') ? result['data'] : result;
    if (data is! Map) {
      return _json({'code': 0, 'data': {}});
    }
    return _json({'code': 0, 'data': data});
  }

  Future<Response> _handleDismissPendingFolder(Request request) async {
    final folderId = request.url.queryParameters['folder'] ?? '';
    final deviceId = request.url.queryParameters['device'] ?? '';
    if (folderId.isEmpty || deviceId.isEmpty) {
      return _json({'code': 1001, 'data': '缺少 folder 或 device 参数'});
    }
    final result = await _api.proxyDelete(
      '/rest/cluster/pending/folders',
      queryParams: {'folder': folderId, 'device': deviceId},
    );
    if (result.containsKey('error')) {
      return _json({'code': 1006, 'data': result['error']}, status: 503);
    }
    return _json({'code': 0, 'data': 'ok'});
  }

  Future<Response> _handleAcceptPendingFolder(Request request) async {
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    final folderId = data['folder']?.toString() ?? '';
    final deviceId = data['device']?.toString() ?? '';
    var path = data['path']?.toString() ?? '';
    if (folderId.isEmpty || deviceId.isEmpty) {
      return _json({'code': 1001, 'data': '缺少 folder 或 device 参数'}, status: 400);
    }

    final pendingResult = await _api.proxyGet('/rest/cluster/pending/folders', silent: true);
    if (pendingResult.containsKey('error')) {
      return _json({'code': 1006, 'data': 'Syncthing 未运行'}, status: 503);
    }
    final pendingRaw = pendingResult.containsKey('data') ? pendingResult['data'] : pendingResult;
    var label = folderId;
    if (pendingRaw is Map && pendingRaw[folderId] is Map) {
      final offeredBy = (pendingRaw[folderId] as Map)['offeredBy'];
      if (offeredBy is Map) {
        for (final entry in offeredBy.entries) {
          if (_normDeviceId(entry.key.toString()) == _normDeviceId(deviceId)) {
            final info = entry.value;
            if (info is Map && info['label'] != null) {
              label = info['label'].toString();
            }
            break;
          }
        }
      }
    }

    if (path.isEmpty) {
      path = await defaultSyncFolderPath(folderId);
    }
    await Directory(path).create(recursive: true);
    await _preCreateFolderMarker(path);

    final localId = await _api.getLocalDeviceId();
    if (localId == null) {
      return _json({'code': 1006, 'data': '无法获取本机设备 ID'}, status: 503);
    }

    final existing = await _api.proxyGet('/rest/config/folders/$folderId', silent: true);
    if (existing.containsKey('error')) {
      final defaults = await _api.proxyGet('/rest/config/defaults/folder', silent: true);
      final folderCfg = Map<String, dynamic>.from(
        defaults.containsKey('data') ? defaults['data'] as Map : defaults,
      );
      folderCfg['id'] = folderId;
      folderCfg['label'] = label;
      folderCfg['path'] = path;
      folderCfg['type'] ??= 'sendreceive';
      folderCfg['paused'] = false;
      folderCfg['ignorePerms'] = true;
      folderCfg['devices'] = [
        _folderDeviceEntry(localId),
        _folderDeviceEntry(deviceId),
      ];
      final created = await _api.proxyPost('/rest/config/folders', folderCfg);
      if (created.containsKey('error')) {
        return _json({'code': 1005, 'data': '创建文件夹失败: ${created['error']}'}, status: 500);
      }
    } else {
      final folderCfg = Map<String, dynamic>.from(existing);
      final devices = (folderCfg['devices'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final hasDevice = devices.any((d) => _normDeviceId(d['deviceID']?.toString() ?? '') == _normDeviceId(deviceId));
      final hasLocal = devices.any((d) => _normDeviceId(d['deviceID']?.toString() ?? '') == _normDeviceId(localId));
      if (!hasLocal) devices.insert(0, _folderDeviceEntry(localId));
      if (!hasDevice) devices.add(_folderDeviceEntry(deviceId));
      folderCfg['devices'] = devices;
      folderCfg['paused'] = false;
      folderCfg['ignorePerms'] = true;
      if (path.isNotEmpty) folderCfg['path'] = path;
      final updated = await _api.proxyPut('/rest/config/folders/$folderId', folderCfg);
      if (updated.containsKey('error')) {
        return _json({'code': 1005, 'data': '更新文件夹失败: ${updated['error']}'}, status: 500);
      }
    }

    await _api.triggerFolderScan(folderId);
    await _api.proxyDelete(
      '/rest/cluster/pending/folders',
      queryParams: {'folder': folderId, 'device': deviceId},
    );
    return _json({'code': 0, 'data': {'message': '已接受共享文件夹', 'folderId': folderId, 'label': label, 'path': path}});
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

    final result = await _api.removeAndIgnoreDevice(deviceId);
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
    final kind = (data['kind']?.toString() == 'app') ? 'app' : 'folder';
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
      'filesystemType': 'basic', 'rescanIntervalS': 3600, 'ignorePerms': true,
      'autoNormalize': true, 'paused': false,
      'devices': [],
    };
    final localId = await _api.getLocalDeviceId();
    if (localId != null) {
      folderData['devices'] = _folderDeviceList([localId]);
    }
    final result = await _api.proxyPost('/rest/config/folders', folderData);
    if (result.containsKey('error')) {
      return _json({'code': 1003, 'data': '添加文件夹失败: ${result['error']}'}, status: 500);
    }
    await _kind.setKind(id, kind);
    await _api.triggerFolderScan(id);
    return _json({'code': 0, 'data': {'id': id, 'label': label, 'path': path, 'kind': kind}});
  }

  Future<Response> _handleDeleteFolder(Request request, String deviceId, String folderId) async {
    final result = await _api.proxyDelete('/rest/config/folders/$folderId');
    if (result.containsKey('error')) {
      return _json({'code': 1003, 'data': '删除文件夹失败: ${result['error']}'}, status: 500);
    }
    await _kind.remove(folderId);
    return _json({'code': 0, 'data': {'message': '文件夹已删除'}});
  }

  Future<Response> _handleSetFolderKind(Request request, String folderId) async {
    final id = _decodeFolderId(folderId);
    final body = utf8.decode(await request.read().expand((e) => e).toList());
    final data = json.decode(body) as Map<String, dynamic>;
    final kind = data['kind']?.toString() == 'app' ? 'app' : 'folder';
    await _kind.setKind(id, kind);
    return _json({'code': 0, 'data': {'id': id, 'kind': kind}});
  }

  Future<Response> _handleHealth(Request request) async =>
      _json({'status': 'ok', 'service': 'datakeep-api'});
}
