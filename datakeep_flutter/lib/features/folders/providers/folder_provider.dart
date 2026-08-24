import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/models/folder.dart';
import '../../../core/services/api_service.dart';
import '../../../shared/utils/app_dir.dart';
import '../../../shared/utils/peer_folder_error.dart';

class FolderProvider with ChangeNotifier {
  List<Folder> _folders = [];
  bool _isLoading = false;
  String? _error;
  String? _loadedDeviceId;
  Timer? _retryTimer;
  int _retryCount = 0;
  static const int _maxRetries = 12;
  static const int _maxPeerWaitRetries = 60;

  List<Folder> get folders => _folders;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get loadedDeviceId => _loadedDeviceId;

  PeerFolderErrorKind? get errorKind =>
      _error == null ? null : classifyPeerFolderError(_error);

  /// 等待对方同意配对 / 连上等（非硬错误）
  bool get isWaitingForPeer {
    final k = errorKind;
    return k == PeerFolderErrorKind.unpaired ||
        k == PeerFolderErrorKind.offline ||
        k == PeerFolderErrorKind.unreachable;
  }

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
      _error = null;

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
    // 空列表是合法状态（尚未添加文件夹），不要当成 Syncthing 未就绪
    if (folders.isEmpty) return false;
    // 有文件夹但统计全是 unknown：启动中，稍后重试
    return folders.every((f) => f.status == 'unknown');
  }

  void _scheduleRetry(String deviceId) {
    if (_loadedDeviceId != null && _loadedDeviceId != deviceId) return;

    final kind = classifyPeerFolderError(_error);
    final waitingPeer = _error != null && peerFolderErrorShouldAutoRetry(kind);
    // Syncthing 未运行：不重试
    if (_error != null && _error!.contains('未运行')) return;
    // 其它硬错误且非启动统计重试：不重试
    if (_error != null && !waitingPeer) return;

    final max = waitingPeer ? _maxPeerWaitRetries : _maxRetries;
    if (_retryCount >= max) return;

    _retryTimer?.cancel();
    final delaySec = waitingPeer ? 5 : ((_retryCount < 3) ? 2 : 3);
    _retryCount++;
    debugPrint(
      '[folders] ${waitingPeer ? "等待对端就绪" : "等待文件夹统计就绪"}，'
      '${delaySec}s 后重试 ($_retryCount/$max)',
    );
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      if (_loadedDeviceId == deviceId || _loadedDeviceId == null) {
        fetchDeviceFolders(deviceId, silent: true);
      }
    });
  }

  /// 删除文件夹/应用后刷新；API 可能短暂仍返回已删项，需再次剔除。
  Future<void> refreshAfterDelete({
    String? removedFolderId,
    String? removedPath,
    bool silent = true,
  }) async {
    _pruneFolders(removedFolderId: removedFolderId, removedPath: removedPath);

    final deviceId = _loadedDeviceId;
    if (deviceId != null) {
      await fetchDeviceFolders(deviceId, silent: silent);
    } else {
      await fetchFolders(silent: silent);
    }

    _pruneFolders(removedFolderId: removedFolderId, removedPath: removedPath);
  }

  void _pruneFolders({String? removedFolderId, String? removedPath}) {
    var changed = false;
    if (removedFolderId != null && removedFolderId.isNotEmpty) {
      final before = _folders.length;
      _folders.removeWhere((f) => f.id == removedFolderId);
      if (_folders.length != before) changed = true;
    }
    if (removedPath != null && removedPath.isNotEmpty) {
      final norm = normalizeFsPath(removedPath);
      final before = _folders.length;
      _folders.removeWhere((f) => normalizeFsPath(f.path) == norm);
      if (_folders.length != before) changed = true;
    }
    if (changed) notifyListeners();
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
    String kind = 'folder',
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final newFolder = await ApiService.createFolder(
        id: id,
        name: name,
        path: path,
        kind: kind,
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
