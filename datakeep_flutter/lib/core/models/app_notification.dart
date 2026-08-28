/// 应用内消息分类（本机 SQLite，不同步）
enum AppNotificationCategory {
  device,
  sync,
  system;

  String get dbValue => name;

  String get label {
    switch (this) {
      case AppNotificationCategory.device:
        return '设备';
      case AppNotificationCategory.sync:
        return '同步';
      case AppNotificationCategory.system:
        return '系统';
    }
  }

  static AppNotificationCategory? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final c in AppNotificationCategory.values) {
      if (c.name == raw) return c;
    }
    return null;
  }
}

class AppNotification {
  final int id;
  final AppNotificationCategory category;
  final String title;
  final DateTime createdAt;
  final bool read;

  const AppNotification({
    required this.id,
    required this.category,
    required this.title,
    required this.createdAt,
    required this.read,
  });

  factory AppNotification.fromMap(Map<String, Object?> map) {
    return AppNotification(
      id: map['id'] as int,
      category: AppNotificationCategory.tryParse(map['category'] as String?) ??
          AppNotificationCategory.system,
      title: map['title'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? 0,
      ),
      read: (map['read'] as int? ?? 0) == 1,
    );
  }
}
