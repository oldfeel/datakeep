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

String peerFolderPendingPairingTitle() => '等待对方添加本机';

String peerFolderPendingPairingMessage() =>
    '本机已添加该设备，但对方尚未添加本机。请在对方设备上接受配对，或手动添加本机设备 ID；双方都添加后即可同步。';

String peerFolderErrorTitle(PeerFolderErrorKind kind) {
  switch (kind) {
    case PeerFolderErrorKind.unpaired:
      return '等待对方同意';
    case PeerFolderErrorKind.offline:
      return '未连接';
    case PeerFolderErrorKind.unreachable:
      return '未连接';
    case PeerFolderErrorKind.other:
      return '无法显示文件夹';
  }
}

String peerFolderErrorMessage(PeerFolderErrorKind kind, Object? raw) {
  switch (kind) {
    case PeerFolderErrorKind.unpaired:
      return '已向对方发出配对请求。请在对方设备上同意后，即可查看与其共享的文件夹。';
    case PeerFolderErrorKind.offline:
      return '当前未与该设备建立连接。请确认对方已打开应用且网络可达，连接后将显示其共享的文件夹。';
    case PeerFolderErrorKind.unreachable:
      // 对齐 sushitrain「Not connected」：已配对但尚未连上，不当成故障
      return '已添加该设备，但尚未连上。连接建立后即可查看对方共享的文件夹。';
    case PeerFolderErrorKind.other:
      return raw?.toString() ?? '未知错误';
  }
}

bool peerFolderErrorShouldAutoRetry(PeerFolderErrorKind kind) {
  return kind == PeerFolderErrorKind.unpaired ||
      kind == PeerFolderErrorKind.offline ||
      kind == PeerFolderErrorKind.unreachable;
}
