import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'syncthing_lifecycle.dart';

class SyncthingEvent {
  final int id;
  final int globalID;
  final String time;
  final String type;
  final Map<String, dynamic> data;

  SyncthingEvent({
    required this.id,
    this.globalID = 0,
    this.time = '',
    required this.type,
    required this.data,
  });

  factory SyncthingEvent.fromJson(Map<String, dynamic> json) {
    return SyncthingEvent(
      id: (json['id'] as num?)?.toInt() ?? 0,
      globalID: (json['globalID'] as num?)?.toInt() ?? 0,
      time: json['time']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      data: json['data'] is Map<String, dynamic> ? json['data'] as Map<String, dynamic> : {},
    );
  }
}

class EventService {
  static final EventService _instance = EventService._();
  factory EventService() => _instance;
  EventService._();

  int _lastEventId = 0;
  bool _isRunning = false;
  bool _cursorSynced = false;
  int _emptyCount = 0;
  int _unavailableBackoff = 10; // Syncthing 不可用时的退避秒数
  bool _loggedUnavailable = false;
  bool _pausedForRestart = false;
  StreamSubscription<SyncthingLifecycleState>? _lifecycleSub;

  final _eventController = StreamController<SyncthingEvent>.broadcast();
  Stream<SyncthingEvent> get events => _eventController.stream;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _cursorSynced = false;
    _lifecycleSub ??= SyncthingLifecycle.instance.stateChanges.listen((state) {
      if (state == SyncthingLifecycleState.restarting) {
        _pausedForRestart = true;
      } else if (state == SyncthingLifecycleState.ready) {
        if (_pausedForRestart) {
          _pausedForRestart = false;
          _cursorSynced = false;
          _emptyCount = 0;
          _loggedUnavailable = false;
          _unavailableBackoff = 10;
        }
      }
    });
    _poll();
  }

  /// Hot Restart 后 since=0 会重放历史事件；先同步到最新 ID，避免重复弹窗
  Future<void> _syncEventCursor() async {
    try {
      final events = await ApiService.getSyncthingEvents(since: 0, timeout: 0);
      for (final eventJson in events) {
        final event = SyncthingEvent.fromJson(eventJson);
        if (event.id > _lastEventId) _lastEventId = event.id;
      }
      if (_lastEventId > 0) {
        debugPrint('[EventService] 事件游标已同步至 $_lastEventId（跳过重放）');
      }
    } catch (e) {
      debugPrint('[EventService] 同步事件游标失败: $e');
    }
  }

  void stop() {
    _isRunning = false;
  }

  void _poll() async {
    if (!_cursorSynced) {
      await _syncEventCursor();
      _cursorSynced = true;
    }
    while (_isRunning) {
      if (_pausedForRestart || SyncthingLifecycle.instance.isRestarting) {
        await Future.delayed(const Duration(seconds: 2));
        continue;
      }
      try {
        final events = await ApiService.getSyncthingEvents(
          since: _lastEventId,
          timeout: 60,
        );
        if (!_isRunning) break;

        if (events.isEmpty) {
          _emptyCount++;
          if (_emptyCount > 3) {
            await Future.delayed(Duration(seconds: _unavailableBackoff));
          }
          continue;
        }
        _emptyCount = 0;
        _loggedUnavailable = false;
        _unavailableBackoff = 10;

        for (final eventJson in events) {
          final event = SyncthingEvent.fromJson(eventJson);
          if (event.id > _lastEventId) {
            _lastEventId = event.id;
            _eventController.add(event);
          }
        }
      } catch (e) {
        if (!_loggedUnavailable) {
          debugPrint('事件轮询失败: $e');
          _loggedUnavailable = true;
        }
        if (!_isRunning) break;
        _unavailableBackoff = (_unavailableBackoff * 2).clamp(10, 60);
        await Future.delayed(Duration(seconds: _unavailableBackoff));
      }
    }
  }

  void dispose() {
    stop();
    _lifecycleSub?.cancel();
    _lifecycleSub = null;
    _eventController.close();
  }
}
