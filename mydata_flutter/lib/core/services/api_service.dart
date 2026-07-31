import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import '../models/folder.dart';
import '../models/device.dart';
import 'native_service.dart';
import 'android_storage_service.dart';
import '../../shared/utils/sync_folder_paths.dart';
import '../../shared/utils/preview_limits.dart';

/// 预览流式下载结果
class PreviewDownloadResult {
  final String path;
  final String tempDirPath;
  final String contentType;
  final int bytes;

  const PreviewDownloadResult({
    required this.path,
    required this.tempDirPath,
    required this.contentType,
    required this.bytes,
  });

  Future<void> cleanup() async {
    try {
      await Directory(tempDirPath).delete(recursive: true);
    } catch (_) {}
  }
}

/// API 服务，调用后端 API 服务器
class ApiService {
  static String _baseUrl = 'https://localhost:8443/api';
  static bool _initialized = false;
  
  // 创建支持自签名证书的 HTTP 客户端
  static http.Client _createHttpClient() {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      // 允许 localhost 的自签名证书
      return host == 'localhost' || host == '127.0.0.1';
    };
    return IOClient(httpClient);
  }
  
  static final http.Client _httpClient = _createHttpClient();

  /// 初始化 API 服务，获取基础 URL
  static Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      _baseUrl = await NativeService.getApiBaseUrl();
      _initialized = true;
      debugPrint('API 服务初始化成功: $_baseUrl');
    } catch (e) {
      debugPrint('API 服务初始化失败: $e');
      _initialized = true; // 即使失败也标记为已初始化，使用默认值
    }
  }

  /// 执行 GET 请求
  static Future<Map<String, dynamic>> _get(
    String endpoint, {
    Duration? timeout,
    bool silent = false,
  }) async {
    await initialize();
    
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      if (!silent) debugPrint('API GET: $uri');
      
      final effectiveTimeout = timeout ?? const Duration(seconds: 5);
      final response = await _httpClient.get(uri).timeout(
        effectiveTimeout,
        onTimeout: () {
          throw Exception('请求超时：后端服务可能未启动，请确保应用已启动后端服务');
        },
      );

      if (!silent) {
        debugPrint('API 响应状态: ${response.statusCode}');
        if (response.statusCode != 200) {
          debugPrint('API 响应体: ${response.body}');
        }
      }

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        // 处理 client 后端响应格式：{"code": 0, "data": ...}
        if (jsonData is Map<String, dynamic>) {
          if (jsonData.containsKey('code') && jsonData['code'] == 0) {
            return jsonData;
          } else if (jsonData.containsKey('success') && jsonData['success'] == true) {
            // Android API 格式
            final data = jsonData['data'];
            if (data is List) {
              return {'list': data};
            } else if (data is Map<String, dynamic>) {
              return data;
            } else {
              return {'list': []};
            }
          } else {
            return jsonData;
          }
        } else if (jsonData is List) {
          // 如果直接返回数组，包装成标准格式
          return {'code': 0, 'data': jsonData};
        } else {
          return jsonData as Map<String, dynamic>;
        }
      } else if (response.statusCode == 503 && silent) {
        return {'code': 1006, 'data': null};
      } else {
        // 尽量解析后端返回的中文错误信息
        try {
          final jsonData = json.decode(response.body);
          if (jsonData is Map && jsonData['data'] != null) {
            throw Exception(jsonData['data'].toString());
          }
        } catch (e) {
          if (e is Exception && !e.toString().startsWith('FormatException')) {
            rethrow;
          }
        }
        throw Exception('HTTP 错误: ${response.statusCode}');
      }
    } catch (e) {
      if (!silent) debugPrint('API 请求失败: $e');
      // 如果是连接被拒绝，提供更友好的错误信息
      final errorStr = e.toString();
      if (errorStr.contains('连接被拒绝') || 
          errorStr.contains('Connection refused') ||
          errorStr.contains('SocketException')) {
        // Android 端使用 AAR 中的 backend，后端服务会在应用内自动启动
        throw Exception('无法连接到后端服务 (localhost:8443)\n\n请确保应用已启动后端服务（通过 SyncthingService）');
      }
      rethrow;
    }
  }

  /// 执行 POST 请求
  static Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    await initialize();
    
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API POST: $uri');
      debugPrint('API 请求体: ${json.encode(body)}');
      
      final response = await _httpClient.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      debugPrint('API 响应状态: ${response.statusCode}');
      debugPrint('API 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData is Map<String, dynamic>) {
          if (jsonData.containsKey('code') && jsonData['code'] != 0) {
            throw Exception(jsonData['data']?.toString() ?? '请求失败');
          }
          if (jsonData.containsKey('error')) {
            throw Exception(jsonData['error'].toString());
          }
        }
        
        if (jsonData is Map<String, dynamic> && jsonData['success'] == true) {
          return jsonData['data'] as Map<String, dynamic>;
        } else {
          return jsonData as Map<String, dynamic>;
        }
      } else {
        throw Exception('HTTP 错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API 请求失败: $e');
      rethrow;
    }
  }

  /// 获取所有设备
  static Future<List<Device>> getDevices() async {
    try {
      final response = await _get('/devices');
      
      // 处理 client 后端响应格式：{"code": 0, "data": [...]}
      List<dynamic> deviceList;
      if (response.containsKey('code') && response['code'] == 0) {
        deviceList = response['data'] as List<dynamic>? ?? [];
      } else if (response.containsKey('list')) {
        deviceList = response['list'] as List<dynamic>;
      } else if (response.containsKey('data')) {
        deviceList = response['data'] is List 
            ? response['data'] as List<dynamic>
            : [response['data']];
      } else {
        deviceList = [];
      }
      
      // 确保本地设备在列表中
      final hasLocalDevice = deviceList.any((d) {
        if (d is! Map<String, dynamic>) return false;
        return d['deviceID'] == 'local' || 
               d['connectionType'] == 'local' ||
               d['clientVersion'] == 'local';
      });
      
      if (!hasLocalDevice) {
        deviceList.insert(0, {
          'deviceID': 'local',
          'name': '本机设备',
          'addresses': [],
          'compression': '',
          'certName': '',
          'introducer': false,
          'connected': true,
          'connectionType': 'local',
          'clientVersion': 'local',
          'inBytesTotal': 0,
          'outBytesTotal': 0,
          'isLocalNetwork': true,
          'crypto': 'local'
        });
      }
      
      // 过滤并转换设备数据，确保每个元素都是 Map
      // Device.fromJson 已经处理了 null 值安全检查
      final devices = <Device>[];
      for (final item in deviceList) {
        if (item is! Map<String, dynamic>) continue;
        
        try {
          // 确保 addresses 是 List（如果存在）
          final json = Map<String, dynamic>.from(item);
          if (json['addresses'] != null && json['addresses'] is! List) {
            json['addresses'] = [];
          }
          
          final device = Device.fromJson(json);
          devices.add(device);
        } catch (e) {
          debugPrint('解析设备失败，跳过: $e');
          debugPrint('设备数据: $item');
          // 跳过无效的设备数据，继续处理其他设备
          continue;
        }
      }
      
      return devices;
    } catch (e) {
      debugPrint('获取设备列表失败: $e');
      // 失败时至少返回本地设备
      return [Device(
        id: 'local',
        name: '本机设备',
        addresses: [],
        connected: true,
        connectionType: 'local',
        version: 'local',
        isLocalNetwork: true,
        crypto: 'local',
      )];
    }
  }

  /// 获取设备文件夹
  static Future<List<Folder>> getDeviceFolders(String deviceId) async {
    try {
      // 如果 deviceId 为空，使用 'local' 作为默认值
      final validDeviceId = deviceId.isEmpty ? 'local' : deviceId;
      final localDeviceId = await getLocalDeviceId();
      final response = await _get(
        '/device/$validDeviceId/folders',
        timeout: const Duration(seconds: 12),
      );

      if (response.containsKey('code') && response['code'] != 0) {
        final msg = response['data']?.toString() ?? '获取文件夹失败';
        throw Exception(msg);
      }

      // 处理 client 后端响应格式
      List<dynamic> folderList;
      if (response.containsKey('code') && response['code'] == 0) {
        folderList = response['data'] as List<dynamic>? ?? [];
      } else if (response.containsKey('list')) {
        folderList = response['list'] as List<dynamic>;
      } else if (response.containsKey('data')) {
        folderList = response['data'] is List
            ? response['data'] as List<dynamic>
            : [response['data']];
      } else {
        folderList = [];
      }

      return folderList.map((json) {
        final status = json['status']?.toString() ?? 'synced';
        return Folder(
          id: json['id'] ?? '',
          name: json['label'] ?? json['name'] ?? 'Unknown Folder',
          path: json['path'] ?? '',
          deviceId: deviceId,
          isLocal: validDeviceId == 'local' || validDeviceId == localDeviceId,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          status: status,
          fileCount: (json['localFiles'] as num?)?.toInt() ?? 0,
          totalSize: (json['localBytes'] as num?)?.toInt() ??
              (json['globalBytes'] as num?)?.toInt() ??
              0,
          access: json['access']?.toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('获取设备文件夹失败: $e');
      rethrow;
    }
  }


  /// 获取所有文件夹
  static Future<List<Folder>> getFolders() async {
    try {
      // Android API 可能没有直接的 /folders 端点
      // 尝试从本地设备获取文件夹
      final localDeviceId = await getLocalDeviceId();
      return await getDeviceFolders(localDeviceId);
    } catch (e) {
      debugPrint('获取文件夹列表失败: $e');
      throw Exception('获取文件夹列表失败: $e');
    }
  }

  /// 获取本地设备 ID
  static Future<String> getLocalDeviceId() async {
    try {
      final data = await _get('/deviceid');
      String deviceId = '';
      if (data.containsKey('code') && data['code'] == 0) {
        deviceId = data['data']?['deviceID'] ?? '';
      } else {
        deviceId = data['deviceID'] ?? '';
      }
      // 如果获取失败或为空，返回 'local' 作为默认值
      return deviceId.isNotEmpty ? deviceId : 'local';
    } catch (e) {
      debugPrint('获取本地设备 ID 失败: $e');
      final errorStr = e.toString();
      if (errorStr.contains('连接被拒绝') || 
          errorStr.contains('Connection refused')) {
        throw Exception('无法连接到后端服务\n\n请确保应用已启动后端服务（通过 SyncthingService）');
      }
      throw Exception('获取本地设备 ID 失败: $e');
    }
  }

  /// 创建文件夹
  static Future<Folder> createFolder({
    required String id,
    required String name,
    required String path,
    List<String>? sharedDevices,
  }) async {
    try {
      final data = await _post('/device/local/folders', {
        'id': id,
        'label': name,
        'path': path,
        'type': 'sendreceive',
        if (sharedDevices != null) 'sharedDevices': sharedDevices,
      });
      
      // 适配 client 后端返回的数据格式
      return Folder(
        id: data['id'] ?? id,
        name: data['label'] ?? data['name'] ?? name,
        path: data['path'] ?? path,
        deviceId: 'local',
        isLocal: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: 'synced',
        fileCount: 0,
        totalSize: 0,
      );
    } catch (e) {
      debugPrint('创建文件夹失败: $e');
      throw Exception('创建文件夹失败: $e');
    }
  }


  /// 获取同步状态
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      return await _get('/syncthing/events');
    } catch (e) {
      debugPrint('获取同步状态失败: $e');
      throw Exception('获取同步状态失败: $e');
    }
  }

  /// 获取文件夹同步状态（Android 会附加 native 写权限检测结果）
  static Future<Map<String, dynamic>> getFolderSyncStatus(String folderId) async {
    try {
      final response = await _get('/folder/${Uri.encodeComponent(folderId)}/status', silent: true);
      Map<String, dynamic> sync;
      if (response.containsKey('code') && response['code'] == 0) {
        final data = response['data'];
        sync = data is Map<String, dynamic> ? Map<String, dynamic>.from(data) : {'status': 'unknown', 'completion': 0.0};
      } else {
        sync = {'status': 'unknown', 'completion': 0.0};
      }

      if (Platform.isAndroid) {
        final currentPath = sync['currentPath']?.toString() ?? '';
        if (currentPath.isNotEmpty) {
          final writable = await AndroidStorageService.canWriteToPath(currentPath);
          sync['pathWritable'] = writable;
          if (!writable) {
            sync['pathError'] = isPublicStoragePath(currentPath)
                ? 'Syncthing 无法写入 $currentPath。请授予「所有文件访问」权限，或重新选择同步目录。'
                : 'Syncthing 无法写入 $currentPath，请重新选择同步目录。';
            sync['needsPathFix'] = true;
            if (sync['status'] != 'syncing') sync['status'] = 'error';
          }
        }
      }
      return sync;
    } catch (e) {
      debugPrint('获取文件夹同步状态失败: $e');
      return {'status': 'unknown', 'completion': 0.0};
    }
  }

  /// 更新文件夹同步路径或触发重新扫描
  static Future<Map<String, dynamic>> fixFolderPath(String folderId, {String? path}) async {
    final body = path != null ? {'path': path} : <String, dynamic>{};
    final response = await _post('/folder/${Uri.encodeComponent(folderId)}/fix-path', body);
    if (response['code'] != 0) {
      throw Exception(response['data']?.toString() ?? '修复路径失败');
    }
    final data = response['data'];
    return data is Map<String, dynamic> ? data : {'message': '已修复同步目录'};
  }

  /// 获取文件夹文件列表
  /// [deviceId] 非本机时经 peer 代理拉取对端文件
  static Future<List<Map<String, dynamic>>> getFolderFiles(
    String folderId, {
    String? path,
    String? deviceId,
  }) async {
    try {
      final localId = await getLocalDeviceId();
      final isLocal = deviceId == null ||
          deviceId.isEmpty ||
          deviceId == 'local' ||
          deviceId == localId;

      String endpoint;
      if (isLocal) {
        endpoint = '/folder/${Uri.encodeComponent(folderId)}';
      } else {
        endpoint =
            '/device/${Uri.encodeComponent(deviceId)}/folder/${Uri.encodeComponent(folderId)}/files';
      }
      if (path != null && path.isNotEmpty) {
        endpoint += '?path=${Uri.encodeComponent(path)}';
      }

      final response = await _get(endpoint, timeout: const Duration(seconds: 12));

      if (response.containsKey('code') && response['code'] != 0) {
        debugPrint('获取文件夹文件列表失败: ${response['data']}');
        throw Exception(response['data']?.toString() ?? '获取文件列表失败');
      }

      List<dynamic> fileList;
      if (response['data'] is List) {
        fileList = response['data'] as List<dynamic>;
      } else {
        return [];
      }

      return fileList.whereType<Map<String, dynamic>>().map((f) {
        final copy = Map<String, dynamic>.from(f);
        final t = copy['type'];
        copy['isDir'] = t == 1 ||
            t == '1' ||
            t == 'dir' ||
            t == true ||
            copy['isDir'] == true;
        return copy;
      }).toList();
    } catch (e) {
      debugPrint('获取文件夹文件列表失败: $e');
      rethrow;
    }
  }

  /// 桌面操作前确保 Syncthing 可用
  static Future<void> _ensureSyncthingReady() async {
    if (kIsWeb) return;
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
    final ok = await NativeService.ensureSyncthingRunning();
    if (!ok) {
      throw Exception('Syncthing 未运行，请重启应用后再试');
    }
  }

  /// 添加设备（本机 Syncthing 配置，需对端也添加本机才能完成配对）
  static Future<void> addDevice({
    required String deviceID,
    required String name,
  }) async {
    try {
      await _ensureSyncthingReady();
      await _post('/syncthing/config/devices', {
        'deviceID': deviceID,
        'name': name,
      });
    } catch (e) {
      debugPrint('添加设备失败: $e');
      throw Exception('添加设备失败: $e');
    }
  }

  /// 获取待确认的设备（未知设备尝试连接时出现在对端）
  static Future<Map<String, dynamic>> getPendingDevices() async {
    try {
      final response = await _get('/syncthing/cluster/pending/devices', silent: true);
      if (response['code'] == 1006) return {};
      if (response.containsKey('code') && response['code'] == 0) {
        final data = response['data'];
        if (data is Map<String, dynamic>) return data;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// 忽略/关闭待确认设备通知
  static Future<void> dismissPendingDevice(String deviceId) async {
    await initialize();
    final uri = Uri.parse('$_baseUrl/syncthing/cluster/pending/devices?device=${Uri.encodeComponent(deviceId)}');
    await _httpClient.delete(uri).timeout(const Duration(seconds: 5));
  }

  /// 获取待接受的共享文件夹
  static Future<Map<String, dynamic>> getPendingFolders() async {
    try {
      final response = await _get('/syncthing/cluster/pending/folders', silent: true);
      if (response['code'] == 1006) {
        debugPrint('[pending] Syncthing 未运行');
        return {};
      }
      if (response.containsKey('code') && response['code'] == 0) {
        final data = response['data'];
        if (data is Map<String, dynamic>) return data;
      }
      return {};
    } catch (e) {
      debugPrint('[pending] 查询待接受文件夹失败: $e');
      return {};
    }
  }

  /// 忽略待接受的共享文件夹
  static Future<void> dismissPendingFolder({
    required String folderId,
    required String deviceId,
  }) async {
    await initialize();
    final uri = Uri.parse(
      '$_baseUrl/syncthing/cluster/pending/folders?folder=${Uri.encodeComponent(folderId)}&device=${Uri.encodeComponent(deviceId)}',
    );
    await _httpClient.delete(uri).timeout(const Duration(seconds: 10));
  }

  /// 接受待共享文件夹
  static Future<Map<String, dynamic>> acceptPendingFolder({
    required String folderId,
    required String deviceId,
    String? path,
  }) async {
    await initialize();
    final body = <String, dynamic>{
      'folder': folderId,
      'device': deviceId,
    };
    if (path != null && path.isNotEmpty) body['path'] = path;
    final response = await _post('/syncthing/cluster/pending/folders/accept', body);
    if (response['code'] != 0) {
      throw Exception(response['data']?.toString() ?? '接受共享失败');
    }
    final data = response['data'];
    return data is Map<String, dynamic> ? data : {'message': '已接受共享文件夹'};
  }

  /// 接受待确认设备：添加到本机并清除 pending
  static Future<void> acceptPendingDevice({
    required String deviceId,
    required String name,
  }) async {
    await addDevice(deviceID: deviceId, name: name);
    try {
      await dismissPendingDevice(deviceId);
    } catch (_) {}
  }


  /// 获取 WiFi 信息
  static Future<Map<String, dynamic>> getWifiInfo() async {
    try {
      return await _get('/wifi-info');
    } catch (e) {
      debugPrint('获取WiFi信息失败: $e');
      return {'wifiName': '获取失败'};
    }
  }

  /// 获取 Syncthing 事件
  static Future<List<Map<String, dynamic>>> getSyncthingEvents({
    int since = 0,
    int timeout = 60,
  }) async {
    try {
      final response = await _get(
        '/syncthing/events?since=$since&timeout=$timeout',
        timeout: Duration(seconds: timeout + 15),
        silent: true,
      );

      if (response['code'] == 1006) return [];
      
      // Syncthing 事件 API 直接返回数组
      if (response is List) {
        return (response as List).map((e) => e as Map<String, dynamic>).toList().cast<Map<String, dynamic>>();
      } else if (response is Map<String, dynamic>) {
        if (response.containsKey('data') && response['data'] is List) {
          final dataList = response['data'] as List;
          return dataList.map((e) => e as Map<String, dynamic>).toList().cast<Map<String, dynamic>>();
        } else if (response.containsKey('code') && response['code'] == 0 && response['data'] is List) {
          final dataList = response['data'] as List;
          return dataList.map((e) => e as Map<String, dynamic>).toList().cast<Map<String, dynamic>>();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// 获取设备发现信息
  static Future<Map<String, dynamic>> getDiscovery() async {
    try {
      final response = await _get('/syncthing/discovery');
      
      // 处理不同的响应格式
      // 1. 如果响应包含 code 和 data，提取 data
      if (response.containsKey('code') && response.containsKey('data')) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      // 2. 如果响应包含 success 和 data，提取 data
      if (response.containsKey('success') && response.containsKey('data')) {
        final data = response['data'];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      // 3. 如果响应本身就是设备发现数据（key 是设备 ID）
      // 检查是否有常见的包装字段，如果没有，直接返回
      if (!response.containsKey('code') && 
          !response.containsKey('success') && 
          !response.containsKey('error')) {
        return response;
      }
      
      debugPrint('无法解析 discovery 响应格式: $response');
      return {};
    } catch (e) {
      debugPrint('获取设备发现信息失败: $e');
      return {};
    }
  }

  /// 获取局域网发现的设备 ID 列表（带名称）
  static Future<List<Map<String, String>>> getDiscoveredDevices({
    int retries = 5,
    Duration interval = const Duration(seconds: 3),
  }) async {
    for (var attempt = 0; attempt < retries; attempt++) {
      final devices = await _fetchDiscoveredDevicesOnce();
      if (devices.isNotEmpty) return devices;
      if (attempt < retries - 1) {
        debugPrint('局域网扫描未发现设备，${interval.inSeconds}s 后重试 (${attempt + 1}/$retries)');
        await Future.delayed(interval);
      }
    }
    return [];
  }

  static Future<List<Map<String, String>>> _fetchDiscoveredDevicesOnce() async {
    try {
      final discovery = await getDiscovery();
      debugPrint('Discovery 数据: $discovery');
      
      // 获取已配置的设备列表，用于匹配设备名称
      Map<String, String> deviceNameMap = {};
      try {
        final configuredDevices = await getDevices();
        for (var device in configuredDevices) {
          // 移除连字符和空格进行匹配
          final cleanId = device.id.replaceAll(RegExp(r'[\s-]'), '');
          if (device.name.trim().isNotEmpty) {
            deviceNameMap[cleanId] = device.name.trim();
          }
        }
      } catch (e) {
        debugPrint('获取已配置设备列表失败（用于匹配名称）: $e');
      }
      
      // 获取本机 ID，排除自身
      String localCleanId = '';
      try {
        localCleanId = (await getLocalDeviceId()).replaceAll(RegExp(r'[\s-]'), '');
      } catch (_) {}

      // discovery 格式应该是: { "deviceID1": {...}, "deviceID2": {...} }
      // 过滤掉非设备 ID 的 key（如 "code", "success", "error", "data" 等）
      final discoveredDevices = <Map<String, String>>[];
      
      for (final deviceId in discovery.keys) {
        // 排除常见的响应字段
        if (deviceId == 'code' || 
            deviceId == 'success' || 
            deviceId == 'error' || 
            deviceId == 'data' || 
            deviceId == 'message') {
          continue;
        }
        // 设备 ID 通常是较长的字符串（至少 20 个字符）
        if (deviceId.length < 20) {
          continue;
        }

        final cleanId = deviceId.replaceAll(RegExp(r'[\s-]'), '');
        if (localCleanId.isNotEmpty && cleanId == localCleanId) {
          continue;
        }
        
        // 尝试从 discovery 条目或已配置设备中获取名称
        String deviceName = deviceId;
        final entry = discovery[deviceId];
        if (entry is Map) {
          final announceName = entry['name'] ?? entry['deviceName'];
          if (announceName is String && announceName.isNotEmpty) {
            deviceName = announceName;
          }
        }
        final cleanForMap = deviceId.replaceAll(RegExp(r'[\s-]'), '');
        deviceName = deviceNameMap[cleanForMap] ?? deviceName;
        if (deviceName.trim().isEmpty) {
          deviceName = deviceId;
        }
        
        discoveredDevices.add({
          'id': deviceId,
          'name': deviceName,
        });
      }
      
      debugPrint('发现的设备列表（带名称）: $discoveredDevices');
      return discoveredDevices;
    } catch (e) {
      debugPrint('获取发现的设备列表失败: $e');
      return [];
    }
  }

  /// 获取局域网发现的设备 ID 列表（仅ID，保持向后兼容）
  static Future<List<String>> getDiscoveredDeviceIds() async {
    try {
      final devices = await getDiscoveredDevices();
      return devices.map((d) => d['id']!).toList();
    } catch (e) {
      debugPrint('获取发现的设备 ID 列表失败: $e');
      return [];
    }
  }

  /// 验证设备 ID
  static Future<bool> validateDeviceId(String deviceId) async {
    try {
      final response = await _get('/syncthing/deviceid?id=${Uri.encodeComponent(deviceId)}');
      return !response.containsKey('error');
    } catch (e) {
      debugPrint('验证设备 ID 失败: $e');
      return false;
    }
  }

  /// 文件预览
  /// [deviceId] 非本机时经 peer 代理从对端拉取文件内容
  static Future<http.Response> previewFile(
    String folderId,
    String filePath, {
    String? deviceId,
  }) async {
    await initialize();
    final uri = await _previewUri(folderId, filePath, deviceId: deviceId);
    debugPrint('API GET preview: $uri');
    return await _httpClient.get(uri).timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw Exception('预览超时（对端需同网且已打开 MyData）'),
    );
  }

  /// 流式下载预览文件到临时路径，避免大文件整包进内存
  static Future<PreviewDownloadResult> previewFileToTemp(
    String folderId,
    String filePath, {
    String? deviceId,
    void Function(int received, int? total)? onProgress,
  }) async {
    await initialize();
    final uri = await _previewUri(folderId, filePath, deviceId: deviceId);
    debugPrint('API GET preview stream: $uri');

    final request = http.Request('GET', uri);
    final streamed = await _httpClient.send(request).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('预览连接超时（对端需同网且已打开 MyData）'),
    );

    if (streamed.statusCode == 413) {
      final body = await streamed.stream.bytesToString();
      throw Exception(body.isNotEmpty ? body : '文件过大，无法应用内预览');
    }
    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      throw Exception(
        body.isNotEmpty ? body : 'HTTP ${streamed.statusCode}',
      );
    }

    final contentLen = streamed.contentLength;
    if (contentLen != null && contentLen > kMaxPreviewBytes) {
      await streamed.stream.drain();
      throw PreviewTooLargeException(contentLen);
    }

    final fileName = filePath.split('/').last;
    final tempDir = await Directory.systemTemp.createTemp('mydata_preview_');
    final tempFile = File('${tempDir.path}/$fileName');
    final sink = tempFile.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream.timeout(
        const Duration(minutes: 5),
      )) {
        received += chunk.length;
        if (received > kMaxPreviewBytes) {
          await sink.close();
          await tempDir.delete(recursive: true);
          throw PreviewTooLargeException(received);
        }
        sink.add(chunk);
        onProgress?.call(received, contentLen);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }

    return PreviewDownloadResult(
      path: tempFile.path,
      tempDirPath: tempDir.path,
      contentType: streamed.headers['content-type'] ?? 'application/octet-stream',
      bytes: received,
    );
  }

  static Future<Uri> _previewUri(
    String folderId,
    String filePath, {
    String? deviceId,
  }) async {
    final localId = await getLocalDeviceId();
    final isLocal = deviceId == null ||
        deviceId.isEmpty ||
        deviceId == 'local' ||
        deviceId == localId;

    final String uriStr;
    if (isLocal) {
      uriStr =
          '$_baseUrl/folder/${Uri.encodeComponent(folderId)}/preview?path=${Uri.encodeComponent(filePath)}';
    } else {
      uriStr =
          '$_baseUrl/device/${Uri.encodeComponent(deviceId)}/folder/${Uri.encodeComponent(folderId)}/preview?path=${Uri.encodeComponent(filePath)}';
    }
    return Uri.parse(uriStr);
  }

  /// 更新文件夹
  static Future<Folder> updateFolder({
    required String folderId,
    required String name,
    required String path,
    List<String>? sharedDevices,
  }) async {
    try {
      final data = await _put('/device/local/folders/${Uri.encodeComponent(folderId)}', {
        'id': folderId,
        'label': name,
        'path': path,
        if (sharedDevices != null) 'sharedDevices': sharedDevices,
      });
      
      return Folder(
        id: data['id'] ?? folderId,
        name: data['label'] ?? data['name'] ?? name,
        path: data['path'] ?? path,
        deviceId: 'local',
        isLocal: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        status: 'synced',
        fileCount: 0,
        totalSize: 0,
      );
    } catch (e) {
      debugPrint('更新文件夹失败: $e');
      throw Exception('更新文件夹失败: $e');
    }
  }

  /// 执行 PUT 请求
  static Future<Map<String, dynamic>> _put(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    await initialize();
    
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API PUT: $uri');
      debugPrint('API 请求体: ${json.encode(body)}');
      
      final response = await _httpClient.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      debugPrint('API 响应状态: ${response.statusCode}');
      debugPrint('API 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData is Map<String, dynamic> && jsonData['code'] == 0) {
          return jsonData;
        } else {
          return jsonData as Map<String, dynamic>;
        }
      } else {
        throw Exception('HTTP 错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API 请求失败: $e');
      rethrow;
    }
  }

  /// 执行 DELETE 请求
  static Future<void> _delete(String endpoint) async {
    await initialize();
    
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API DELETE: $uri');
      
      final response = await _httpClient.delete(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      debugPrint('API 响应状态: ${response.statusCode}');
      debugPrint('API 响应体: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('HTTP 错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API 请求失败: $e');
      rethrow;
    }
  }

  /// 删除文件夹（使用正确的端点）
  static Future<void> deleteFolder(String folderId) async {
    try {
      await _delete('/device/local/folders/${Uri.encodeComponent(folderId)}');
    } catch (e) {
      debugPrint('删除文件夹失败: $e');
      throw Exception('删除文件夹失败: $e');
    }
  }

  /// 删除设备
  static Future<void> removeDevice(String deviceId) async {
    try {
      await _ensureSyncthingReady();
      await _delete('/device/${Uri.encodeComponent(deviceId)}');
    } catch (e) {
      debugPrint('删除设备失败: $e');
      throw Exception('删除设备失败: $e');
    }
  }

  /// 获取设备列表（原始 JSON）
  static Future<List<Map<String, dynamic>>> getDevicesRaw() async {
    final resp = await _get('/devices');
    return ((resp['data'] as List?)?.cast<Map<String, dynamic>>()) ?? [];
  }

  /// 获取设备文件夹列表（原始 JSON）
  static Future<List<Map<String, dynamic>>> getDeviceFoldersRaw(String deviceId) async {
    final resp = await _get('/device/$deviceId/folders');
    return ((resp['data'] as List?)?.cast<Map<String, dynamic>>()) ?? [];
  }

  /// 更新文件夹共享设备列表
  static Future<void> shareFolder(String folderId, List<String> sharedDevices) async {
    await _post('/folder/$folderId/sharing', {'sharedDevices': sharedDevices});
  }

  /// 获取文件夹 ACL（deviceId → sync|readonly|hidden）
  static Future<Map<String, String>> getFolderAcl(String folderId) async {
    final resp = await _get('/folder/${Uri.encodeComponent(folderId)}/acl');
    if (resp['code'] != 0) {
      throw Exception(resp['data']?.toString() ?? '获取权限失败');
    }
    final data = resp['data'];
    if (data is! Map) return {};
    final perms = data['permissions'];
    if (perms is! Map) return {};
    return {
      for (final e in perms.entries) e.key.toString(): e.value.toString(),
    };
  }

  /// 保存文件夹 ACL
  static Future<void> setFolderAcl(
    String folderId,
    Map<String, String> permissions,
  ) async {
    await _post('/folder/${Uri.encodeComponent(folderId)}/acl', {
      'permissions': permissions,
    });
  }

  /// 文件夹设置（类型 / 暂停）
  static Future<Map<String, dynamic>> getFolderSettings(String folderId) async {
    final resp = await _get('/folder/${Uri.encodeComponent(folderId)}/settings');
    if (resp['code'] != 0) {
      throw Exception(resp['data']?.toString() ?? '获取文件夹设置失败');
    }
    return Map<String, dynamic>.from(resp['data'] as Map? ?? {});
  }

  static Future<void> updateFolderSettings(
    String folderId, {
    String? type,
    bool? paused,
  }) async {
    await _put('/folder/${Uri.encodeComponent(folderId)}/settings', {
      if (type != null) 'type': type,
      if (paused != null) 'paused': paused,
    });
  }

  /// 忽略规则（每行一条）
  static Future<List<String>> getFolderIgnores(String folderId) async {
    final resp = await _get('/folder/${Uri.encodeComponent(folderId)}/ignores');
    if (resp['code'] != 0) {
      throw Exception(resp['data']?.toString() ?? '读取忽略规则失败');
    }
    final data = resp['data'];
    if (data is! Map) return [];
    final ignore = data['ignore'];
    if (ignore is! List) return [];
    return ignore.map((e) => e.toString()).toList();
  }

  static Future<void> setFolderIgnores(String folderId, List<String> lines) async {
    await _post('/folder/${Uri.encodeComponent(folderId)}/ignores', {
      'ignore': lines,
    });
  }

  static Future<void> scanFolder(String folderId) async {
    await _post('/folder/${Uri.encodeComponent(folderId)}/scan', {});
  }

  /// 失败 / 待同步 / 冲突 基础信息
  static Future<Map<String, dynamic>> getFolderIssues(String folderId) async {
    final resp = await _get('/folder/${Uri.encodeComponent(folderId)}/issues');
    if (resp['code'] != 0) {
      throw Exception(resp['data']?.toString() ?? '获取问题列表失败');
    }
    return Map<String, dynamic>.from(resp['data'] as Map? ?? {});
  }
}
