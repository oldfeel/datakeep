import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/services/ai_settings_store.dart';

/// 对话过程事件（供 UI 展示思考/工具/流式正文）
enum AiChatEventKind {
  status,
  thinking,
  contentDelta,
  toolStart,
  toolResult,
}

class AiChatEvent {
  const AiChatEvent(this.kind, this.text, {this.detail});

  final AiChatEventKind kind;
  final String text;
  final String? detail;
}

/// 应用内 AI：OpenAI 兼容 chat（流式）+ 本地文件工具
class AppAiService {
  AppAiService({required this.codeRoot});

  final String codeRoot;

  static const _textExts = {
    '.html',
    '.htm',
    '.js',
    '.mjs',
    '.cjs',
    '.css',
    '.json',
    '.md',
    '.txt',
    '.svg',
    '.xml',
    '.csv',
    '.ts',
    '.tsx',
    '.vue',
    '.yaml',
    '.yml',
  };

  static const _blockedPrefixes = {
    'vendor/',
    'node_modules/',
    'seed/',
    'data/',
  };

  static const tools = [
    {
      'type': 'function',
      'function': {
        'name': 'list_files',
        'description': '列出应用包内相对路径下的文件与目录（不含 vendor/data/seed）',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': '相对 codeRoot 的目录，默认 "."',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': '读取包内文本文件全文',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': '相对路径'},
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'write_file',
        'description': '写入/覆盖包内文本文件；写后宿主会按 appRev 重载页面',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': '相对路径'},
            'content': {'type': 'string', 'description': '完整文件内容'},
          },
          'required': ['path', 'content'],
        },
      },
    },
  ];

  static String systemPrompt(String appName) => '''
你是 DataKeep 应用内助手，正在编辑「$appName」的无构建前端源码（HTML/JS/CSS 等）。
规则：
- 只能通过工具读写包内文本文件；不要编造未读过的大段代码。
- 禁止修改 vendor/、node_modules/、seed/、data/ 下文件。
- 改完用简短中文说明改了什么。
- 用户要改 UI/文案/交互时：先 list/read，再 write 完整文件内容。
''';

  String? _resolveSafe(String rel) {
    final cleaned = rel.trim().replaceAll('\\', '/');
    if (cleaned.isEmpty || cleaned == '.') {
      return p.normalize(codeRoot);
    }
    if (cleaned.startsWith('/') ||
        cleaned.contains('..') ||
        cleaned.startsWith('~')) {
      return null;
    }
    final abs = p.normalize(p.join(codeRoot, cleaned));
    final root = p.normalize(codeRoot);
    if (abs != root && !p.isWithin(root, abs)) return null;
    final relNorm = p.relative(abs, from: root).replaceAll('\\', '/');
    for (final b in _blockedPrefixes) {
      if (relNorm == b.substring(0, b.length - 1) ||
          relNorm.startsWith(b)) {
        return null;
      }
    }
    return abs;
  }

  String _relOf(String abs) =>
      p.relative(abs, from: codeRoot).replaceAll('\\', '/');

  bool _isTextPath(String path) {
    final ext = p.extension(path).toLowerCase();
    if (ext.isEmpty) return false;
    return _textExts.contains(ext);
  }

  Future<String> runTool(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'list_files':
        return _listFiles(args['path']?.toString() ?? '.');
      case 'read_file':
        return _readFile(args['path']?.toString() ?? '');
      case 'write_file':
        return _writeFile(
          args['path']?.toString() ?? '',
          args['content']?.toString() ?? '',
        );
      default:
        return '未知工具: $name';
    }
  }

  String _listFiles(String rel) {
    final abs = _resolveSafe(rel);
    if (abs == null) return '非法路径';
    final dir = Directory(abs);
    if (!dir.existsSync()) return '目录不存在';
    final lines = <String>[];
    for (final e in dir.listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      final r = _relOf(e.path);
      if (_blockedPrefixes
          .any((b) => r == b.replaceAll('/', '') || r.startsWith(b))) {
        continue;
      }
      if (e is Directory) {
        lines.add('$r/');
      } else {
        lines.add(r);
      }
    }
    lines.sort();
    if (lines.isEmpty) return '(空)';
    return lines.join('\n');
  }

  String _readFile(String rel) {
    final abs = _resolveSafe(rel);
    if (abs == null) return '非法或受保护路径';
    final f = File(abs);
    if (!f.existsSync()) return '文件不存在';
    if (!_isTextPath(abs)) return '仅支持文本文件';
    final len = f.lengthSync();
    if (len > 400 * 1024) return '文件过大（>${400}KB），拒绝读取';
    return f.readAsStringSync();
  }

  String _writeFile(String rel, String content) {
    final abs = _resolveSafe(rel);
    if (abs == null) return '非法或受保护路径，拒绝写入';
    if (!_isTextPath(abs)) return '仅支持写入文本扩展名';
    if (content.length > 800 * 1024) return '内容过大，拒绝写入';
    final f = File(abs);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
    return '已写入 ${_relOf(abs)}（${content.length} 字符）';
  }

  String _toolSummary(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'list_files':
        return 'list_files(${args['path'] ?? '.'})';
      case 'read_file':
        return 'read_file(${args['path'] ?? ''})';
      case 'write_file':
        final path = args['path']?.toString() ?? '';
        final len = args['content']?.toString().length ?? 0;
        return 'write_file($path, $len字)';
      default:
        return name;
    }
  }

  Future<ChatTurnResult> chat({
    required List<Map<String, dynamic>> messages,
    void Function(AiChatEvent event)? onEvent,
  }) async {
    final provider = await AiSettingsStore.getProvider();
    final key = await AiSettingsStore.getApiKey(provider);
    if (key.isEmpty) {
      throw StateError('请先在设置中填写 ${provider.label} API Key');
    }
    final model = await AiSettingsStore.getModel(provider);
    final base = switch (provider) {
      AiProvider.deepseek => 'https://api.deepseek.com',
      AiProvider.doubao => await AiSettingsStore.getDoubaoBaseUrl(),
    };
    final url = Uri.parse('$base/chat/completions');

    void emit(AiChatEventKind kind, String text, {String? detail}) {
      onEvent?.call(AiChatEvent(kind, text, detail: detail));
    }

    var msgs = List<Map<String, dynamic>>.from(messages);
    var wrote = false;
    String? lastAssistant;
    final thinkingBuf = StringBuffer();

    for (var round = 0; round < 8; round++) {
      emit(AiChatEventKind.status, '连接 ${provider.label}（$model）…');
      final streamed = await _streamCompletion(
        url: url,
        apiKey: key,
        model: model,
        messages: msgs,
        onDelta: (delta) {
          final reasoning = delta['reasoning_content']?.toString();
          if (reasoning != null && reasoning.isNotEmpty) {
            thinkingBuf.write(reasoning);
            emit(AiChatEventKind.thinking, reasoning);
          }
          final content = delta['content']?.toString();
          if (content != null && content.isNotEmpty) {
            emit(AiChatEventKind.contentDelta, content);
          }
        },
      );

      final assistant = streamed.message;
      msgs.add(assistant);
      lastAssistant = assistant['content']?.toString();
      if (thinkingBuf.isNotEmpty) {
        emit(AiChatEventKind.status, '思考完成');
      }

      final toolCalls = assistant['tool_calls'];
      if (toolCalls is! List || toolCalls.isEmpty) {
        return ChatTurnResult(
          messages: msgs,
          assistantText: lastAssistant?.trim().isNotEmpty == true
              ? lastAssistant!.trim()
              : '（无文本回复）',
          wroteFiles: wrote,
        );
      }

      emit(
        AiChatEventKind.status,
        '准备调用 ${toolCalls.length} 个工具…',
      );

      for (final raw in toolCalls) {
        if (raw is! Map) continue;
        final id = raw['id']?.toString() ?? '';
        final fn = raw['function'];
        if (fn is! Map) continue;
        final name = fn['name']?.toString() ?? '';
        Map<String, dynamic> args = {};
        final argStr = fn['arguments']?.toString() ?? '{}';
        try {
          final parsed = jsonDecode(argStr);
          if (parsed is Map) {
            args = Map<String, dynamic>.from(parsed);
          }
        } catch (_) {}
        final summary = _toolSummary(name, args);
        emit(AiChatEventKind.toolStart, summary);
        final result = await runTool(name, args);
        final preview = result.length > 180
            ? '${result.substring(0, 180)}…'
            : result;
        emit(AiChatEventKind.toolResult, summary, detail: preview);
        if (name == 'write_file' && result.startsWith('已写入')) {
          wrote = true;
        }
        msgs.add({
          'role': 'tool',
          'tool_call_id': id,
          'content': result,
        });
      }
      emit(AiChatEventKind.status, '工具完成，继续思考…');
    }

    return ChatTurnResult(
      messages: msgs,
      assistantText: lastAssistant?.trim().isNotEmpty == true
          ? lastAssistant!.trim()
          : '工具调用轮次过多，已停止',
      wroteFiles: wrote,
    );
  }

  /// 流式 chat/completions，组装完整 assistant message（含 tool_calls）
  Future<({Map<String, dynamic> message, String? finishReason})>
      _streamCompletion({
    required Uri url,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
    required void Function(Map<String, dynamic> delta) onDelta,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final req = await client.postUrl(url);
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      req.add(
        utf8.encode(
          jsonEncode({
            'model': model,
            'messages': messages,
            'tools': tools,
            'tool_choice': 'auto',
            'stream': true,
          }),
        ),
      );
      final res = await req.close().timeout(const Duration(seconds: 120));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final errBody = await res.transform(utf8.decoder).join();
        throw StateError(
          'API ${res.statusCode}: ${errBody.length > 400 ? errBody.substring(0, 400) : errBody}',
        );
      }

      final contentBuf = StringBuffer();
      final reasoningBuf = StringBuffer();
      final toolAcc = <int, _ToolAcc>{};
      String? finishReason;
      var lineBuf = '';

      await for (final chunk in res.transform(utf8.decoder)) {
        lineBuf += chunk;
        while (true) {
          final nl = lineBuf.indexOf('\n');
          if (nl < 0) break;
          var line = lineBuf.substring(0, nl);
          lineBuf = lineBuf.substring(nl + 1);
          line = line.trimRight();
          if (line.isEmpty || line.startsWith(':')) continue;
          if (!line.startsWith('data:')) continue;
          final data = line.substring(5).trimLeft();
          if (data == '[DONE]') continue;
          Map<String, dynamic>? decoded;
          try {
            final raw = jsonDecode(data);
            if (raw is Map<String, dynamic>) {
              decoded = raw;
            } else if (raw is Map) {
              decoded = Map<String, dynamic>.from(raw);
            }
          } catch (_) {
            continue;
          }
          if (decoded == null) continue;
          final choices = decoded['choices'];
          if (choices is! List || choices.isEmpty) continue;
          final choice = choices.first;
          if (choice is! Map) continue;
          finishReason = choice['finish_reason']?.toString() ?? finishReason;
          final delta = choice['delta'];
          if (delta is! Map) continue;
          final deltaMap = Map<String, dynamic>.from(delta);
          onDelta(deltaMap);

          final c = deltaMap['content']?.toString();
          if (c != null) contentBuf.write(c);
          final r = deltaMap['reasoning_content']?.toString();
          if (r != null) reasoningBuf.write(r);

          final tcs = deltaMap['tool_calls'];
          if (tcs is List) {
            for (final tc in tcs) {
              if (tc is! Map) continue;
              final idx = (tc['index'] is int)
                  ? tc['index'] as int
                  : int.tryParse('${tc['index']}') ?? 0;
              final acc = toolAcc.putIfAbsent(idx, _ToolAcc.new);
              final id = tc['id']?.toString();
              if (id != null && id.isNotEmpty) acc.id = id;
              final fn = tc['function'];
              if (fn is Map) {
                final name = fn['name']?.toString();
                if (name != null && name.isNotEmpty) acc.name = name;
                final args = fn['arguments']?.toString();
                if (args != null) acc.args.write(args);
              }
            }
          }
        }
      }

      final message = <String, dynamic>{
        'role': 'assistant',
        'content': contentBuf.isEmpty ? null : contentBuf.toString(),
      };
      if (toolAcc.isNotEmpty) {
        final keys = toolAcc.keys.toList()..sort();
        message['tool_calls'] = [
          for (final i in keys)
            {
              'id': toolAcc[i]!.id.isEmpty ? 'call_$i' : toolAcc[i]!.id,
              'type': 'function',
              'function': {
                'name': toolAcc[i]!.name,
                'arguments': toolAcc[i]!.args.toString(),
              },
            },
        ];
      }
      return (message: message, finishReason: finishReason);
    } on TimeoutException {
      throw StateError('请求超时，请检查网络或模型名是否正确');
    } finally {
      client.close(force: true);
    }
  }
}

class _ToolAcc {
  String id = '';
  String name = '';
  final args = StringBuffer();
}

class ChatTurnResult {
  ChatTurnResult({
    required this.messages,
    required this.assistantText,
    required this.wroteFiles,
  });

  final List<Map<String, dynamic>> messages;
  final String assistantText;
  final bool wroteFiles;
}
