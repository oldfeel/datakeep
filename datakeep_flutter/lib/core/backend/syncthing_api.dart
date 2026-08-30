import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../shared/utils/local_http_client.dart';
import '../services/syncthing_lifecycle.dart';

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

  /// config.xml 由 Syncthing 引擎异步创建后需重新读取 apikey（Android 冷启动）
  void reloadConfig() {
    if (_configPath.isEmpty) {
      _configPath = _findConfigPath();
    }
    _apiKey = _loadApiKey();
    debugPrint('Syncthing config reloaded, hasKey: ${_apiKey.isNotEmpty}');
  }

  String _findConfigPath() {
    final home = _userHomeDir();
    final sep = Platform.pathSeparator;
    final candidates = <String>[
      if (Platform.isWindows) ...[
        // Syncthing 官方默认：%LOCALAPPDATA%\Syncthing
        if (_envNonEmpty('LOCALAPPDATA'))
          '${Platform.environment['LOCALAPPDATA']!.trim()}${sep}Syncthing${sep}config.xml',
        if (home.isNotEmpty)
          '$home${sep}AppData${sep}Local${sep}Syncthing${sep}config.xml',
      ],
      if (Platform.isMacOS && home.isNotEmpty)
        '$home/Library/Application Support/Syncthing/config.xml',
      if (!Platform.isWindows && home.isNotEmpty) ...[
        '$home/.config/syncthing/config.xml',
        '$home/.local/state/syncthing/config.xml',
      ],
    ];
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return candidates.isNotEmpty ? candidates.first : '';
  }

  /// Windows 优先 USERPROFILE / LOCALAPPDATA，忽略 Git Bash 等假 HOME（如 "/"）。
  static String _userHomeDir() {
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE']?.trim();
      if (profile != null && profile.isNotEmpty) return profile;
      final home = Platform.environment['HOME']?.trim();
      if (home != null && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(home)) {
        return home;
      }
      return '';
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) return home;
    return Platform.environment['USERPROFILE']?.trim() ?? '';
  }

  static bool _envNonEmpty(String key) {
    final v = Platform.environment[key]?.trim();
    return v != null && v.isNotEmpty;
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

  HttpClient _createClient() {
    final client = HttpClient();
    configureLocalHttpClient(client);
    return client;
  }

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

  /// 代理层失败（区别于 Syncthing 业务 JSON 自带的空 `error: ""` 字段）
  bool _isProxyError(Map<String, dynamic> result) {
    final err = result['error'];
    if (err == null || err.toString().isEmpty) return false;
    // /rest/db/status 成功响应含 state/localFiles，同时可能有 error:""
    if (result.containsKey('state') ||
        result.containsKey('localFiles') ||
        result.containsKey('data') ||
        result.containsKey('myID')) {
      return false;
    }
    return true;
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
      final tagRegex = RegExp(r'<folder\s+([^>/]+)/?>');
      final folders = <Map<String, dynamic>>[];
      for (final m in tagRegex.allMatches(xml)) {
        final attrs = m.group(1) ?? '';
        final id = RegExp(r'\bid="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
        if (id.isEmpty) continue;
        var path = RegExp(r'\bpath="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
        final label = RegExp(r'\blabel="([^"]*)"').firstMatch(attrs)?.group(1) ?? id;
        if (path.startsWith('~/')) {
          path = '${Platform.environment['HOME'] ?? ''}${path.substring(1)}';
        }
        if (path.isEmpty) continue;
        folders.add({'id': id, 'label': label, 'path': path});
      }
      return folders;
    } catch (e) {
      debugPrint('读取 config.xml 失败: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> browseLocalDirectory(String folderPath, [String subPath = '']) {
    try {
      final dir = Directory(
        subPath.isEmpty ? folderPath : '$folderPath/$subPath',
      );
      if (!dir.existsSync()) return [];
      final entries = dir.listSync().toList()..sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.compareTo(b.path);
      });
      final result = entries
          .where((e) {
            final name = e.path.split(Platform.pathSeparator).last;
            return name.isNotEmpty && name != '.';
          })
          .map((e) {
            final stat = e.statSync();
            final name = e.path.split(Platform.pathSeparator).last;
            final isDir = e is Directory;
            // 子目录含 app.json 即视为应用包（与 kind=app 注册无关）
            final isApp = isDir &&
                File('${e.path}${Platform.pathSeparator}app.json').existsSync();
            return {
              'name': name,
              'type': isDir ? 'dir' : 'file',
              'size': e is File ? stat.size : 0,
              'modTime': stat.modified.millisecondsSinceEpoch ~/ 1000,
              'ctime': stat.changed.millisecondsSinceEpoch ~/ 1000,
              if (isApp) 'isApp': true,
            };
          }).toList();
      return result;
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

  String? _cachedLocalDeviceId;

  /// 获取本机 Syncthing 设备 ID（成功后缓存；引擎短暂不可用时仍可用）
  Future<String?> getLocalDeviceId() async {
    final result = await proxyGet('/rest/system/status', silent: true);
    final myId = result['myID']?.toString();
    if (myId != null && myId.isNotEmpty) {
      _cachedLocalDeviceId = myId;
      return myId;
    }
    if (_cachedLocalDeviceId != null && _cachedLocalDeviceId!.isNotEmpty) {
      return _cachedLocalDeviceId;
    }
    final fromConfig = _localDeviceIdFromConfig();
    if (fromConfig != null && fromConfig.isNotEmpty) {
      _cachedLocalDeviceId = fromConfig;
    }
    return fromConfig;
  }

  String? _localDeviceIdFromConfig() {
    try {
      final xml = File(_configPath).readAsStringSync();
      // 顶层设备块通常含 name= 与 compression=；folder 内共享成员没有 compression
      final full = RegExp(
        r'<device id="([^"]+)"[^>]*compression=',
      ).firstMatch(xml);
      if (full != null) {
        final id = full.group(1);
        if (id != null && id.isNotEmpty) return id;
      }
      final withName = RegExp(r'<device id="([^"]+)"\s+name="').firstMatch(xml);
      final id = withName?.group(1);
      if (id != null && id.isNotEmpty) return id;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 优先从 REST 读取设备名，回退 config.xml（Syncthing 保存后文件里 name 可能为空）
  Future<String> getEffectiveDeviceName(String deviceId) async {
    final formattedId = formatDeviceId(deviceId);
    final rest = await getDeviceNameFromRest(formattedId);
    if (rest != null && !_isPlaceholderName(rest, formattedId)) return rest;
    return getDeviceNameFromConfig(formattedId) ?? '';
  }

  Future<String?> getDeviceNameFromRest(String deviceId) async {
    final formattedId = formatDeviceId(deviceId);
    final result = await proxyGet('/rest/config/devices/$formattedId', silent: true);
    if (result.containsKey('error')) return null;
    final raw = result.containsKey('data') ? result['data'] : result;
    if (raw is! Map) return null;
    final name = raw['name']?.toString().trim();
    return (name != null && name.isNotEmpty) ? name : null;
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

  /// 将本机 Syncthing 设备名写入配置（运行中仅 REST，停止时才写 config.xml）
  Future<void> ensureLocalDeviceName(String preferredName) async {
    final trimmed = preferredName.trim();
    debugPrint('[设备名] ensureLocalDeviceName 开始, preferred=$trimmed, config=$_configPath');
    if (trimmed.isEmpty) {
      debugPrint('[设备名] 跳过: 名称为空');
      return;
    }

    final localId = await getLocalDeviceId();
    if (localId == null || localId.isEmpty) {
      debugPrint('[设备名] 跳过: 无法获取本机 device ID');
      return;
    }

    final formattedId = formatDeviceId(localId);
    final restName = await getDeviceNameFromRest(formattedId);
    if (restName != null && !_isPlaceholderName(restName, formattedId)) {
      debugPrint('[设备名] 跳过: REST 已有有效名称 $restName');
      return;
    }

    final current = getDeviceNameFromConfig(formattedId) ?? '';
    debugPrint('[设备名] 本机 ID=$formattedId, config 当前名=$current');
    if (!_isPlaceholderName(current, formattedId)) {
      debugPrint('[设备名] 跳过: config 已是有效名称');
      return;
    }

    final running = await isRunning();
    if (!running) {
      // Android gomobile：引擎停止/重启窗口内写 config.xml 会与 native 竞态，由 Kotlin 启动前写入
      if (Platform.isAndroid) {
        debugPrint('[设备名] Android 引擎未运行，跳过 config.xml 写入');
        return;
      }
      _patchLocalDeviceNameInConfigFile(formattedId, trimmed);
      debugPrint('[设备名] Syncthing 未运行，已写入 config.xml');
      return;
    }

    final deviceRes = await proxyGet('/rest/config/devices/$formattedId', silent: true);
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

  /// 从 config.xml 解析顶层设备（必须带 name=，避免把文件夹里的共享 `<device>` 算进去）
  List<Map<String, dynamic>> parseDevicesFromConfig() {
    try {
      if (_configPath.isEmpty || !File(_configPath).existsSync()) return [];
      final xml = File(_configPath).readAsStringSync();
      final tagRegex = RegExp(r'<device\s+([^>/]+)/?>', caseSensitive: false);
      final devices = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final m in tagRegex.allMatches(xml)) {
        final attrs = m.group(1) ?? '';
        if (!RegExp(r'\bname=').hasMatch(attrs)) continue;
        final id = RegExp(r'\bid="([^"]*)"').firstMatch(attrs)?.group(1)?.trim() ?? '';
        if (id.isEmpty) continue;
        final norm = id.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
        if (!seen.add(norm)) continue;
        final name = RegExp(r'\bname="([^"]*)"').firstMatch(attrs)?.group(1)?.trim() ?? id;
        devices.add({
          'deviceID': id,
          'name': name,
          'addresses': <String>[],
          'connected': false,
          'isLocalNetwork': false,
        });
      }
      return devices;
    } catch (e) {
      debugPrint('parseDevicesFromConfig 失败: $e');
      return [];
    }
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

  /// 解析路由中的 folderId（支持 URL 编码的中文 ID）
  String _resolveFolderId(String raw) {
    if (raw.isEmpty) return raw;
    try {
      var id = Uri.decodeComponent(raw);
      // 部分平台可能双重编码
      if (id.contains('%')) {
        id = Uri.decodeComponent(id);
      }
      return id;
    } catch (_) {
      return raw;
    }
  }

  /// 从 Syncthing 配置读取文件夹本地路径（优先 REST，避免 xml 属性顺序问题）
  Future<String?> getFolderPath(String folderId) async {
    final resolvedId = _resolveFolderId(folderId);
    final encoded = Uri.encodeComponent(resolvedId);
    final result = await proxyGet('/rest/config/folders/$encoded', silent: true);
    if (!result.containsKey('error')) {
      final path = result['path']?.toString() ?? '';
      if (path.isNotEmpty) return path;
    }
    for (final f in getFoldersFromConfig()) {
      final fid = f['id']?.toString() ?? '';
      if (fid == resolvedId || fid == folderId) {
        final path = f['path']?.toString() ?? '';
        if (path.isNotEmpty) return path;
      }
    }
    return null;
  }

  /// 触发文件夹扫描（接受共享或新建后调用）
  Future<void> triggerFolderScan(String folderId) async {
    final encoded = Uri.encodeComponent(folderId);
    await proxyPost('/rest/db/scan?folder=$encoded', {});
  }

  /// 重建指定文件夹的索引：从配置移除再加回（会 DropFolder，本地文件保留）。
  /// 比 /rest/system/reset 更适合移动端（无需暂停+整进程重启）。
  Future<Map<String, dynamic>> resetFolderIndex(String folderId) async {
    final resolvedId = _resolveFolderId(folderId);
    final encoded = Uri.encodeComponent(resolvedId);
    debugPrint('[sync] 重建索引 folder=$resolvedId');

    final cfg = await proxyGet('/rest/config/folders/$encoded');
    if (_isProxyError(cfg) || cfg.isEmpty) {
      return {'error': '读取文件夹配置失败: ${cfg['error'] ?? 'empty'}'};
    }

    final saved = Map<String, dynamic>.from(cfg);
    // 确保重新加入时不会保持异常暂停态
    saved['paused'] = false;
    saved['id'] = resolvedId;

    final del = await proxyDelete('/rest/config/folders/$encoded');
    if (_isProxyError(del)) {
      return {'error': '移除文件夹配置失败: ${del['error']}'};
    }
    debugPrint('[sync] 已移除配置以丢弃索引: $resolvedId');

    // 等待 model.removeFolder / DropFolder 完成
    await Future.delayed(const Duration(milliseconds: 800));

    final created = await proxyPost('/rest/config/folders', saved);
    if (_isProxyError(created)) {
      return {'error': '重新添加文件夹失败: ${created['error']}'};
    }
    debugPrint('[sync] 已重新添加文件夹: $resolvedId');

    await Future.delayed(const Duration(milliseconds: 400));
    await triggerFolderScan(resolvedId);
    return {'ok': 'rebuilt folder index', 'folderId': resolvedId};
  }

  /// Android：确保 ignorePerms=true 并触发全量扫描
  Future<void> ensureAndroidFoldersReady() async {
    if (!Platform.isAndroid) return;
    if (!await isRunning()) return;

    final folders = getFoldersFromConfig();
    for (final f in folders) {
      final id = f['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final encoded = Uri.encodeComponent(id);
      final cfg = await proxyGet('/rest/config/folders/$encoded', silent: true);
      if (cfg.containsKey('error')) continue;
      if (cfg['ignorePerms'] != true) {
        final updated = Map<String, dynamic>.from(cfg);
        updated['ignorePerms'] = true;
        await proxyPut('/rest/config/folders/$encoded', updated);
        debugPrint('[folder] 已设置 ignorePerms: $id');
      }
      await triggerFolderScan(id);
    }
  }

  int? _prevInBytesTotal;
  int? _prevOutBytesTotal;
  DateTime? _prevConnSampleAt;

  /// 从 /rest/system/connections 的累计字节估算当前上下行速率（B/s）
  Future<({int inBps, int outBps})> _sampleConnectionRates() async {
    final conn = await proxyGet('/rest/system/connections', silent: true);
    if (_isProxyError(conn) || conn.isEmpty) {
      return (inBps: 0, outBps: 0);
    }
    final total = conn['total'];
    int inTotal = 0;
    int outTotal = 0;
    if (total is Map) {
      inTotal = (total['inBytesTotal'] as num?)?.toInt() ?? 0;
      outTotal = (total['outBytesTotal'] as num?)?.toInt() ?? 0;
    }
    final now = DateTime.now();
    var inBps = 0;
    var outBps = 0;
    final prevAt = _prevConnSampleAt;
    final prevIn = _prevInBytesTotal;
    final prevOut = _prevOutBytesTotal;
    if (prevAt != null && prevIn != null && prevOut != null) {
      final dt = now.difference(prevAt).inMilliseconds / 1000.0;
      if (dt >= 0.5) {
        if (inTotal >= prevIn) inBps = ((inTotal - prevIn) / dt).round();
        if (outTotal >= prevOut) outBps = ((outTotal - prevOut) / dt).round();
      }
    }
    _prevInBytesTotal = inTotal;
    _prevOutBytesTotal = outTotal;
    _prevConnSampleAt = now;
    return (inBps: inBps, outBps: outBps);
  }

  /// 从 Syncthing 读取文件夹同步状态（本机视角，以 db/status 为准）
  Future<Map<String, dynamic>> getFolderSyncSummary(String folderId) async {
    // 防御路径参数被双重编码（如 %E5%A4%96%E5%8C%85）
    var id = folderId;
    for (var i = 0; i < 2; i++) {
      try {
        final decoded = Uri.decodeComponent(id);
        if (decoded == id) break;
        id = decoded;
      } catch (_) {
        break;
      }
    }
    final status = await proxyGet(
      '/rest/db/status',
      queryParams: {'folder': id},
      silent: true,
    );
    // 注意：成功响应里也有 error:""，不能用 containsKey('error')
    if (_isProxyError(status) || status.isEmpty) {
      debugPrint(
        '[sync][$id] db/status 失败或空: '
        'keys=${status.keys.toList()} err=${status['error']}',
      );
      return {'status': 'unknown', 'state': 'unknown', 'completion': 0.0};
    }

    final state = status['state']?.toString() ?? 'unknown';
    final stateError = status['error']?.toString().trim() ?? '';
    final hasStateError =
        stateError.isNotEmpty && stateError != 'null';
    final needBytes = (status['needBytes'] as num?)?.toInt() ?? 0;
    final needFiles = (status['needFiles'] as num?)?.toInt() ?? 0;
    final globalBytes = (status['globalBytes'] as num?)?.toInt() ?? 0;
    final globalFiles = (status['globalFiles'] as num?)?.toInt() ?? 0;
    final localFiles = (status['localFiles'] as num?)?.toInt() ?? 0;
    final localBytes = (status['localBytes'] as num?)?.toInt() ?? 0;
    final pullErrors = (status['pullErrors'] as num?)?.toInt() ?? 0;
    final rawInSyncFiles = (status['inSyncFiles'] as num?)?.toInt();
    final rawInSyncBytes = (status['inSyncBytes'] as num?)?.toInt();
    final inSyncFiles =
        rawInSyncFiles ?? (globalFiles - needFiles).clamp(0, globalFiles);
    final inSyncBytes =
        rawInSyncBytes ?? (globalBytes - needBytes).clamp(0, globalBytes);

    // 本机完成度：用 inSyncBytes/globalBytes（勿用 /rest/db/completion，那是对端视角）
    final double completion;
    if (globalBytes > 0) {
      completion = (inSyncBytes / globalBytes * 100.0).clamp(0.0, 100.0);
    } else if (needFiles == 0 && needBytes == 0) {
      completion = 100.0;
    } else {
      completion = 0.0;
    }

    // 对照旧算法，便于确认热重载/热重启是否生效
    final oldNeedBased = globalBytes > 0
        ? ((globalBytes - needBytes) / globalBytes * 100.0).clamp(0.0, 100.0)
        : 100.0;

    final rates = await _sampleConnectionRates();
    // idle 但仍有 need：常见于过期/重复索引（对端已无这些项，本机也不会再传输）
    final stalledIdle =
        state == 'idle' && (needFiles > 0 || needBytes > 0);

    String uiStatus;
    if (pullErrors > 0 || hasStateError || state == 'error') {
      uiStatus = 'error';
    } else if (stalledIdle) {
      uiStatus = 'stalled';
    } else if (state == 'syncing' ||
        state == 'scanning' ||
        state == 'scan-waiting' ||
        needBytes > 0 ||
        needFiles > 0) {
      uiStatus = 'syncing';
    } else if (globalBytes > 0 && completion < 99.9) {
      uiStatus = 'syncing';
    } else if (globalBytes == 0 && localFiles == 0) {
      uiStatus = 'waiting';
    } else {
      uiStatus = 'synced';
    }

    debugPrint(
      '[sync][$id] state=$state ui=$uiStatus '
      'inSyncFiles=$inSyncFiles(raw=$rawInSyncFiles) '
      'globalFiles=$globalFiles localFiles=$localFiles needFiles=$needFiles | '
      'inSyncBytes=$inSyncBytes(raw=$rawInSyncBytes) '
      'globalBytes=$globalBytes needBytes=$needBytes | '
      'completion=${completion.toStringAsFixed(1)}% '
      '(oldNeedBased=${oldNeedBased.toStringAsFixed(1)}%) '
      '↓${rates.inBps} ↑${rates.outBps} B/s',
    );

    final summary = {
      'state': state,
      'status': uiStatus,
      'completion': completion,
      'needBytes': needBytes,
      'needFiles': needFiles,
      'globalBytes': globalBytes,
      'globalFiles': globalFiles,
      'localFiles': localFiles,
      'localBytes': localBytes,
      'inSyncFiles': inSyncFiles,
      'inSyncBytes': inSyncBytes,
      'pullErrors': pullErrors,
      'inBps': rates.inBps,
      'outBps': rates.outBps,
      'stalled': stalledIdle,
    };
    await _applyPathDiagnostics(id, status, summary);
    return summary;
  }

  String _folderErrorMessage(String raw, String? path) {
    final lower = raw.toLowerCase();
    if (lower.contains('folder path missing')) {
      if (path != null && path.isNotEmpty) {
        return 'Syncthing 找不到同步目录：$path';
      }
      return 'Syncthing 同步目录不存在';
    }
    return raw;
  }

  /// 检测配置路径是否存在，并解析 db/status 中的 folder 级错误
  Future<void> _applyPathDiagnostics(
    String folderId,
    Map<String, dynamic> status,
    Map<String, dynamic> result,
  ) async {
    final stateError = status['error']?.toString().trim() ?? '';
    final hasStateError =
        stateError.isNotEmpty && stateError != 'null';
    final watchError = status['watchError']?.toString().trim() ?? '';
    final folderPath = await getFolderPath(folderId);

    String? pathError;
    var needsPathFix = false;
    var pathMissing = false;

    if (folderPath != null && folderPath.isNotEmpty) {
      result['currentPath'] = folderPath;
      if (!await Directory(folderPath).exists()) {
        pathMissing = true;
        needsPathFix = true;
        pathError = '同步目录不存在：$folderPath';
      }
    }

    if (hasStateError) {
      needsPathFix = true;
      pathError ??= _folderErrorMessage(stateError, folderPath);
    }

    if (watchError.isNotEmpty) {
      needsPathFix = true;
      pathError = pathError != null ? '$pathError（$watchError）' : watchError;
    }

    if (needsPathFix) {
      result['needsPathFix'] = true;
      result['pathMissing'] = pathMissing;
      if (pathError != null) result['pathError'] = pathError;
      result['status'] = 'error';
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
    if (SyncthingLifecycle.instance.isRestarting) {
      return {'error': 'Syncthing 重启中，请稍后重试'};
    }
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

    // 曾被忽略过时，先从 remoteIgnoredDevices 去掉，否则无法真正配对
    await unignoreRemoteDevice(formattedId);

    return proxyPost('/rest/config/devices', device);
  }

  /// 读取完整 config（失败返回带 error 的 map）
  Future<Map<String, dynamic>> _getFullConfig() async {
    final raw = await proxyGet('/rest/config');
    if (_isProxyError(raw)) return raw;
    if (raw.containsKey('version') || raw.containsKey('devices')) {
      return Map<String, dynamic>.from(raw);
    }
    final data = raw['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'error': '无法读取 Syncthing 配置'};
  }

  bool _sameDeviceId(String a, String b) => _normId(a) == _normId(b);

  /// 将设备加入 remoteIgnoredDevices，避免删除/拒绝后反复弹出「新设备请求」
  Future<Map<String, dynamic>> ignoreRemoteDevice(
    String deviceId, {
    String name = '',
    String address = '',
  }) async {
    if (!await isRunning()) return {'error': 'Syncthing 未运行'};
    final cfg = await _getFullConfig();
    if (cfg.containsKey('error')) return cfg;

    final formattedId = formatDeviceId(deviceId);
    final ignored = <Map<String, dynamic>>[];
    for (final e in (cfg['remoteIgnoredDevices'] as List? ?? const [])) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['deviceID']?.toString() ?? '';
      if (id.isEmpty || _sameDeviceId(id, deviceId)) continue;
      ignored.add(m);
    }
    ignored.add({
      'deviceID': formattedId,
      'name': name,
      'address': address,
      'time': DateTime.now().toUtc().toIso8601String(),
    });
    cfg['remoteIgnoredDevices'] = ignored;
    return proxyPut('/rest/config', cfg);
  }

  /// 从忽略列表移除（重新接受该设备前调用）
  Future<Map<String, dynamic>> unignoreRemoteDevice(String deviceId) async {
    if (!await isRunning()) return {'error': 'Syncthing 未运行'};
    final cfg = await _getFullConfig();
    if (cfg.containsKey('error')) return cfg;

    final list = (cfg['remoteIgnoredDevices'] as List? ?? const []);
    final next = <Map<String, dynamic>>[];
    var changed = false;
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = m['deviceID']?.toString() ?? '';
      if (_sameDeviceId(id, deviceId)) {
        changed = true;
        continue;
      }
      next.add(m);
    }
    if (!changed) return {};
    cfg['remoteIgnoredDevices'] = next;
    return proxyPut('/rest/config', cfg);
  }

  /// 从配置删除设备，并写入 remoteIgnoredDevices（防止对端仍连接时反复 pending 弹窗）。
  /// 用单设备 / 单文件夹接口删共享与设备，再 ignore；避免整份 config PUT 打挂 8384。
  Future<Map<String, dynamic>> removeAndIgnoreDevice(String deviceId) async {
    if (!await isRunning()) return {'error': 'Syncthing 未运行'};
    final formattedId = formatDeviceId(deviceId);

    var name = '';
    final getDev = await proxyGet('/rest/config/devices/$formattedId', silent: true);
    if (!_isProxyError(getDev)) {
      final data = getDev['data'];
      if (data is Map) {
        name = data['name']?.toString() ?? '';
      }
    }

    final foldersRes = await proxyGet('/rest/config/folders');
    if (!_isProxyError(foldersRes)) {
      final folderList = foldersRes['data'] is List
          ? foldersRes['data'] as List
          : const [];
      for (final e in folderList) {
        if (e is! Map) continue;
        final folder = Map<String, dynamic>.from(e);
        final folderId = folder['id']?.toString() ?? '';
        if (folderId.isEmpty) continue;
        final fDevs = <Map<String, dynamic>>[];
        var changed = false;
        for (final d in (folder['devices'] as List? ?? const [])) {
          if (d is! Map) continue;
          final dm = Map<String, dynamic>.from(d);
          final id = dm['deviceID']?.toString() ?? '';
          if (_sameDeviceId(id, deviceId)) {
            changed = true;
            continue;
          }
          fDevs.add(dm);
        }
        if (!changed) continue;
        folder['devices'] = fDevs;
        final encoded = Uri.encodeComponent(folderId);
        final put = await proxyPut('/rest/config/folders/$encoded', folder);
        if (_isProxyError(put)) {
          debugPrint('[devices] 文件夹 $folderId 移除设备失败: ${put['error']}');
        }
      }
    }

    final del = await proxyDelete('/rest/config/devices/$formattedId');
    if (_isProxyError(del)) return del;

    final ignore = await ignoreRemoteDevice(formattedId, name: name);
    if (ignore.containsKey('error')) {
      debugPrint('[devices] 删除后写入忽略失败: ${ignore['error']}');
    }

    // 顺带清掉 pending，避免残留再弹
    await proxyDelete(
      '/rest/cluster/pending/devices',
      queryParams: {'device': formattedId},
    );
    return del;
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

  /// 获取已连接设备的局域网地址（原始 host:port）
  Future<({bool connected, String? address})> getDeviceConnection(String deviceId) async {
    final connResult = await proxyGet('/rest/system/connections', silent: true);
    if (connResult.containsKey('error')) {
      return (connected: false, address: null);
    }
    final connections = connResult['connections'];
    if (connections is! Map) return (connected: false, address: null);

    Map<String, dynamic>? conn;
    connections.forEach((key, value) {
      if (_normId(key.toString()) == _normId(deviceId) && value is Map) {
        conn = Map<String, dynamic>.from(value);
      }
    });
    if (conn == null) return (connected: false, address: null);
    return (
      connected: conn!['connected'] == true,
      address: conn!['address']?.toString(),
    );
  }
}
