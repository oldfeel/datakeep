import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import '../models/folder.dart';
import '../models/device.dart';
import 'native_service.dart';

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
  static Future<Map<String, dynamic>> _get(String endpoint) async {
    await initialize();
    
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('API GET: $uri');
      
      final response = await _httpClient.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('请求超时：后端服务可能未启动，请先启动 client 后端服务');
        },
      );

      debugPrint('API 响应状态: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('API 响应体: ${response.body}');
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
      } else {
        throw Exception('HTTP 错误: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('API 请求失败: $e');
      // 如果是连接被拒绝，提供更友好的错误信息
      final errorStr = e.toString();
      if (errorStr.contains('连接被拒绝') || 
          errorStr.contains('Connection refused') ||
          errorStr.contains('SocketException')) {
        throw Exception('无法连接到后端服务 (localhost:8443)\n\n请先启动后端服务：\ncd mydata_flutter/backend/cmd && go run main.go');
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
      return deviceList
          .where((item) => item is Map<String, dynamic>)
          .map((json) => Device.fromJson(json as Map<String, dynamic>))
          .toList();
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
      final response = await _get('/device/$validDeviceId/folders');
      
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
        return Folder(
          id: json['id'] ?? '',
          name: json['label'] ?? json['name'] ?? 'Unknown Folder',
          path: json['path'] ?? '',
          deviceId: deviceId,
          isLocal: deviceId == 'local',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          status: 'synced',
          fileCount: 0,
          totalSize: 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('获取设备文件夹失败: $e');
      return [];
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
        throw Exception('无法连接到后端服务\n\n请先启动 client 后端服务：\ncd client && go run main.go');
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

  /// 获取文件夹文件列表
  static Future<List<Map<String, dynamic>>> getFolderFiles(
    String folderId, {
    String? path,
  }) async {
    try {
      String endpoint = '/folder/${Uri.encodeComponent(folderId)}';
      if (path != null && path.isNotEmpty) {
        endpoint += '?path=${Uri.encodeComponent(path)}';
      }
      
      final response = await _get(endpoint);
      
      // 处理 client 后端响应格式
      List<dynamic> fileList;
      if (response.containsKey('code') && response['code'] == 0) {
        fileList = response['data'] as List<dynamic>? ?? [];
      } else if (response.containsKey('list')) {
        fileList = response['list'] as List<dynamic>;
      } else if (response.containsKey('data')) {
        fileList = response['data'] is List 
            ? response['data'] as List<dynamic>
            : [response['data']];
      } else {
        fileList = [];
      }
      
      return fileList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('获取文件夹文件列表失败: $e');
      return [];
    }
  }

  /// 添加设备
  static Future<void> addDevice({
    required String deviceID,
    required String name,
  }) async {
    try {
      await _post('/syncthing/config/devices', {
        'deviceID': deviceID.replaceAll(RegExp(r'[\s-]'), ''),
        'name': name,
        'addresses': ['dynamic'],
        'compression': 'metadata',
        'introducer': false,
        'autoAcceptFolders': false,
        'untrusted': false,
        'numConnections': 0,
        'maxRecvKbps': 0,
        'maxSendKbps': 0,
      });
    } catch (e) {
      debugPrint('添加设备失败: $e');
      throw Exception('添加设备失败: $e');
    }
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
      final response = await _get('/syncthing/events?since=$since&timeout=$timeout');
      
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
      debugPrint('获取 Syncthing 事件失败: $e');
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
  static Future<List<Map<String, String>>> getDiscoveredDevices() async {
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
          deviceNameMap[cleanId] = device.name;
        }
      } catch (e) {
        debugPrint('获取已配置设备列表失败（用于匹配名称）: $e');
      }
      
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
        
        // 尝试从已配置的设备中查找名称
        final cleanId = deviceId.replaceAll(RegExp(r'[\s-]'), '');
        final deviceName = deviceNameMap[cleanId] ?? deviceId;
        
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
  static Future<http.Response> previewFile(
    String folderId,
    String filePath,
  ) async {
    await initialize();
    
    final uri = Uri.parse('$_baseUrl/folder/${Uri.encodeComponent(folderId)}/preview?path=${Uri.encodeComponent(filePath)}');
    return await _httpClient.get(uri);
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
      await _delete('/device/${Uri.encodeComponent(deviceId)}');
    } catch (e) {
      debugPrint('删除设备失败: $e');
      throw Exception('删除设备失败: $e');
    }
  }
}
