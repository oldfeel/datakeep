import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_notification.dart';

/// 本机消息 SQLite（保留 30 天，不同步）
class NotificationRepository {
  NotificationRepository._();
  static final NotificationRepository instance = NotificationRepository._();

  static const _dbName = 'notifications.db';
  static const _table = 'notifications';
  static const retention = Duration(days: 30);
  static const pageSize = 20;

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE $_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  read INTEGER NOT NULL DEFAULT 0
)
''');
        await db.execute(
          'CREATE INDEX idx_notifications_created ON $_table(created_at DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_notifications_cat_created ON $_table(category, created_at DESC)',
        );
      },
    );
  }

  Future<void> purgeExpired() async {
    final cutoff =
        DateTime.now().subtract(retention).millisecondsSinceEpoch;
    final db = await _database;
    final n = await db.delete(
      _table,
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    if (n > 0) {
      debugPrint('[notifications] 清理过期 $n 条');
    }
  }

  Future<AppNotification> insert({
    required AppNotificationCategory category,
    required String title,
  }) async {
    await purgeExpired();
    final db = await _database;
    final now = DateTime.now();
    final id = await db.insert(_table, {
      'category': category.dbValue,
      'title': title,
      'created_at': now.millisecondsSinceEpoch,
      'read': 0,
    });
    return AppNotification(
      id: id,
      category: category,
      title: title,
      createdAt: now,
      read: false,
    );
  }

  Future<List<AppNotification>> page({
    AppNotificationCategory? category,
    required int offset,
    int limit = pageSize,
  }) async {
    await purgeExpired();
    final db = await _database;
    final rows = await db.query(
      _table,
      where: category == null ? null : 'category = ?',
      whereArgs: category == null ? null : [category.dbValue],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(AppNotification.fromMap).toList();
  }

  Future<int> unreadCount() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE read = 0',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> markAllRead() async {
    final db = await _database;
    await db.update(_table, {'read': 1}, where: 'read = 0');
  }

  Future<void> clearAll() async {
    final db = await _database;
    await db.delete(_table);
  }
}
