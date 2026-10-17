import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// 带库内序号的气泡（分页用）
class AiChatBubbleRow {
  AiChatBubbleRow({required this.seq, required this.payload});

  final int seq;
  final Map<String, dynamic> payload;
}

class AiChatPage {
  AiChatPage({
    required this.bubbles,
    required this.hasMore,
    this.messages = const [],
  });

  final List<AiChatBubbleRow> bubbles;
  final bool hasMore;
  /// 仅首页携带，供继续对话
  final List<Map<String, dynamic>> messages;
}

/// AI 对话历史：SQLite 分页（本机，不进同步目录）
class AiChatHistoryStore {
  AiChatHistoryStore._();

  static const _dbName = 'ai_chat.db';
  static const _prefsPrefix = 'ai_chat_v1_';
  static const pageSize = 20;
  /// 继续对话时载入的 messages 条数（过大易卡主线程）
  static const messagePageSize = 40;
  static const maxMessages = 200;

  static Database? _db;
  static Future<Database>? _opening;
  static final Set<String> _migratedPrefs = {};
  /// 最近一次失败原因（供 UI 展示，避免乱猜）
  static String? lastError;

  static void _log(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint('[AiChat] $message${error != null ? ' | $error' : ''}');
    developer.log(
      message,
      name: 'AiChat',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static Future<Database> get _database async {
    if (_db != null) return _db!;
    _opening ??= _open().then((db) {
      _db = db;
      _log('数据库已打开');
      return db;
    }, onError: (Object e, StackTrace st) {
      _opening = null;
      lastError = '打开数据库失败: $e';
      _log('打开数据库失败', error: e, stackTrace: st);
      Error.throwWithStackTrace(e, st);
    });
    return _opening!;
  }

  static Future<Database> _open() async {
    // 与通知库一致：放应用文档目录
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _log('准备打开数据库 path=$path');
    try {
      final db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
CREATE TABLE sessions (
  app_id TEXT PRIMARY KEY,
  updated_at INTEGER NOT NULL
)
''');
          await db.execute('''
CREATE TABLE bubbles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  app_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  UNIQUE(app_id, seq)
)
''');
          await db.execute('''
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  app_id TEXT NOT NULL,
  seq INTEGER NOT NULL,
  role TEXT NOT NULL,
  payload TEXT NOT NULL,
  UNIQUE(app_id, seq)
)
''');
          await db.execute(
            'CREATE INDEX idx_ai_bubbles_app ON bubbles(app_id, seq)',
          );
          await db.execute(
            'CREATE INDEX idx_ai_messages_app ON messages(app_id, seq)',
          );
        },
        onOpen: (db) {
          _log('onOpen ok');
        },
      );
      return db;
    } catch (e, st) {
      lastError = 'openDatabase 异常: $e';
      _log('openDatabase 异常 path=$path', error: e, stackTrace: st);
      rethrow;
    }
  }

  static String _normAppId(String appId) {
    final id = appId.trim();
    return id.isEmpty ? '_unknown' : id;
  }

  static Future<void> ensureMigrated(String appId) async {
    await _migratePrefsIfNeeded(_normAppId(appId));
  }

  /// 最近一页气泡（时间上最新）+ 近期 messages
  ///
  /// 无记录时返回空列表（不是错误）。打开失败会抛异常。
  static Future<AiChatPage> loadRecent(
    String appId, {
    int limit = pageSize,
  }) async {
    final id = _normAppId(appId);
    lastError = null;
    _log('loadRecent 开始 appId=$id limit=$limit');
    // 旧 prefs 迁移放到后台，不阻塞首屏
    unawaited(() async {
      try {
        await _migratePrefsIfNeeded(id);
      } catch (e, st) {
        _log('prefs 迁移跳过', error: e, stackTrace: st);
      }
    }());

    try {
      final db = await _database;
      final rows = await db.query(
        'bubbles',
        where: 'app_id = ?',
        whereArgs: [id],
        orderBy: 'seq DESC',
        limit: limit,
      );
      _log('bubbles 查询到 ${rows.length} 行');
      final bubbles = _decodeBubbleRows(rows.reversed.toList());
      _log('bubbles 解码成功 ${bubbles.length} 条');
      final hasMore = bubbles.isEmpty
          ? false
          : await _hasOlder(db, id, bubbles.first.seq);

      final messages = await _loadMessages(db, id);
      _log(
        'loadRecent 完成 bubbles=${bubbles.length} messages=${messages.length} hasMore=$hasMore',
      );
      return AiChatPage(
        bubbles: bubbles,
        hasMore: hasMore,
        messages: messages,
      );
    } catch (e, st) {
      lastError = e.toString();
      _log('loadRecent 失败 appId=$id', error: e, stackTrace: st);
      rethrow;
    }
  }

  /// 加载更早一页：seq < beforeSeq
  static Future<AiChatPage> loadOlder(
    String appId, {
    required int beforeSeq,
    int limit = pageSize,
  }) async {
    final id = _normAppId(appId);
    final db = await _database;
    final rows = await db.query(
      'bubbles',
      where: 'app_id = ? AND seq < ?',
      whereArgs: [id, beforeSeq],
      orderBy: 'seq DESC',
      limit: limit,
    );
    final bubbles = _decodeBubbleRows(rows.reversed.toList());
    final hasMore = bubbles.isEmpty
        ? false
        : await _hasOlder(db, id, bubbles.first.seq);
    return AiChatPage(bubbles: bubbles, hasMore: hasMore);
  }

  static Future<bool> _hasOlder(Database db, String appId, int oldestSeq) async {
    final r = await db.rawQuery(
      'SELECT 1 FROM bubbles WHERE app_id = ? AND seq < ? LIMIT 1',
      [appId, oldestSeq],
    );
    return r.isNotEmpty;
  }

  static List<AiChatBubbleRow> _decodeBubbleRows(List<Map<String, Object?>> rows) {
    final out = <AiChatBubbleRow>[];
    for (final row in rows) {
      try {
        final seq = row['seq'] as int? ?? 0;
        final decoded = jsonDecode(row['payload'] as String);
        if (decoded is Map) {
          final payload = Map<String, dynamic>.from(decoded);
          // 列表首屏不需要大段 thinking，展开时再靠已加载字段；先截断防卡
          final think = payload['thinking']?.toString();
          if (think != null && think.length > 1500) {
            payload['thinking'] = '${think.substring(0, 1500)}…';
          }
          out.add(AiChatBubbleRow(seq: seq, payload: payload));
        }
      } catch (_) {}
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _loadMessages(
    Database db,
    String appId,
  ) async {
    // 只取末尾若干条，避免一打开 AI 就解析整库 messages 卡死
    final messageRows = await db.query(
      'messages',
      where: 'app_id = ?',
      whereArgs: [appId],
      orderBy: 'seq DESC',
      limit: messagePageSize,
    );
    final messages = <Map<String, dynamic>>[];
    for (final row in messageRows.reversed) {
      try {
        final decoded = jsonDecode(row['payload'] as String);
        if (decoded is Map) {
          messages.add(_lightenMessage(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {}
    }
    return messages;
  }

  /// 载入时再截断一次，防止库里旧的大 payload 拖垮 UI
  static Map<String, dynamic> _lightenMessage(Map<String, dynamic> m) {
    final content = m['content'];
    if (content is String && content.length > 8000) {
      m['content'] =
          '${content.substring(0, 3000)}\n…\n${content.substring(content.length - 3000)}';
    }
    final tcs = m['tool_calls'];
    if (tcs is List) {
      m['tool_calls'] = [
        for (final tc in tcs)
          if (tc is Map) _trimToolCall(Map<String, dynamic>.from(tc)),
      ];
    }
    return m;
  }

  /// 追加尚未入库的气泡，并整体替换 messages（继续对话上下文）
  static Future<List<int>> appendBubblesAndSaveMessages({
    required String appId,
    required List<Map<String, dynamic>> newBubbles,
    required List<Map<String, dynamic>> messages,
  }) async {
    final id = _normAppId(appId);
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final assigned = <int>[];

    await db.transaction((txn) async {
      final maxRow = await txn.rawQuery(
        'SELECT MAX(seq) AS m FROM bubbles WHERE app_id = ?',
        [id],
      );
      var next = ((maxRow.first['m'] as int?) ?? 0) + 1;

      for (final b in newBubbles) {
        final seq = next++;
        assigned.add(seq);
        await txn.insert('bubbles', {
          'app_id': id,
          'seq': seq,
          'kind': b['kind']?.toString() ?? '',
          'payload': jsonEncode(b),
        });
      }

      var msgs = sanitizeMessages(messages);
      if (msgs.length > maxMessages) {
        msgs = _trimMessages(msgs, keep: maxMessages);
      }
      await txn.delete('messages', where: 'app_id = ?', whereArgs: [id]);
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        await txn.insert('messages', {
          'app_id': id,
          'seq': i,
          'role': m['role']?.toString() ?? '',
          'payload': jsonEncode(m),
        });
      }

      await txn.insert(
        'sessions',
        {'app_id': id, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    return assigned;
  }

  /// 更新已有气泡内容（如结束后的思考摘要）
  static Future<void> updateBubblePayload({
    required String appId,
    required int seq,
    required Map<String, dynamic> payload,
  }) async {
    final id = _normAppId(appId);
    final db = await _database;
    await db.update(
      'bubbles',
      {
        'kind': payload['kind']?.toString() ?? '',
        'payload': jsonEncode(payload),
      },
      where: 'app_id = ? AND seq = ?',
      whereArgs: [id, seq],
    );
  }

  /// 全量写入（迁移用）
  static Future<void> replaceAll({
    required String appId,
    required List<Map<String, dynamic>> bubbles,
    required List<Map<String, dynamic>> messages,
  }) async {
    final id = _normAppId(appId);
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch;
    var msgs = sanitizeMessages(messages);
    if (msgs.length > maxMessages) {
      msgs = _trimMessages(msgs, keep: maxMessages);
    }
    await db.transaction((txn) async {
      await txn.delete('bubbles', where: 'app_id = ?', whereArgs: [id]);
      await txn.delete('messages', where: 'app_id = ?', whereArgs: [id]);
      await txn.insert(
        'sessions',
        {'app_id': id, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (var i = 0; i < bubbles.length; i++) {
        final b = bubbles[i];
        await txn.insert('bubbles', {
          'app_id': id,
          'seq': i + 1,
          'kind': b['kind']?.toString() ?? '',
          'payload': jsonEncode(b),
        });
      }
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        await txn.insert('messages', {
          'app_id': id,
          'seq': i,
          'role': m['role']?.toString() ?? '',
          'payload': jsonEncode(m),
        });
      }
    });
  }

  static Future<void> clear(String appId) async {
    final id = _normAppId(appId);
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('bubbles', where: 'app_id = ?', whereArgs: [id]);
      await txn.delete('messages', where: 'app_id = ?', whereArgs: [id]);
      await txn.delete('sessions', where: 'app_id = ?', whereArgs: [id]);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsPrefix$id');
    } catch (_) {}
  }

  static Future<void> _migratePrefsIfNeeded(String appId) async {
    if (_migratedPrefs.contains(appId)) return;
    _migratedPrefs.add(appId);
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsPrefix$appId';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;

      final db = await _database;
      final existing = await db.query(
        'sessions',
        where: 'app_id = ?',
        whereArgs: [appId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        await prefs.remove(key);
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final bubbles = <Map<String, dynamic>>[];
      final rawB = map['bubbles'];
      if (rawB is List) {
        for (final e in rawB) {
          if (e is Map) bubbles.add(Map<String, dynamic>.from(e));
        }
      }
      final messages = <Map<String, dynamic>>[];
      final rawM = map['messages'];
      if (rawM is List) {
        for (final e in rawM) {
          if (e is Map) messages.add(Map<String, dynamic>.from(e));
        }
      }
      if (bubbles.isEmpty && messages.isEmpty) {
        await prefs.remove(key);
        return;
      }
      await replaceAll(appId: appId, bubbles: bubbles, messages: messages);
      await prefs.remove(key);
      debugPrint('[AiChat] 已从 SharedPreferences 迁移: $appId');
    } catch (e) {
      debugPrint('[AiChat] 迁移失败 $appId: $e');
    }
  }

  static List<Map<String, dynamic>> sanitizeMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final m in messages) {
      final copy = Map<String, dynamic>.from(m);
      final role = copy['role']?.toString() ?? '';
      if (role == 'system') {
        out.add(copy);
        continue;
      }
      final content = copy['content'];
      if (content is String && content.length > 24000) {
        copy['content'] =
            '${content.substring(0, 8000)}\n…\n${content.substring(content.length - 8000)}';
      }
      final tcs = copy['tool_calls'];
      if (tcs is List) {
        copy['tool_calls'] = [
          for (final tc in tcs)
            if (tc is Map) _trimToolCall(Map<String, dynamic>.from(tc)),
        ];
      }
      out.add(copy);
    }
    return out;
  }

  static Map<String, dynamic> _trimToolCall(Map<String, dynamic> tc) {
    final fn = tc['function'];
    if (fn is Map) {
      final f = Map<String, dynamic>.from(fn);
      final args = f['arguments']?.toString() ?? '';
      if (args.length > 8000) {
        f['arguments'] = '${args.substring(0, 4000)}…(截断)';
      }
      tc['function'] = f;
    }
    return tc;
  }

  static List<Map<String, dynamic>> _trimMessages(
    List<Map<String, dynamic>> messages, {
    required int keep,
  }) {
    if (messages.length <= keep) return messages;
    final system = <Map<String, dynamic>>[];
    final rest = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m['role']?.toString() == 'system' && system.isEmpty) {
        system.add(m);
      } else {
        rest.add(m);
      }
    }
    final restKeep = keep - system.length;
    if (rest.length <= restKeep) return [...system, ...rest];
    return [...system, ...rest.sublist(rest.length - restKeep)];
  }
}
