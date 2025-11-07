import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/folder.dart';
import '../models/device.dart';
import 'native_service.dart';

/// API 服务，调用 Android HTTPS API 服务器
class ApiService {
  static String _baseUrl = 'https://127.0.0.1:8443/api';
  static bool _initialized = false;

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
      
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('请求超时');
        },
      );

      debugPrint('API 响应状态: ${response.statusCode}');
      debugPrint('API 响应体: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        // 检查响应格式：{"success": true, "data": ...}
        if (jsonData is Map<String, dynamic> && jsonData['success'] == true) {
          final data = jsonData['data'];
          // data 可能是数组或对象
          if (data is List) {
            return {'list': data};
          } else if (data is Map<String, dynamic>) {
            return data;
          } else {
            return {'list': []};
          }
        } else if (jsonData is List) {
          // 如果直接返回数组，包装成标准格式
          return {'list': jsonData};
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
      
      final response = await http.post(
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
      final data = await _get('/devices');
      
      // 处理响应格式：可能是 {"list": [...]} 或直接是数组
      List<dynamic> deviceList;
      if (data.containsKey('list')) {
        deviceList = data['list'] as List<dynamic>;
      } else {
        // 如果返回的是单个对象，尝试转换为列表
        deviceList = [data];
      }
      
      return deviceList.map((json) {
        // 适配 Android API 返回的数据格式
        return Device(
          id: json['id'] ?? '',
          name: json['name'] ?? 'Unknown Device',
          type: _getDeviceType(json),
          isLocal: json['isLocal'] ?? false,
          status: json['status'] ?? (json['connected'] == true ? 'online' : 'offline'),
          lastSeen: DateTime.now(), // Android API 可能不返回此字段
          version: json['clientVersion'] ?? '',
          folders: List<String>.from(json['folders'] ?? []),
        );
      }).toList();
    } catch (e) {
      debugPrint('获取设备列表失败: $e');
      throw Exception('获取设备列表失败: $e');
    }
  }

  /// 根据设备信息推断设备类型
  static String _getDeviceType(Map<String, dynamic> json) {
    final name = (json['name'] ?? '').toLowerCase();
    if (name.contains('android') || name.contains('mobile')) {
      return 'mobile';
    } else if (name.contains('server')) {
      return 'server';
    } else {
      return 'desktop';
    }
  }

  /// 获取设备文件夹
  static Future<List<Folder>> getDeviceFolders(String deviceId) async {
    try {
      final data = await _get('/device/$deviceId/folders');
      
      List<dynamic> folderList;
      if (data.containsKey('list')) {
        folderList = data['list'] as List<dynamic>;
      } else {
        folderList = [data];
      }
      
      return folderList.map((json) {
        // 适配 Android API 返回的数据格式
        return Folder(
          id: json['id'] ?? '',
          name: json['label'] ?? json['name'] ?? 'Unknown Folder',
          path: json['path'] ?? '',
          deviceId: deviceId,
          isLocal: true, // 从设备获取的文件夹都是本地的
          createdAt: DateTime.now(), // Android API 可能不返回此字段
          updatedAt: DateTime.now(), // Android API 可能不返回此字段
          status: 'synced', // 默认状态
          fileCount: 0, // 需要单独获取
          totalSize: 0, // 需要单独获取
        );
      }).toList();
    } catch (e) {
      debugPrint('获取设备文件夹失败: $e');
      throw Exception('获取设备文件夹失败: $e');
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
      final data = await _get('/local-device-id');
      return data['deviceId'] ?? '';
    } catch (e) {
      debugPrint('获取本地设备 ID 失败: $e');
      throw Exception('获取本地设备 ID 失败: $e');
    }
  }

  /// 创建文件夹
  static Future<Folder> createFolder({
    required String name,
    required String path,
  }) async {
    try {
      final data = await _post('/folders', {
        'name': name,
        'path': path,
      });
      
      // 适配 Android API 返回的数据格式
      return Folder(
        id: data['id'] ?? '',
        name: data['label'] ?? data['name'] ?? name,
        path: data['path'] ?? path,
        deviceId: await getLocalDeviceId(),
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

  /// 删除文件夹
  static Future<void> deleteFolder(String folderId) async {
    try {
      await http.delete(
        Uri.parse('$_baseUrl/folders/$folderId'),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('删除文件夹失败: $e');
      throw Exception('删除文件夹失败: $e');
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
  static Future<List<Map<String, dynamic>>> getFolderFiles(String folderId) async {
    try {
      final data = await _get('/folder/$folderId/files');
      
      List<dynamic> fileList;
      if (data.containsKey('list')) {
        fileList = data['list'] as List<dynamic>;
      } else {
        fileList = [];
      }
      
      return fileList.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('获取文件夹文件列表失败: $e');
      throw Exception('获取文件夹文件列表失败: $e');
    }
  }
}
