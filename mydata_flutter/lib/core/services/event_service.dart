import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

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
  Timer? _reconnectTimer;
  int _emptyCount = 0;

  final _eventController = StreamController<SyncthingEvent>.broadcast();
  Stream<SyncthingEvent> get events => _eventController.stream;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _poll();
  }

  void stop() {
    _isRunning = false;
    _reconnectTimer?.cancel();
  }

  void _poll() async {
    while (_isRunning) {
      try {
        final events = await ApiService.getSyncthingEvents(
          since: _lastEventId,
          timeout: 60,
        );
        if (!_isRunning) break;

        if (events.isEmpty) {
          _emptyCount++;
          if (_emptyCount > 3) {
            await Future.delayed(const Duration(seconds: 10));
          }
          continue;
        }
        _emptyCount = 0;

        for (final eventJson in events) {
          final event = SyncthingEvent.fromJson(eventJson);
          if (event.id > _lastEventId) {
            _lastEventId = event.id;
            _eventController.add(event);
          }
        }
      } catch (e) {
        debugPrint('事件轮询失败: $e');
        if (!_isRunning) break;
        _reconnectTimer = Timer(const Duration(seconds: 10), () {
          if (_isRunning) _poll();
        });
        return;
      }
    }
  }

  void dispose() {
    stop();
    _eventController.close();
  }
}
