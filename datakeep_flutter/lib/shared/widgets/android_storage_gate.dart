import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/services/android_storage_service.dart';
import '../../core/services/syncthing_lifecycle.dart';

/// Android 启动时引导授予 All files access（与 Syncthing Android onboarding 一致）
class AndroidStorageGate extends StatefulWidget {
  final Widget child;

  const AndroidStorageGate({super.key, required this.child});

  @override
  State<AndroidStorageGate> createState() => _AndroidStorageGateState();
}

class _AndroidStorageGateState extends State<AndroidStorageGate> with WidgetsBindingObserver {
  bool _checking = true;
  bool _granted = false;
  bool _restartingSyncthing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) {
      setState(() {
        _checking = false;
        _granted = true;
      });
      return;
    }
    final wasGranted = _granted;
    final ok = await AndroidStorageService.hasAllFilesAccess();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _granted = ok;
    });
    if (ok && !wasGranted) {
      setState(() => _restartingSyncthing = true);
      await SyncthingLifecycle.instance.requestRestart();
      if (mounted) setState(() => _restartingSyncthing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return widget.child;
    if (_checking || _restartingSyncthing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_restartingSyncthing) ...[
                const SizedBox(height: 16),
                Text(
                  '同步引擎重启中…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (_granted) return widget.child;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.folder_shared, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                '需要存储访问权限',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Syncthing 需要「允许访问所有文件」权限，才能将文件同步到 DCIM、下载等目录。\n\n'
                '这与官方 Syncthing Android 应用使用相同的权限模型。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await AndroidStorageService.requestAllFilesAccess();
                },
                child: const Text('打开权限设置'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _refresh,
                child: const Text('我已授予，继续'),
              ),
              const SizedBox(height: 8),
              Text(
                '未授予权限时，同步到 /storage/emulated/0/ 等公共目录将失败。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
