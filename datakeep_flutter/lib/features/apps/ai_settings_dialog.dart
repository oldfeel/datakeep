import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/ai_settings_store.dart';

/// DeepSeek / 豆包 API Key 设置
Future<void> showAiSettingsDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => const _AiSettingsDialog(),
  );
}

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog();

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  AiProvider _provider = AiProvider.deepseek;
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final provider = await AiSettingsStore.getProvider();
    final key = await AiSettingsStore.getApiKey(provider);
    final model = await AiSettingsStore.getModel(provider);
    final base = await AiSettingsStore.getDoubaoBaseUrl();
    if (!mounted) return;
    setState(() {
      _provider = provider;
      _keyCtrl.text = key;
      _modelCtrl.text = model;
      _baseCtrl.text = base;
      _loading = false;
    });
  }

  Future<void> _onProviderChanged(AiProvider? v) async {
    if (v == null) return;
    final key = await AiSettingsStore.getApiKey(v);
    final model = await AiSettingsStore.getModel(v);
    if (!mounted) return;
    setState(() {
      _provider = v;
      _keyCtrl.text = key;
      _modelCtrl.text = model;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AiSettingsStore.setProvider(_provider);
      await AiSettingsStore.setApiKey(_provider, _keyCtrl.text);
      await AiSettingsStore.setModel(_provider, _modelCtrl.text);
      if (_provider == AiProvider.doubao) {
        await AiSettingsStore.setDoubaoBaseUrl(_baseCtrl.text);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 设置已保存')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _baseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 设置'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Key 仅保存在本机，用于应用内 AI 改无构建应用的源码。',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '服务商',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<AiProvider>(
                          isExpanded: true,
                          value: _provider,
                          items: [
                            for (final p in AiProvider.values)
                              DropdownMenuItem(
                                value: p,
                                child: Text(p.label),
                              ),
                          ],
                          onChanged: _onProviderChanged,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'API Key',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? '显示' : '隐藏',
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modelCtrl,
                      decoration: const InputDecoration(
                        labelText: '模型',
                        border: OutlineInputBorder(),
                        hintText: 'deepseek-flash / 豆包接入点 ID',
                      ),
                    ),
                    if (_provider == AiProvider.doubao) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _baseCtrl,
                        decoration: const InputDecoration(
                          labelText: '豆包 API Base',
                          border: OutlineInputBorder(),
                          hintText:
                              'https://ark.cn-beijing.volces.com/api/v3',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
