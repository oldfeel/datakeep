import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import 'notification_repository.dart';

/// 未读数与写入入口（列表分页由页面直接查 Repository）
class AppNotificationStore extends ChangeNotifier {
  AppNotificationStore() {
    unawaited(refreshUnread());
  }

  final NotificationRepository _repo = NotificationRepository.instance;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  Timer? _itemFinishedFlushTimer;
  int _itemFinishedBurst = 0;

  Future<void> refreshUnread() async {
    try {
      _unreadCount = await _repo.unreadCount();
      notifyListeners();
    } catch (e) {
      debugPrint('[notifications] 刷新未读失败: $e');
    }
  }

  Future<void> add({
    required AppNotificationCategory category,
    required String title,
  }) async {
    try {
      await _repo.insert(category: category, title: title);
      await refreshUnread();
    } catch (e) {
      debugPrint('[notifications] 写入失败: $e');
    }
  }

  /// 大批量 ItemFinished 合并提示
  void noteItemFinished() {
    _itemFinishedBurst++;
    _itemFinishedFlushTimer?.cancel();
    _itemFinishedFlushTimer = Timer(const Duration(seconds: 2), () {
      final n = _itemFinishedBurst;
      _itemFinishedBurst = 0;
      if (n <= 0) return;
      unawaited(add(
        category: AppNotificationCategory.sync,
        title: n == 1 ? '文件同步完成' : '已同步 $n 个文件',
      ));
    });
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await refreshUnread();
  }

  Future<void> clearAll() async {
    await _repo.clearAll();
    await refreshUnread();
  }

  @override
  void dispose() {
    _itemFinishedFlushTimer?.cancel();
    super.dispose();
  }
}
