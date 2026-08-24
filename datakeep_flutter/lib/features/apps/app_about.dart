import 'package:flutter/material.dart';

import '../../shared/utils/app_manifest.dart';

/// 显示应用「关于」信息（来自 app.json）。
Future<void> showAppAboutDialog(
  BuildContext context, {
  required AppManifest manifest,
  String? installPath,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('关于 ${manifest.displayName()}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manifest.description.isNotEmpty) ...[
              Text(manifest.description),
              const SizedBox(height: 12),
            ],
            _AboutRow(label: '名称', value: manifest.displayName()),
            if (manifest.id.isNotEmpty) _AboutRow(label: '标识', value: manifest.id),
            if (manifest.version.isNotEmpty) _AboutRow(label: '版本', value: manifest.version),
            if (installPath != null && installPath.isNotEmpty)
              _AboutRow(label: '路径', value: installPath),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
      ],
    ),
  );
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
