import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android 存储：All files access、SAF 选目录、native 写测试（对齐 Syncthing Android）
class AndroidStorageService {
  static const MethodChannel _channel = MethodChannel('tech.shupi.datakeep/api');

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 是否已授予 All files access（Android 11+）或 WRITE_EXTERNAL_STORAGE（旧版）
  static Future<bool> hasAllFilesAccess() async {
    if (!isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (e) {
      debugPrint('[AndroidStorage] hasAllFilesAccess 失败: $e');
      return false;
    }
  }

  /// 打开系统「允许访问所有文件」设置页
  static Future<void> requestAllFilesAccess() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('requestAllFilesAccess');
    } catch (e) {
      debugPrint('[AndroidStorage] requestAllFilesAccess 失败: $e');
    }
  }

  /// 模拟 Syncthing native 进程写权限检测
  static Future<bool> canWriteToPath(String path) async {
    if (!isAndroid || path.isEmpty) return true;
    try {
      return await _channel.invokeMethod<bool>('canWriteToPath', {'path': path}) ?? false;
    } catch (e) {
      debugPrint('[AndroidStorage] canWriteToPath 失败: $e');
      return false;
    }
  }

  /// 默认同步目录：Android/media/<pkg>/sync/<folderId>
  static Future<String> getDefaultSyncFolderPath(String folderId) async {
    if (!isAndroid) return '';
    try {
      final path = await _channel.invokeMethod<String>(
        'getDefaultSyncFolderPath',
        {'folderId': folderId},
      );
      return path ?? '';
    } catch (e) {
      debugPrint('[AndroidStorage] getDefaultSyncFolderPath 失败: $e');
      return '';
    }
  }

  /// SAF 选择同步目录，返回绝对路径与是否可写
  static Future<({String path, bool writable})?> pickSyncFolder() async {
    if (!isAndroid) return null;
    try {
      final result = await _channel.invokeMethod('pickSyncFolder');
      if (result == null) return null;
      if (result is Map) {
        final path = result['path']?.toString() ?? '';
        if (path.isEmpty) return null;
        final writable = result['writable'] == true;
        return (path: path, writable: writable);
      }
    } on PlatformException catch (e) {
      debugPrint('[AndroidStorage] pickSyncFolder: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[AndroidStorage] pickSyncFolder 失败: $e');
    }
    return null;
  }
}
