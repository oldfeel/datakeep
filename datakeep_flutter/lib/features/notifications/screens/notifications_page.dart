import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/app_notification.dart';
import '../../../core/services/app_notification_store.dart';
import '../../../core/services/notification_repository.dart';

/// 消息历史：分类 / 下拉刷新 / 上拉加载更多
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  static final _tabs = <(String, AppNotificationCategory?)>[
    ('全部', null),
    ('设备', AppNotificationCategory.device),
    ('同步', AppNotificationCategory.sync),
    ('系统', AppNotificationCategory.system),
  ];

  late final TabController _tabController;
  final _repo = NotificationRepository.instance;
  final _scroll = ScrollController();

  final List<AppNotification> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  AppNotificationCategory? get _category => _tabs[_tabController.index].$2;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _reload();
    });
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
      context.read<AppNotificationStore>().markAllRead();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });
    try {
      final page = await _repo.page(
        category: _category,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _hasMore = page.length >= NotificationRepository.pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.page(
        category: _category,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= NotificationRepository.pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空消息'),
        content: const Text('确定删除全部本地消息？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppNotificationStore>().clearAll();
    await _reload();
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (sameDay) return hm;
    return '${t.month}/${t.day} $hm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('消息'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty ? null : _clearAll,
            child: const Text('清空'),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [for (final t in _tabs) Tab(text: t.$1)],
        ),
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: _items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('暂无消息')),
                          ],
                        )
                      : ListView.builder(
                          controller: _scroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              if (_loadingMore) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: Text(
                                    _hasMore ? '' : '没有更多了',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              );
                            }
                            final n = _items[i];
                            return ListTile(
                              leading: Icon(_iconFor(n.category)),
                              title: Text(n.title),
                              subtitle: Text(
                                '${n.category.label} · ${_formatTime(n.createdAt)}',
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  IconData _iconFor(AppNotificationCategory c) {
    switch (c) {
      case AppNotificationCategory.device:
        return Icons.devices;
      case AppNotificationCategory.sync:
        return Icons.sync;
      case AppNotificationCategory.system:
        return Icons.info_outline;
    }
  }
}
