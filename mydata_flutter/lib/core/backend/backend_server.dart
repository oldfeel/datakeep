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
import '../../shared/utils/sync_folder_paths.dart';

class BackendServer {
  final SyncthingApi _api = SyncthingApi();
  final FolderAclStore _acl = FolderAclStore();
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

    final router = Router()
      ..get('/api/devices', _handleDevices)
      ..get('/api/device/<deviceId>/folders', _handleDeviceFolders)
      ..get('/api/device/<deviceId>/folder/<folderId>/files', _handleDeviceFolderFiles)
      ..post('/api/device/local/folders', _handleCreateFolder)
      ..delete('/api/device/<deviceId>/folders/<folderId>', _handleDeleteFolder)
      ..delete('/api/device/<deviceId>', _handleRemoveDevice)
      ..get('/api/deviceid', _handleDeviceId)
      ..get('/api/folder/<folderId>', _handleFolderFiles)
      ..get('/api/folder/<folderId>/status', _handleFolderStatus)
      ..get('/api/folder/<folderId>/acl', _handleGetFolderAcl)
      ..post('/api/folder/<folderId>/acl', _handleSetFolderAcl)
      ..post('/api/folder/<folderId>/fix-path', _handleFixFolderPath)
      ..get('/api/folder/<folderId>/preview', _handleFilePreview)
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

  /// 本机文件夹列表（含同步统计）
  Future<List<Map<String, dynamic>>> _buildLocalFoldersPayload() async {
    final localId = await _api.getLocalDeviceId();
    final result = await _api.proxyGet('/rest/config/folders', silent: true);
    if (result.containsKey('error')) {
      return _localFoldersPayload();
    }

    final rawList = result['data'] as List? ?? [];
    if (rawList.isEmpty) return _localFoldersPayload();

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
    return folders;
  }

  /// 经局域网 HTTPS 拉取对端真实文件夹列表
  Future<Response> _handleRemoteDeviceFolders(String deviceId) async {
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
        'data': peer['error']?.toString() ?? '对端 MyData 不可达',
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
    final callerId = request.headers['x-mydata-device-id'] ?? '';
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
    final callerId = request.headers['x-mydata-device-id'] ?? '';
    final access = await _resolveAccessForCaller(folderId, callerId);
    if (!access.isPeerVisible) {
      return _json({'code': 1403, 'data': '无权限访问该文件夹'}, status: 403);
    }
    return _browseFolderFiles(folderId, request.url.queryParameters['path'] ?? '');
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

  Future<Response> _proxyPeerFolderFiles(
    String deviceId,
    String folderId,
    String path,
  ) async {
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

  /// 校验 X-MyData-Device-ID 是否为已配对设备（或本机）
  Future<Response?> _authorizePeer(Request request) async {
    // shelf 将 header 名规范为小写
    final callerId = request.headers['x-mydata-device-id'] ?? '';
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
    final sync = await _api.getFolderSyncSummary(folderId);
    if (sync['status'] == 'unknown') {
      return _json({'code': 1005, 'data': '无法获取文件夹状态'}, status: 503);
    }
    final folderPath = await _api.getFolderPath(folderId);
    if (folderPath != null) {
      sync['currentPath'] = folderPath;
    }
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
    final filePath = request.url.queryParameters['path'] ?? '';
    if (filePath.isEmpty) return Response(400, body: '缺少 path 参数');
    final folderPath = await _api.getFolderPath(folderId);
    if (folderPath == null || folderPath.isEmpty) {
      return Response(404, body: '文件夹未找到');
    }
    final fullPath = '$folderPath/$filePath';
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
    return {
      'id': folderId,
      'label': map['label'] ?? map['id'] ?? '',
      'path': map['path'] ?? '',
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
    final result = await _api.proxyDelete('/rest/cluster/pending/devices',
        queryParams: {'device': deviceId});
    if (result.containsKey('error')) {
      return _json({'code': 1006, 'data': result['error']}, status: 503);
    }
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
    await _api.triggerFolderScan(id);
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
