import 'dart:async';
import 'package:flutter/foundation.dart';
import '../backend/syncthing_api.dart';
import 'native_service.dart';

/// Syncthing 引擎生命周期：ready / restarting / unavailable
enum SyncthingLifecycleState { ready, restarting, unavailable }

/// 全局协调器，避免权限重启与添加设备/写 config/事件轮询并发
class SyncthingLifecycle {
  SyncthingLifecycle._();
  static final SyncthingLifecycle instance = SyncthingLifecycle._();

  SyncthingLifecycleState _state = SyncthingLifecycleState.ready;
  Future<bool>? _restartFuture;

  final _stateController = StreamController<SyncthingLifecycleState>.broadcast();

  SyncthingLifecycleState get state => _state;
  bool get isRestarting => _state == SyncthingLifecycleState.restarting;
  bool get isReady => _state == SyncthingLifecycleState.ready;

  Stream<SyncthingLifecycleState> get stateChanges => _stateController.stream;

  void _setState(SyncthingLifecycleState next) {
    if (_state == next) return;
    _state = next;
    debugPrint('[SyncthingLifecycle] => $next');
    _stateController.add(next);
  }

  /// 标记引擎已就绪（main 启动完成后可调用）
  void markReady() => _setState(SyncthingLifecycleState.ready);

  void markUnavailable() => _setState(SyncthingLifecycleState.unavailable);

  /// 串行化重启：停 → 启 → reloadConfig → 等到 API 可用
  Future<bool> requestRestart() {
    if (_restartFuture != null) return _restartFuture!;
    _restartFuture = _doRestart().whenComplete(() => _restartFuture = null);
    return _restartFuture!;
  }

  Future<bool> _doRestart() async {
    _setState(SyncthingLifecycleState.restarting);
    try {
      await NativeService.restartSyncthingService();
      return await waitUntilReady();
    } catch (e, st) {
      debugPrint('[SyncthingLifecycle] 重启失败: $e\n$st');
      _setState(SyncthingLifecycleState.unavailable);
      return false;
    }
  }

  /// 等待 Syncthing API 可用（含 myID）
  Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      SyncthingApi().reloadConfig();
      if (await NativeService.ensureSyncthingRunning()) {
        _setState(SyncthingLifecycleState.ready);
        return true;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    debugPrint('[SyncthingLifecycle] 等待就绪超时');
    _setState(SyncthingLifecycleState.unavailable);
    return false;
  }
}
