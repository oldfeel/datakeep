import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/market_service.dart';
import '../../../features/folders/providers/folder_provider.dart';
import 'app_runner_page.dart';
import '../delete_app.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  List<MarketAppInfo> _apps = [];
  bool _loading = true;
  String? _error;
  String _base = MarketService.defaultBase;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _base = await MarketService.getBaseUrl();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await MarketService.listApps();
      if (!mounted) return;
      setState(() {
        _apps = list;
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

  Future<void> _editBase() async {
    final ctrl = TextEditingController(text: _base);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('市场 API 地址'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            hintText: 'http://192.168.2.10:8088',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      await MarketService.setBaseUrl(ctrl.text);
      _base = await MarketService.getBaseUrl();
      await _load();
    }
  }

  bool _installed(String appKey) {
    final id = 'app-$appKey';
    return context.read<FolderProvider>().folders.any((f) => f.id == id);
  }

  Future<void> _install(MarketAppInfo app) async {
    setState(() => _busy.add(app.appKey));
    String? progress;
    try {
      await MarketService.install(app, onProgress: (m) {
        progress = m;
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      await context.read<FolderProvider>().fetchFolders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已安装 ${app.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('安装失败: $e${progress != null ? " ($progress)" : ""}')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(app.appKey));
    }
  }

  Future<void> _open(MarketAppInfo app) async {
    final path = await MarketService.installPathFor(app.appKey);
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AppRunnerPage(
          appPath: path,
          title: app.name,
          folderId: app.folderId,
        ),
      ),
    );
    if (!mounted) return;
    await context.read<FolderProvider>().fetchFolders(silent: true);
  }

  Future<void> _uninstall(MarketAppInfo app) async {
    final ok = await confirmDeleteApp(
      context,
      app.name,
      title: '卸载应用',
      actionLabel: '卸载',
    );
    if (ok != true) return;
    setState(() => _busy.add(app.appKey));
    try {
      await MarketService.uninstall(app.appKey);
      if (!mounted) return;
      await context.read<FolderProvider>().fetchFolders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已卸载')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('卸载失败: $e')));
    } finally {
      if (mounted) setState(() => _busy.remove(app.appKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用市场'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: _editBase, tooltip: 'API 地址'),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text('当前 API: $_base', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _editBase, child: const Text('修改地址')),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : _apps.isEmpty
                  ? const Center(child: Text('暂无上架应用'))
                  : ListView.builder(
                      itemCount: _apps.length,
                      itemBuilder: (ctx, i) {
                        final app = _apps[i];
                        final installed = _installed(app.appKey);
                        final busy = _busy.contains(app.appKey);
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.apps)),
                          title: Text(app.name),
                          subtitle: Text(
                            [
                              if (app.version != null) 'v${app.version}',
                              if (app.description.isNotEmpty) app.description,
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: busy
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Wrap(
                                  spacing: 4,
                                  children: [
                                    if (installed) ...[
                                      TextButton(onPressed: () => _open(app), child: const Text('打开')),
                                      TextButton(onPressed: () => _install(app), child: const Text('更新')),
                                      TextButton(
                                        onPressed: () => _uninstall(app),
                                        child: const Text('卸载'),
                                      ),
                                    ] else
                                      FilledButton(
                                        onPressed: () => _install(app),
                                        child: const Text('安装'),
                                      ),
                                  ],
                                ),
                        );
                      },
                    ),
    );
  }
}
