import 'package:flutter/material.dart';

import '../utils/peer_folder_error.dart';

/// 对端文件夹加载失败 / 等待配对时的居中提示
class PeerFolderStatusView extends StatelessWidget {
  final Object? error;
  final VoidCallback? onRetry;
  /// 本机已添加对方，但尚未完成首次连接（待确认）
  final bool pairingPending;

  const PeerFolderStatusView({
    super.key,
    required this.error,
    this.onRetry,
    this.pairingPending = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = classifyPeerFolderError(error);
    final waiting = pairingPending ||
        kind == PeerFolderErrorKind.unpaired ||
        kind == PeerFolderErrorKind.offline;
    final scheme = Theme.of(context).colorScheme;
    final title = pairingPending
        ? peerFolderPendingPairingTitle()
        : peerFolderErrorTitle(kind);
    final message = pairingPending
        ? peerFolderPendingPairingMessage()
        : peerFolderErrorMessage(kind, error);

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
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
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
