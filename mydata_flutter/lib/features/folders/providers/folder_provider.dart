import 'package:flutter/foundation.dart';
import '../../../core/models/folder.dart';
import '../../../core/services/api_service.dart';

class FolderProvider with ChangeNotifier {
  List<Folder> _folders = [];
  bool _isLoading = false;
  String? _error;
  String? _loadedDeviceId;

  List<Folder> get folders => _folders;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get loadedDeviceId => _loadedDeviceId;

  /// 加载指定设备的文件夹列表
  Future<void> fetchDeviceFolders(String deviceId, {bool silent = false}) async {
    try {
      if (!silent) {
        _isLoading = true;
        _error = null;
        notifyListeners();
      }

      final folders = await ApiService.getDeviceFolders(deviceId);
      _folders = folders;
      _loadedDeviceId = deviceId;
      if (silent) _error = null;

      // Syncthing 重启中可能暂时为空，自动重试
      if (folders.isEmpty && !silent) {
        Future.delayed(const Duration(seconds: 4), () {
          if (_loadedDeviceId == deviceId && _folders.isEmpty) {
            fetchDeviceFolders(deviceId, silent: true);
          }
        });
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) _isLoading = false;
      notifyListeners();
    }
  }

  // 获取所有文件夹（本机）
  Future<void> fetchFolders({bool silent = false}) async {
    try {
      final localDeviceId = await ApiService.getLocalDeviceId();
      await fetchDeviceFolders(localDeviceId, silent: silent);
    } catch (e) {
      _error = e.toString();
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  // 创建文件夹
  Future<void> createFolder({
    required String id,
    required String name,
    required String path,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final newFolder = await ApiService.createFolder(
        id: id,
        name: name,
        path: path,
      );
      
      _folders.add(newFolder);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 删除文件夹
  Future<void> deleteFolder(String folderId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await ApiService.deleteFolder(folderId);
      _folders.removeWhere((folder) => folder.id == folderId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 获取指定设备的文件夹（兼容旧调用，不更新 Provider 状态）
  Future<List<Folder>> getDeviceFolders(String deviceId) async {
    try {
      return await ApiService.getDeviceFolders(deviceId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
