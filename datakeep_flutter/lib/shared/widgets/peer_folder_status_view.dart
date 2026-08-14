import 'package:flutter/material.dart';

import '../utils/peer_folder_error.dart';

/// 对端文件夹加载失败 / 等待配对时的居中提示
class PeerFolderStatusView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;

  const PeerFolderStatusView({
    super.key,
    required this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final kind = classifyPeerFolderError(error);
    final waiting = kind == PeerFolderErrorKind.unpaired ||
        kind == PeerFolderErrorKind.offline;
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              waiting ? Icons.hourglass_top : Icons.error_outline,
              size: 64,
              color: waiting ? scheme.primary : scheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              peerFolderErrorTitle(kind),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              peerFolderErrorMessage(kind, error),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('刷新'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
