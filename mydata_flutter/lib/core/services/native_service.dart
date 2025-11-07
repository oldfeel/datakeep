import 'package:flutter/services.dart';

/// Platform Channel 服务，用于与 Android 原生代码通信
class NativeService {
  static const MethodChannel _channel = MethodChannel('tech.shupi.mydata/api');

  /// 启动 Syncthing 服务
  static Future<bool> startSyncthingService() async {
    try {
      final result = await _channel.invokeMethod<bool>('startSyncthingService');
      return result ?? false;
    } on PlatformException catch (e) {
      print('启动 Syncthing 服务失败: ${e.message}');
      return false;
    }
  }

  /// 停止 Syncthing 服务
  static Future<bool> stopSyncthingService() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopSyncthingService');
      return result ?? false;
    } on PlatformException catch (e) {
      print('停止 Syncthing 服务失败: ${e.message}');
      return false;
    }
  }

  /// 获取服务状态
  static Future<String> getServiceStatus() async {
    try {
      final result = await _channel.invokeMethod<String>('getServiceStatus');
      return result ?? 'unknown';
    } on PlatformException catch (e) {
      print('获取服务状态失败: ${e.message}');
      return 'unknown';
    }
  }

  /// 获取 API 基础 URL
  static Future<String> getApiBaseUrl() async {
    try {
      final result = await _channel.invokeMethod<String>('getApiBaseUrl');
      return result ?? 'https://127.0.0.1:8443/api';
    } on PlatformException catch (e) {
      print('获取 API URL 失败: ${e.message}');
      return 'https://127.0.0.1:8443/api';
    }
  }
}

