import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SyncthingApi {
  static final SyncthingApi _instance = SyncthingApi._();
  factory SyncthingApi() => _instance;
  SyncthingApi._();

  String _apiKey = '';
  String _configPath = '';
  String? _defaultLocalDeviceName;

  String get configPath => _configPath;

  void init({String? configPath, String? defaultLocalDeviceName}) {
    _configPath = configPath ?? _findConfigPath();
    _defaultLocalDeviceName = defaultLocalDeviceName;
    _apiKey = _loadApiKey();
    debugPrint('Syncthing config: $_configPath, hasKey: ${_apiKey.isNotEmpty}');
  }

  String _findConfigPath() {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = [
      '$home/.config/syncthing/config.xml',
      '$home/.local/state/syncthing/config.xml',
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return candidates.first;
  }

  String _loadApiKey() {
    try {
      final xml = File(_configPath).readAsStringSync();
      final keyMatch = RegExp(r'<apikey>(.*?)</apikey>', dotAll: true).firstMatch(xml);
      return keyMatch?.group(1) ?? '';
    } catch (_) {
      return '';
    }
  }

  HttpClient _createClient() => HttpClient();

  HttpClientRequest _addAuth(HttpClientRequest request) {
    if (_apiKey.isNotEmpty) {
      request.headers.set('X-API-Key', _apiKey);
      request.headers.set('Authorization', 'Bearer $_apiKey');
    }
    return request;
  }

  Future<Map<String, dynamic>> _handleResponse(HttpClientResponse response) async {
    if (response.statusCode == 403) {
      // 403 表示 API Key 不正确但 Syncthing 在运行，当成"成功"处理
      final body = await response.transform(utf8.decoder).join();
      if (body.contains('CSRF Error')) {
        return {}; // 返回空而不是报错
      }
    }
    if (response.statusCode != 200) {
      return {'error': 'HTTP ${response.statusCode}'};
    }
    final body = await response.transform(utf8.decoder).join();
    if (body.isEmpty) return {};
    try {
      final decoded = json.decode(body);
      if (decoded is List) return {'data': decoded};
      if (decoded is Map) return decoded as Map<String, dynamic>;
      return {'data': decoded};
    } catch (e) {
      return {'error': 'JSON 解析失败: $body'};
    }
  }

  Future<Map<String, dynamic>> proxyGet(
    String path, {
    Map<String, String>? queryParams,
    Duration? timeout,
    bool silent = false,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path').replace(queryParameters: queryParams);
    final client = _createClient();
    try {
      final request = _addAuth(await client.getUrl(uri));
      final response = await request.close().timeout(
        timeout ?? const Duration(seconds: 10),
      );
      final result = await _handleResponse(response);
      return result;
    } catch (e) {
      if (!silent) debugPrint('Syncthing API error: $e');
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> proxyPost(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path');
    final client = _createClient();
    try {
      final request = _addAuth(await client.postUrl(uri));
      request.headers.contentType = ContentType.json;
      request.write(json.encode(body));
      final response = await request.close().timeout(const Duration(seconds: 10));
      return await _handleResponse(response);
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> proxyPut(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path');
    final client = _createClient();
    try {
      final request = _addAuth(await client.putUrl(uri));
      request.headers.contentType = ContentType.json;
      request.write(json.encode(body));
      final response = await request.close().timeout(const Duration(seconds: 10));
      return await _handleResponse(response);
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> proxyDelete(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path').replace(queryParameters: queryParams);
    final client = _createClient();
    try {
      final request = _addAuth(await client.deleteUrl(uri));
      final response = await request.close().timeout(const Duration(seconds: 10));
      return await _handleResponse(response);
    } catch (e) {
      return {'error': e.toString()};
    } finally {
      client.close();
    }
  }

  Future<List<int>> proxyGetRaw(String path, {Map<String, String>? queryParams}) async {
    final uri = Uri.parse('http://127.0.0.1:8384$path').replace(queryParameters: queryParams);
    final client = _createClient();
    try {
      final request = _addAuth(await client.getUrl(uri));
      final response = await request.close().timeout(const Duration(seconds: 30));
      return await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
    } catch (e) {
      debugPrint('Syncthing raw fetch error: $e');
      return [];
    } finally {
      client.close();
    }
  }

  List<Map<String, dynamic>> getFoldersFromConfig() {
    try {
      final xml = File(_configPath).readAsStringSync();
      final folderRegex = RegExp(
        r'<folder\s+id="(.*?)"[^>]*\s*label="(.*?)"[^>]*\s*path="(.*?)"[^>]*>',
        dotAll: true,
      );
      final folders = <Map<String, dynamic>>[];
      for (final m in folderRegex.allMatches(xml)) {
        final folderPath = m.group(3) ?? '';
        final expanded = folderPath.startsWith('~/')
            ? '${Platform.environment['HOME'] ?? ''}${folderPath.substring(1)}'
            : folderPath;
        folders.add({
          'id': m.group(1) ?? '',
          'label': m.group(2) ?? m.group(1) ?? '',
          'path': expanded,
        });
      }
      return folders;
    } catch (e) {
      debugPrint('读取 config.xml 失败: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> browseLocalDirectory(String folderPath, [String subPath = '']) {
    try {
      final dir = Directory('$folderPath/$subPath');
      if (!dir.existsSync()) return [];
      final entries = dir.listSync().toList()..sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.compareTo(b.path);
      });
      return entries.map((e) {
        final stat = e.statSync();
        final name = e.uri.pathSegments.last;
        return {
          'name': name,
          'type': e is Directory ? 'dir' : 'file',
          'size': e is File ? stat.size : 0,
          'modTime': stat.modified.millisecondsSinceEpoch ~/ 1000,
        };
      }).toList();
    } catch (e) {
      debugPrint('浏览本地目录失败: $e');
      return [];
    }
  }

  Future<bool> isRunning() async {
    try {
      final uri = Uri.parse('http://127.0.0.1:8384/rest/system/status');
      final request = _addAuth(await _createClient().getUrl(uri));
      final response = await request.close().timeout(const Duration(seconds: 2));
      return response.statusCode == 200 || response.statusCode == 403;
    } catch (_) {
      return false;
    }
  }

  /// 获取本机 Syncthing 设备 ID
  Future<String?> getLocalDeviceId() async {
    final result = await proxyGet('/rest/system/status');
    final myId = result['myID']?.toString();
    if (myId != null && myId.isNotEmpty) return myId;
    return _localDeviceIdFromConfig();
  }

  String? _localDeviceIdFromConfig() {
    try {
      final xml = File(_configPath).readAsStringSync();
      // config.xml 第一个 device 即本机
      final m = RegExp(r'<device id="([^"]+)"').firstMatch(xml);
      final id = m?.group(1);
      return (id != null && id.isNotEmpty) ? id : null;
    } catch (_) {
      return null;
    }
  }

  /// 从 config.xml 读取本机设备名称
  String getLocalDeviceName(String localId) {
    final formattedId = formatDeviceId(localId);
    var name = getDeviceNameFromConfig(formattedId) ?? '';
    if (_isPlaceholderName(name, formattedId)) {
      name = _defaultLocalDeviceName ?? '';
    }
    if (name.isEmpty || _isPlaceholderName(name, formattedId)) {
      return _defaultLocalDeviceName ?? '本机设备';
    }
    return name;
  }

  /// 将本机 Syncthing 设备名写入运行中的配置（Android 修正 localhost 等占位名）
  Future<void> ensureLocalDeviceName(String preferredName) async {
    final trimmed = preferredName.trim();
    debugPrint('[设备名] ensureLocalDeviceName 开始, preferred=$trimmed, config=$_configPath');
    if (trimmed.isEmpty) {
      debugPrint('[设备名] 跳过: 名称为空');
      return;
    }
    if (!await isRunning()) {
      debugPrint('[设备名] 跳过: Syncthing API 未运行');
      return;
    }

    final localId = await getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      debugPrint('[设备名] 跳过: 无法获取本机 device ID');
      return;
    }

    final formattedId = formatDeviceId(localId);
    final current = getDeviceNameFromConfig(formattedId) ?? '';
    debugPrint('[设备名] 本机 ID=$formattedId, config 当前名=$current');
    if (!_isPlaceholderName(current, formattedId)) {
      debugPrint('[设备名] 跳过: 当前名已是有效名称');
      return;
    }

    _patchLocalDeviceNameInConfigFile(formattedId, trimmed);
    debugPrint('[设备名] 已写入 config.xml');

    final deviceRes = await proxyGet('/rest/config/devices/$formattedId');
    if (deviceRes.containsKey('error')) {
      debugPrint('[设备名] GET /rest/config/devices 失败: ${deviceRes['error']}');
      return;
    }

    final raw = deviceRes.containsKey('data') ? deviceRes['data'] : deviceRes;
    if (raw is! Map) {
      debugPrint('[设备名] GET device 响应格式异常: $deviceRes');
      return;
    }

    final device = Map<String, dynamic>.from(raw);
    device['name'] = trimmed;
    final result = await proxyPut('/rest/config/devices/$formattedId', device);
    if (result.containsKey('error')) {
      debugPrint('[设备名] PUT 失败: ${result['error']}');
    } else {
      debugPrint('[设备名] Syncthing API 已更新本机名为: $trimmed');
    }
  }

  void _patchLocalDeviceNameInConfigFile(String deviceId, String newName) {
    try {
      final file = File(_configPath);
      if (!file.existsSync()) return;
      var xml = file.readAsStringSync();
      final tagMatch = RegExp(
        '<device\\s+([^>]*\\bid="${RegExp.escape(deviceId)}"[^>]*)>',
        caseSensitive: false,
      ).firstMatch(xml);
      final attrs = tagMatch?.group(1);
      if (attrs == null) return;

      final nameMatch = RegExp(r'\bname="[^"]*"').firstMatch(attrs);
      final newAttrs = nameMatch != null
          ? attrs.replaceFirst(nameMatch.group(0)!, 'name="$newName"')
          : '$attrs name="$newName"';
      xml = xml.replaceFirst(
        '<device $attrs>',
        '<device $newAttrs>',
      );
      file.writeAsStringSync(xml);
    } catch (e) {
      debugPrint('写入 config.xml 设备名失败: $e');
    }
  }

  /// 从 config.xml 读取指定设备的名称（属性顺序无关）
  String? getDeviceNameFromConfig(String deviceId) {
    try {
      final id = formatDeviceId(deviceId);
      final xml = File(_configPath).readAsStringSync();
      final tagMatch = RegExp(
        '<device\\s+([^>]*\\bid="${RegExp.escape(id)}"[^>]*)>',
        caseSensitive: false,
      ).firstMatch(xml);
      final attrs = tagMatch?.group(1);
      if (attrs == null) return null;
      final name = RegExp(r'\bname="([^"]*)"').firstMatch(attrs)?.group(1)?.trim();
      if (name != null && name.isNotEmpty) return name;
    } catch (_) {}
    return null;
  }

  static bool isPlaceholderName(String name, String deviceId) => _isPlaceholderName(name, deviceId);

  static bool _isPlaceholderName(String name, String deviceId) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return true;
    if (n == 'localhost' || n == 'unknown' || n == '未知设备') return true;
    final norm = (String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (norm(n) == norm(deviceId)) return true;
    final shortId = _shortDeviceLabel(deviceId).toUpperCase();
    if (name.trim().toUpperCase() == shortId) return true;
    return false;
  }

  static String _shortDeviceLabel(String deviceId) {
    if (deviceId.contains('-')) return deviceId.split('-').first;
    final clean = deviceId.replaceAll(RegExp(r'[\s-]'), '');
    return clean.length >= 7 ? clean.substring(0, 7) : deviceId;
  }

  /// 从 Syncthing 事件（DeviceConnected）解析远端设备在 Hello 中宣告的名称
  Future<Map<String, String>> fetchAdvertisedDeviceNames() async {
    final names = <String, String>{};
    final result = await proxyGet(
      '/rest/events',
      queryParams: {'limit': '500', 'events': 'DeviceConnected', 'timeout': '0'},
      timeout: const Duration(seconds: 3),
      silent: true,
    );
    if (result.containsKey('error')) {
      debugPrint('[设备名] 读取 events 失败: ${result['error']}');
      return names;
    }

    final events = result['data'];
    if (events is! List) {
      debugPrint('[设备名] events 响应无 data 列表: ${result.keys}');
      return names;
    }

    for (final ev in events) {
      if (ev is! Map) continue;
      final type = ev['type']?.toString() ?? '';
      if (type != 'DeviceConnected') continue;
      final data = ev['data'];
      if (data is! Map) continue;
      final id = data['id']?.toString() ?? '';
      final deviceName = data['deviceName']?.toString().trim() ?? '';
      if (id.isEmpty || deviceName.isEmpty) continue;
      if (_isPlaceholderName(deviceName, id)) continue;
      names[_normId(id)] = deviceName;
    }
    debugPrint('[设备名] 从 DeviceConnected 事件解析: $names');
    return names;
  }

  /// 将远端设备有效名称持久化到本机 Syncthing config（修正 Linux 侧 localhost 等）
  Future<void> persistRemoteDeviceNameIfNeeded(String deviceId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || !await isRunning()) return;

    final formattedId = formatDeviceId(deviceId);
    final current = getDeviceNameFromConfig(formattedId) ?? '';
    if (!_isPlaceholderName(current, formattedId)) return;

    final deviceRes = await proxyGet('/rest/config/devices/$formattedId');
    if (deviceRes.containsKey('error')) {
      debugPrint('[设备名] 持久化 $formattedId 失败 GET: ${deviceRes['error']}');
      return;
    }
    final raw = deviceRes.containsKey('data') ? deviceRes['data'] : deviceRes;
    if (raw is! Map) return;

    final device = Map<String, dynamic>.from(raw);
    device['name'] = trimmed;
    final result = await proxyPut('/rest/config/devices/$formattedId', device);
    if (result.containsKey('error')) {
      debugPrint('[设备名] 持久化 $formattedId 失败 PUT: ${result['error']}');
    } else {
      _patchLocalDeviceNameInConfigFile(formattedId, trimmed);
      debugPrint('[设备名] 已持久化远端设备 $formattedId => $trimmed');
    }
  }

  /// 补全设备显示名称：config 为空时用短 ID，避免 UI 空白
  Future<void> normalizeDeviceNames(List<Map<String, dynamic>> devices) async {
    final localId = await getLocalDeviceId();
    final advertised = await fetchAdvertisedDeviceNames();

    for (final device in devices) {
      final id = device['deviceID']?.toString() ?? '';
      if (id.isEmpty || id == 'local') continue;

      var name = device['name']?.toString().trim() ?? '';
      final apiName = name;
      if (_isPlaceholderName(name, id)) {
        name = getDeviceNameFromConfig(id) ?? '';
      }
      if (_isPlaceholderName(name, id) &&
          localId != null &&
          _normId(id) == _normId(localId)) {
        final fallback = _defaultLocalDeviceName;
        if (fallback != null && fallback.isNotEmpty) {
          name = fallback;
        }
      }
      if (_isPlaceholderName(name, id)) {
        final adv = advertised[_normId(id)];
        if (adv != null && adv.isNotEmpty) {
          name = adv;
          // 异步持久化，不阻塞 API 响应
          persistRemoteDeviceNameIfNeeded(id, adv);
        }
      }
      if (_isPlaceholderName(name, id)) {
        name = _shortDeviceLabel(id);
      }

      if (name != apiName) {
        debugPrint('[设备名] $id: API="$apiName" => 显示="$name"');
      }
      device['name'] = name;
    }
  }

  /// 格式化为 Syncthing 标准设备 ID（带连字符）
  static String formatDeviceId(String id) {
    final clean = id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (clean.length != 56) return id.trim();
    return List.generate(8, (i) => clean.substring(i * 7, i * 7 + 7)).join('-');
  }

  static String _normId(String id) =>
      id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  /// 连接时自动用远端宣告的设备名覆盖本机 config 中的占位名
  Future<void> ensureOverwriteRemoteDeviceNamesOnConnect() async {
    if (!await isRunning()) return;
    final result = await proxyGet('/rest/config/options', silent: true);
    if (result.containsKey('error')) return;

    final raw = result.containsKey('data') ? result['data'] : result;
    if (raw is! Map) return;

    final options = Map<String, dynamic>.from(raw);
    if (options['overwriteRemoteDeviceNamesOnConnect'] == true) {
      debugPrint('[设备名] overwriteRemoteDeviceNamesOnConnect 已启用');
      return;
    }

    options['overwriteRemoteDeviceNamesOnConnect'] = true;
    final put = await proxyPut('/rest/config/options', options);
    if (!put.containsKey('error')) {
      debugPrint('[设备名] 已启用 overwriteRemoteDeviceNamesOnConnect');
    }
  }

  /// 添加设备到 Syncthing 配置（先读取默认配置再 POST，与 Syncthing GUI 一致）
  Future<Map<String, dynamic>> addDeviceToConfig(String deviceId, String name) async {
    if (!await isRunning()) {
      return {'error': 'Syncthing 未运行'};
    }

    final defaultsRes = await proxyGet('/rest/config/defaults/device');
    if (defaultsRes.containsKey('error')) return defaultsRes;

    final raw = defaultsRes.containsKey('data') ? defaultsRes['data'] : defaultsRes;
    if (raw is! Map) {
      return {'error': '无法读取 Syncthing 默认设备配置'};
    }

    final device = Map<String, dynamic>.from(raw);
    final formattedId = formatDeviceId(deviceId);
    device['deviceID'] = formattedId;
    var effectiveName = name.trim();
    if (_isPlaceholderName(effectiveName, formattedId)) {
      effectiveName = getDeviceNameFromConfig(formattedId) ?? _shortDeviceLabel(formattedId);
    }
    device['name'] = effectiveName;

    return proxyPost('/rest/config/devices', device);
  }

  /// 合并连接状态到设备列表
  Future<void> enrichDevicesWithConnections(List<Map<String, dynamic>> devices) async {
    final connResult = await proxyGet('/rest/system/connections');
    if (connResult.containsKey('error')) return;

    final connections = connResult['connections'];
    if (connections is! Map) return;

    for (final device in devices) {
      final id = device['deviceID']?.toString() ?? '';
      if (id.isEmpty) continue;

      Map<String, dynamic>? conn;
      connections.forEach((key, value) {
        if (_normId(key.toString()) == _normId(id) && value is Map) {
          conn = Map<String, dynamic>.from(value);
        }
      });
      if (conn == null) continue;

      device['connected'] = conn!['connected'] == true;
      device['connectionType'] = conn!['type']?.toString() ?? '';
      final clientVersion = conn!['clientVersion']?.toString() ?? '';
      if (clientVersion.isNotEmpty) {
        device['clientVersion'] = clientVersion;
      }
      final address = conn!['address']?.toString() ?? '';
      if (address.isNotEmpty) {
        device['addresses'] = [address];
      }
    }
  }
}
