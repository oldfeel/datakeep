import 'package:flutter/foundation.dart';
import 'native_service.dart';

/// Syncthing 服务管理器
class SyncthingServiceManager extends ChangeNotifier {
  String _status = 'unknown';
  bool _isRunning = false;

  String get status => _status;
  bool get isRunning => _isRunning;

  SyncthingServiceManager() {
    _checkStatus();
  }

  /// 检查服务状态
  Future<void> _checkStatus() async {
    try {
      final status = await NativeService.getServiceStatus();
      _status = status;
      _isRunning = status == 'active' || status == 'running';
      notifyListeners();
    } catch (e) {
      debugPrint('检查服务状态失败: $e');
      _status = 'unknown';
      _isRunning = false;
      notifyListeners();
    }
  }

  /// 启动服务
  Future<bool> start() async {
    try {
      final success = await NativeService.startSyncthingService();
      if (success) {
        _isRunning = true;
        _status = 'starting';
        notifyListeners();
        
        // 等待一段时间后再次检查状态
        await Future.delayed(const Duration(seconds: 2));
        await _checkStatus();
      }
      return success;
    } catch (e) {
      debugPrint('启动服务失败: $e');
      _status = 'error';
      _isRunning = false;
      notifyListeners();
      return false;
    }
  }

  /// 停止服务
  Future<bool> stop() async {
    try {
      final success = await NativeService.stopSyncthingService();
      if (success) {
        _isRunning = false;
        _status = 'stopping';
        notifyListeners();
        
        // 等待一段时间后再次检查状态
        await Future.delayed(const Duration(seconds: 1));
        await _checkStatus();
      }
      return success;
    } catch (e) {
      debugPrint('停止服务失败: $e');
      _status = 'error';
      notifyListeners();
      return false;
    }
  }

  /// 刷新状态
  Future<void> refresh() async {
    await _checkStatus();
  }
}

