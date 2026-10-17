import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/ai_chat_history_store.dart';
import '../../core/services/ai_settings_store.dart';
import 'ai_settings_dialog.dart';
import 'app_ai_service.dart';

/// 应用内 AI 全屏对话（嵌入 AppRunner body，与 WebView 切换显示）
class AppAiPanel extends StatefulWidget {
  const AppAiPanel({
    super.key,
    required this.codeRoot,
    required this.appName,
    required this.appId,
    this.onWroteChanged,
  });

  final String codeRoot;
  final String appName;
  /// 用于本机持久化对话（app.json id）
  final String appId;
  final ValueChanged<bool>? onWroteChanged;

  @override
  State<AppAiPanel> createState() => _AppAiPanelState();
}

class _AppAiPanelState extends State<AppAiPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _bubbles = <_Bubble>[];
  late final AppAiService _service;
  List<Map<String, dynamic>> _messages = [];
  bool _busy = false;
  bool _loadingHistory = false;
  bool _loadingOlder = false;
  bool _hasMoreHistory = false;
  String _status = '';
  /// 历史加载完整错误（供复制；副标题可能截断）
  String? _historyErrorDetail;
  bool _wrote = false;
  bool _uiDirty = false;
  bool _needScroll = false;
  Timer? _uiThrottle;
  Timer? _saveDebounce;

  String get _historyId =>
      widget.appId.trim().isEmpty ? widget.appName : widget.appId.trim();

  @override
  void initState() {
    super.initState();
    _service = AppAiService(codeRoot: widget.codeRoot);
    _messages = [
      {
        'role': 'system',
        'content': AppAiService.systemPrompt(widget.appName),
      },
    ];
    // 先展示可对话界面，历史在后台拉取（读库失败也不挡输入）
    _bubbles.add(
      _Bubble(
        kind: _BubbleKind.assistant,
        text: '可以改标题、样式或简单交互。例如：「把标题改成我的生物馆」。',
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadHistory());
    });
  }

  @override
  void dispose() {
    _uiThrottle?.cancel();
    _saveDebounce?.cancel();
    // dispose 时不阻塞写库：延迟到微任务，避免关面板卡顿
    final id = _historyId;
    final pending = [
      for (final b in _bubbles)
        if (!b.streaming && b.dbSeq == null) b.toJson(),
    ];
    final msgs = List<Map<String, dynamic>>.from(_messages);
    scheduleMicrotask(() {
      unawaited(
        AiChatHistoryStore.appendBubblesAndSaveMessages(
          appId: id,
          newBubbles: pending,
          messages: msgs,
        ),
      );
    });
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _loadingHistory = true;
      _historyErrorDetail = null;
      _status = '加载历史…';
    });
    try {
      final page = await AiChatHistoryStore.loadRecent(_historyId).timeout(
        const Duration(seconds: 8),
      );
      if (!mounted) return;
      if (page.bubbles.isNotEmpty) {
        final restored = <_Bubble>[];
        for (final row in page.bubbles) {
          final b = _Bubble.fromJson(row.payload, dbSeq: row.seq);
          if (b != null) restored.add(b);
        }
        if (restored.isNotEmpty) {
          _bubbles
            ..clear()
            ..addAll(restored);
        }
        if (page.messages.isNotEmpty) {
          _messages = List<Map<String, dynamic>>.from(page.messages);
          _ensureSystemPrompt();
        }
        setState(() {
          _loadingHistory = false;
          _historyErrorDetail = null;
          _hasMoreHistory = page.hasMore;
          _status = page.hasMore ? '已加载最近对话（顶部可加载更早）' : '已恢复历史对话';
        });
        _scrollToEnd();
        return;
      }
      // 库正常打开但没有记录 ≠ 失败
      setState(() {
        _loadingHistory = false;
        _historyErrorDetail = null;
        _hasMoreHistory = false;
        _status = '暂无历史记录';
      });
    } on TimeoutException catch (e, st) {
      final detail =
          'TimeoutException appId=$_historyId\n$e\n$st';
      debugPrint('[AiChat] 加载历史超时: $detail');
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _hasMoreHistory = false;
        _historyErrorDetail = detail;
        _status = '历史读取超时（点旁侧复制）';
      });
    } catch (e, st) {
      final detail = [
        'appId=$_historyId',
        if (AiChatHistoryStore.lastError != null)
          'lastError=${AiChatHistoryStore.lastError}',
        'error=$e',
        'stack=\n$st',
      ].join('\n');
      debugPrint('[AiChat] 加载历史异常:\n$detail');
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _hasMoreHistory = false;
        _historyErrorDetail = detail;
        _status = '历史加载失败（点旁侧复制原因）';
      });
    }
  }

  Future<void> _copyHistoryError() async {
    final text = _historyErrorDetail;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制错误原因')),
    );
  }

  Future<void> _loadOlderHistory() async {
    if (_loadingOlder || !_hasMoreHistory) return;
    int? beforeSeq;
    for (final b in _bubbles) {
      if (b.dbSeq != null) {
        beforeSeq = b.dbSeq;
        break;
      }
    }
    if (beforeSeq == null) {
      setState(() => _hasMoreHistory = false);
      return;
    }

    setState(() => _loadingOlder = true);
    final prevMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final prevPixels =
        _scroll.hasClients ? _scroll.position.pixels : 0.0;

    try {
      final page = await AiChatHistoryStore.loadOlder(
        _historyId,
        beforeSeq: beforeSeq,
      );
      if (!mounted) return;
      if (page.bubbles.isEmpty) {
        setState(() {
          _loadingOlder = false;
          _hasMoreHistory = false;
        });
        return;
      }
      final older = <_Bubble>[];
      for (final row in page.bubbles) {
        final b = _Bubble.fromJson(row.payload, dbSeq: row.seq);
        if (b != null) older.add(b);
      }
      setState(() {
        _bubbles.insertAll(0, older);
        _hasMoreHistory = page.hasMore;
        _loadingOlder = false;
        _status = _hasMoreHistory ? '已加载更早记录' : '已到最早记录';
      });
      // 保持视口相对位置，避免跳动到顶
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final newMax = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(prevPixels + (newMax - prevMax));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _status = '加载更早记录失败';
      });
    }
  }

  void _ensureSystemPrompt() {
    final sys = {
      'role': 'system',
      'content': AppAiService.systemPrompt(widget.appName),
    };
    if (_messages.isEmpty || _messages.first['role']?.toString() != 'system') {
      _messages.insert(0, sys);
    } else {
      _messages[0] = sys;
    }
  }

  Future<void> _persist({bool immediate = false}) async {
    Future<void> doSave() async {
      final pending = [
        for (final b in _bubbles)
          if (!b.streaming && b.dbSeq == null) b,
      ];
      if (pending.isEmpty && _messages.isEmpty) return;
      try {
        if (pending.isNotEmpty) {
          final seqs = await AiChatHistoryStore.appendBubblesAndSaveMessages(
            appId: _historyId,
            newBubbles: [for (final b in pending) b.toJson()],
            messages: _messages,
          );
          for (var i = 0; i < pending.length && i < seqs.length; i++) {
            pending[i].dbSeq = seqs[i];
          }
        } else {
          // 仅刷新 messages（例如失败后）
          await AiChatHistoryStore.appendBubblesAndSaveMessages(
            appId: _historyId,
            newBubbles: const [],
            messages: _messages,
          );
        }
      } catch (e) {
        debugPrint('[AiChat] 保存失败: $e');
      }
    }

    if (immediate) {
      _saveDebounce?.cancel();
      await doSave();
      return;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(doSave());
    });
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('清除本应用的 AI 对话记录？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await AiChatHistoryStore.clear(_historyId);
    if (!mounted) return;
    setState(() {
      _bubbles
        ..clear()
        ..add(
          _Bubble(
            kind: _BubbleKind.assistant,
            text: '可以改标题、样式或简单交互。例如：「把标题改成我的生物馆」。',
          ),
        );
      _messages = [
        {
          'role': 'system',
          'content': AppAiService.systemPrompt(widget.appName),
        },
      ];
      _hasMoreHistory = false;
      _status = '已清空对话';
    });
  }

  /// 流式输出节流；思考增量默认不强制滚到底，减少闪动
  void _scheduleUi({bool force = false, bool scroll = false}) {
    if (!mounted) return;
    if (scroll) _needScroll = true;
    if (force) {
      _uiThrottle?.cancel();
      _uiThrottle = null;
      _uiDirty = false;
      final doScroll = _needScroll;
      _needScroll = false;
      setState(() {});
      if (doScroll) _scrollToEnd();
      return;
    }
    _uiDirty = true;
    if (_uiThrottle?.isActive ?? false) return;
    _uiThrottle = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || !_uiDirty) return;
      _uiDirty = false;
      final doScroll = _needScroll;
      _needScroll = false;
      setState(() {});
      if (doScroll) _scrollToEnd();
    });
  }

  void _markWrote() {
    if (_wrote) return;
    _wrote = true;
    widget.onWroteChanged?.call(true);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    final keyOk = await AiSettingsStore.hasAnyKey();
    if (!keyOk) {
      if (!mounted) return;
      await showAiSettingsDialog(context);
      return;
    }

    final activity = _Bubble(
      kind: _BubbleKind.activity,
      text: '思考中',
      phase: '连接中…',
      tools: [],
      expanded: true,
      streaming: true,
    );
    final reply = _Bubble(
      kind: _BubbleKind.assistant,
      text: '',
      streaming: true,
    );

    setState(() {
      _busy = true;
      _status = '发送中…';
      _input.clear();
      _bubbles.add(_Bubble(kind: _BubbleKind.user, text: text));
      _bubbles.add(activity);
      _bubbles.add(reply);
    });
    _scrollToEnd();
    _messages.add({'role': 'user', 'content': text});

    try {
      final result = await _service.chat(
        messages: _messages,
        onEvent: (ev) {
          if (!mounted) return;
          switch (ev.kind) {
            case AiChatEventKind.status:
              // 状态只更新一行 phase，不往列表里堆
              _status = ev.text;
              activity.phase = ev.text;
              _scheduleUi();
            case AiChatEventKind.thinking:
              _status = '思考中…';
              activity.phase = '推理中…';
              activity.thinking.write(ev.text);
              if (activity.thinking.length > 12000) {
                final s = activity.thinking.toString();
                activity.thinking
                  ..clear()
                  ..write('…\n')
                  ..write(s.substring(s.length - 8000));
              }
              _scheduleUi();
            case AiChatEventKind.contentDelta:
              _status = '生成回复…';
              activity.phase = '生成回复…';
              reply.text += ev.text;
              _scheduleUi(scroll: true);
            case AiChatEventKind.toolStart:
              _status = '工具：${ev.text}';
              activity.phase = '调用工具…';
              activity.tools.add(_ToolItem(label: ev.text));
              _scheduleUi(scroll: true);
            case AiChatEventKind.toolResult:
              _status = '工具完成';
              if (activity.tools.isNotEmpty) {
                final last = activity.tools.last;
                if (!last.done && last.label == ev.text) {
                  last.done = true;
                  last.detail = _shortDetail(ev.detail);
                } else {
                  activity.tools.add(
                    _ToolItem(
                      label: ev.text,
                      done: true,
                      detail: _shortDetail(ev.detail),
                    ),
                  );
                }
              }
              _scheduleUi(scroll: true);
          }
        },
      );
      _messages = result.messages;
      if (result.wroteFiles) _markWrote();
      if (!mounted) return;
      if (reply.text.trim().isEmpty) {
        reply.text = result.assistantText;
      }
      activity.streaming = false;
      activity.phase = result.wroteFiles ? '已写文件' : '完成';
      activity.text = activity.phase;
      // 结束后默认收起，避免大段推理占屏（可手动展开）
      activity.expanded = false;
      reply.streaming = false;
      _status = result.wroteFiles ? '已写文件，返回应用后将重载' : '';
      _busy = false;
      _scheduleUi(force: true, scroll: true);
      unawaited(_persist());
    } catch (e) {
      if (!mounted) return;
      activity.streaming = false;
      activity.phase = '失败';
      activity.text = '失败';
      activity.error = '$e';
      reply.streaming = false;
      if (reply.text.trim().isEmpty) {
        reply.text = '出错：$e';
      }
      _status = '';
      _busy = false;
      _scheduleUi(force: true, scroll: true);
      unawaited(_persist());
    } finally {
      if (mounted && _busy) {
        _busy = false;
        _scheduleUi(force: true);
      }
    }
  }

  static String? _shortDetail(String? detail) {
    if (detail == null || detail.isEmpty) return null;
    final oneLine = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 96) return oneLine;
    return '${oneLine.substring(0, 96)}…';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if ((max - _scroll.offset).abs() < 8) return;
      _scroll.jumpTo(max);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          children: [
            Material(
              elevation: 0.5,
              child: ListTile(
                dense: true,
                title: Text('AI 编辑 · ${widget.appName}'),
                subtitle: SelectableText(
                  _loadingHistory
                      ? '加载历史…'
                      : _status.isEmpty
                          ? (_busy ? '处理中…' : '对话已保存在本机 SQLite')
                          : _status,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_historyErrorDetail != null)
                      IconButton(
                        tooltip: '复制错误原因',
                        icon: const Icon(Icons.copy_all_outlined),
                        onPressed: () => unawaited(_copyHistoryError()),
                      ),
                    IconButton(
                      tooltip: '清空对话',
                      icon: const Icon(Icons.delete_outline),
                      onPressed:
                          _busy ? null : () => unawaited(_clearHistory()),
                    ),
                    IconButton(
                      tooltip: 'AI 设置',
                      icon: const Icon(Icons.key_outlined),
                      onPressed: () => showAiSettingsDialog(context),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _bubbles.length +
                    ((_hasMoreHistory || _loadingOlder) ? 1 : 0),
                itemBuilder: (context, i) {
                  final header =
                      (_hasMoreHistory || _loadingOlder) ? 1 : 0;
                  if (header == 1 && i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Center(
                        child: _loadingOlder
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : TextButton(
                                onPressed: () =>
                                    unawaited(_loadOlderHistory()),
                                child: const Text('加载更早的对话'),
                              ),
                      ),
                    );
                  }
                  final b = _bubbles[i - header];
                  return KeyedSubtree(
                    key: ObjectKey(b),
                    child: _buildBubble(context, b),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent) {
                            return KeyEventResult.ignored;
                          }
                          final isEnter =
                              event.logicalKey == LogicalKeyboardKey.enter ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.numpadEnter;
                          if (!isEnter) return KeyEventResult.ignored;
                          if (HardwareKeyboard.instance.isShiftPressed) {
                            return KeyEventResult.ignored;
                          }
                          if (!_busy) unawaited(_send());
                          return KeyEventResult.handled;
                        },
                        child: TextField(
                          controller: _input,
                          enabled: !_busy,
                          minLines: 3,
                          maxLines: 8,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: const InputDecoration(
                            hintText: 'Enter 发送 · Shift+Enter 换行',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final onPrimary =
                            Theme.of(context).colorScheme.onPrimary;
                        return FilledButton(
                          onPressed: () {
                            if (!_busy) unawaited(_send());
                          },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            fixedSize: const Size(48, 48),
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          child: _busy
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: onPrimary,
                                  ),
                                )
                              : Icon(
                                  Icons.send_rounded,
                                  size: 22,
                                  color: onPrimary,
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, _Bubble b) {
    final scheme = Theme.of(context).colorScheme;
    final maxW = MediaQuery.sizeOf(context).width * 0.92;

    if (b.kind == _BubbleKind.activity) {
      return _ThoughtCard(bubble: b, maxWidth: maxW);
    }

    final mine = b.kind == _BubbleKind.user;
    if (b.kind == _BubbleKind.assistant &&
        b.text.trim().isEmpty &&
        b.streaming) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: maxW * 0.92),
        decoration: BoxDecoration(
          color: mine
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SelectableText(
          b.text.isEmpty && b.streaming ? '…' : b.text,
        ),
      ),
    );
  }
}

/// Cursor / OpenCode 风格：可折叠「思考」块，内部聚合推理 + 工具，避免逐步刷列表闪烁
class _ThoughtCard extends StatefulWidget {
  const _ThoughtCard({required this.bubble, required this.maxWidth});

  final _Bubble bubble;
  final double maxWidth;

  @override
  State<_ThoughtCard> createState() => _ThoughtCardState();
}

class _ThoughtCardState extends State<_ThoughtCard> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.bubble.expanded;
  }

  @override
  void didUpdateWidget(covariant _ThoughtCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅在流式结束时跟随 bubble.expanded（默认收起），避免流式中被外部反复改
    if (oldWidget.bubble.streaming && !widget.bubble.streaming) {
      _open = widget.bubble.expanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bubble;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.62);
    final hasBody = b.thinking.isNotEmpty ||
        b.tools.isNotEmpty ||
        (b.error != null && b.error!.isNotEmpty);

    final title = b.streaming
        ? (b.phase.isEmpty ? '思考中' : '思考中 · ${b.phase}')
        : (b.phase.isEmpty ? '思考过程' : '思考过程 · ${b.phase}');

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.55),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: hasBody
                    ? () => setState(() {
                          _open = !_open;
                          b.expanded = _open;
                        })
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      if (b.streaming)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary.withValues(alpha: 0.85),
                          ),
                        )
                      else
                        Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: muted,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ),
                      if (hasBody)
                        Icon(
                          _open
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 20,
                          color: muted,
                        ),
                    ],
                  ),
                ),
              ),
              if (_open && hasBody) ...[
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (b.thinking.isNotEmpty)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: SingleChildScrollView(
                            // 固定滚动位置，避免流式追加时视口跳动
                            primary: false,
                            child: SelectableText(
                              b.thinking.toString(),
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: muted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      if (b.thinking.isNotEmpty && b.tools.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Divider(
                            height: 1,
                            color: scheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                      for (final t in b.tools)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                t.done
                                    ? Icons.check_circle_outline
                                    : Icons.pending_outlined,
                                size: 15,
                                color: t.done
                                    ? scheme.primary.withValues(alpha: 0.8)
                                    : muted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        height: 1.3,
                                        fontFamily: 'monospace',
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.82),
                                      ),
                                    ),
                                    if (t.detail != null)
                                      Text(
                                        t.detail!,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.3,
                                          color: muted,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (b.error != null && b.error!.isNotEmpty)
                        Text(
                          b.error!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _BubbleKind { user, assistant, activity }

class _ToolItem {
  _ToolItem({
    required this.label,
    this.done = false,
    this.detail,
  });

  final String label;
  bool done;
  String? detail;

  Map<String, dynamic> toJson() => {
        'label': label,
        'done': done,
        if (detail != null) 'detail': detail,
      };

  factory _ToolItem.fromJson(Map<String, dynamic> json) => _ToolItem(
        label: json['label']?.toString() ?? '',
        done: json['done'] == true,
        detail: json['detail']?.toString(),
      );
}

class _Bubble {
  _Bubble({
    required this.kind,
    required this.text,
    this.phase = '',
    List<_ToolItem>? tools,
    this.expanded = false,
    this.streaming = false,
    this.error,
    this.dbSeq,
    String? thinkingText,
  }) : tools = tools ?? <_ToolItem>[] {
    if (thinkingText != null && thinkingText.isNotEmpty) {
      thinking.write(thinkingText);
    }
  }

  final _BubbleKind kind;
  String text;
  String phase;
  final StringBuffer thinking = StringBuffer();
  final List<_ToolItem> tools;
  bool expanded;
  bool streaming;
  String? error;
  /// SQLite bubbles.seq；null 表示尚未入库
  int? dbSeq;

  Map<String, dynamic> toJson() {
    var think = thinking.toString();
    if (think.length > 4000) {
      think = '…\n${think.substring(think.length - 3500)}';
    }
    return {
      'kind': kind.name,
      'text': text,
      'phase': phase,
      if (think.isNotEmpty) 'thinking': think,
      'tools': [for (final t in tools) t.toJson()],
      'expanded': false,
      if (error != null) 'error': error,
    };
  }

  static _Bubble? fromJson(
    Map<String, dynamic> json, {
    int? dbSeq,
  }) {
    final kindName = json['kind']?.toString() ?? '';
    final kind = _BubbleKind.values.where((k) => k.name == kindName).firstOrNull;
    if (kind == null) return null;
    final tools = <_ToolItem>[];
    final rawTools = json['tools'];
    if (rawTools is List) {
      for (final e in rawTools) {
        if (e is Map) {
          tools.add(_ToolItem.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return _Bubble(
      kind: kind,
      text: json['text']?.toString() ?? '',
      phase: json['phase']?.toString() ?? '',
      tools: tools,
      expanded: false,
      streaming: false,
      error: json['error']?.toString(),
      thinkingText: json['thinking']?.toString(),
      dbSeq: dbSeq,
    );
  }
}
