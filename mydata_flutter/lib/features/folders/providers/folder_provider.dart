import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/models/folder.dart';
import '../../../core/services/api_service.dart';

class FolderProvider with ChangeNotifier {
  List<Folder> _folders = [];
  bool _isLoading = false;
  String? _error;
  String? _loadedDeviceId;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const int _maxRetries = 12;

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
        _retryCount = 0;
        notifyListeners();
      }

      final folders = await ApiService.getDeviceFolders(deviceId);
      _folders = folders;
      _loadedDeviceId = deviceId;
      if (silent) _error = null;

      // Syncthing 启动中可能暂时为空或统计未就绪，自动重试
      if (_needsStartupRetry(folders)) {
        _scheduleRetry(deviceId);
      } else {
        _retryTimer?.cancel();
        _retryTimer = null;
        _retryCount = 0;
      }
    } catch (e) {
      _error = e.toString();
      // 远程失败时清空列表，避免残留本机过滤结果
      _folders = [];
      _loadedDeviceId = deviceId;
      _scheduleRetry(deviceId);
    } finally {
      if (!silent) _isLoading = false;
      notifyListeners();
    }
  }

  bool _needsStartupRetry(List<Folder> folders) {
    // 仅本机：启动中空列表或统计未就绪时重试
    // 远程空列表可能是真实空，由对端 API 决定，不再盲重试
    if (_loadedDeviceId == null) return folders.isEmpty;
    // 粗略：远程错误会走 catch；此处只对「全 unknown」重试（本机 Syncthing 未就绪）
    if (folders.isEmpty) return true;
    return folders.every((f) => f.status == 'unknown');
  }

  void _scheduleRetry(String deviceId) {
    if (_retryCount >= _maxRetries) return;
    if (_loadedDeviceId != null && _loadedDeviceId != deviceId) return;
    // 远程对端不可达时不要疯狂重试（错误信息已展示）
    final err = _error ?? '';
    if (err.contains('对端') ||
        err.contains('离线') ||
        err.contains('未配对') ||
        err.contains('未运行')) {
      return;
    }
    _retryTimer?.cancel();
    final delaySec = (_retryCount < 3) ? 2 : 3;
    _retryCount++;
    debugPrint('[folders] Syncthing 未就绪，${delaySec}s 后重试 ($_retryCount/$_maxRetries)');
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      if (_loadedDeviceId == deviceId || _loadedDeviceId == null) {
        fetchDeviceFolders(deviceId, silent: true);
      }
    });
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

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}
