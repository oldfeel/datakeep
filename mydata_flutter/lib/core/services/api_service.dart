import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/folder.dart';
import '../models/device.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api';
  
  // 获取所有文件夹
  static Future<List<Folder>> getFolders() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/folders'));
      
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Folder.fromJson(json)).toList();
      } else {
        throw Exception('获取文件夹失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
  
  // 创建文件夹
  static Future<Folder> createFolder({
    required String name,
    required String path,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/folders'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'path': path,
        }),
      );
      
      if (response.statusCode == 201) {
        return Folder.fromJson(json.decode(response.body));
      } else {
        throw Exception('创建文件夹失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
  
  // 删除文件夹
  static Future<void> deleteFolder(String folderId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/folders/$folderId'),
      );
      
      if (response.statusCode != 204) {
        throw Exception('删除文件夹失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
  
  // 获取所有设备
  static Future<List<Device>> getDevices() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/devices'));
      
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => Device.fromJson(json)).toList();
      } else {
        throw Exception('获取设备失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
  
  // 获取同步状态
  static Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/sync/status'));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('获取同步状态失败: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求失败: $e');
    }
  }
}
