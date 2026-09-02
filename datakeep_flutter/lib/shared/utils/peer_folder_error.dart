/// 对端文件夹加载失败的分类（用于 UI，不把「未配对」当成硬错误）
enum PeerFolderErrorKind {
  /// 本机已添加对方，对方尚未同意配对
  unpaired,
  /// Syncthing 尚未连上
  offline,
  /// 对端数据管理服务不可达等
  unreachable,
  other,
}

PeerFolderErrorKind classifyPeerFolderError(Object? error) {
  final e = error?.toString() ?? '';
  if (e.contains('未配对')) return PeerFolderErrorKind.unpaired;
  if (e.contains('离线')) return PeerFolderErrorKind.offline;
  if (e.contains('对端') ||
      e.contains('不可达') ||
      e.contains('中继') ||
      e.contains('局域网地址')) {
    return PeerFolderErrorKind.unreachable;
  }
  return PeerFolderErrorKind.other;
}

String peerFolderPendingPairingTitle() => '配对未完成';

String peerFolderPendingPairingMessage() =>
    '本机已添加该设备，但对方尚未添加本机。请在对方设备上接受配对请求，或通过「添加设备」手动添加本机；双方均添加后，文件夹列表会自动显示。';

String peerFolderErrorTitle(PeerFolderErrorKind kind) {
  switch (kind) {
    case PeerFolderErrorKind.unpaired:
      return '等待对方同意';
    case PeerFolderErrorKind.offline:
      return '设备离线';
    case PeerFolderErrorKind.unreachable:
      return '暂时无法访问';
    case PeerFolderErrorKind.other:
      return '加载文件夹失败';
  }
}

String peerFolderErrorMessage(PeerFolderErrorKind kind, Object? raw) {
  switch (kind) {
    case PeerFolderErrorKind.unpaired:
      return '已向对方发出配对请求，请在对方设备上同意后再查看文件夹。同意后将自动刷新。';
    case PeerFolderErrorKind.offline:
      return '暂时无法连接对方，请确认设备在线且在同一网络，稍后会自动重试。';
    case PeerFolderErrorKind.unreachable:
      return '已配对但暂时拉不到对方文件夹（对端服务可能还在启动），请稍候。';
    case PeerFolderErrorKind.other:
      return raw?.toString() ?? '未知错误';
  }
}

bool peerFolderErrorShouldAutoRetry(PeerFolderErrorKind kind) {
  return kind == PeerFolderErrorKind.unpaired ||
      kind == PeerFolderErrorKind.offline ||
      kind == PeerFolderErrorKind.unreachable;
}
