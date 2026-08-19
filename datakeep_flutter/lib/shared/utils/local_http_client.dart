import 'dart:io';

/// 配置访问本机后端 / Syncthing / 局域网对端的 [HttpClient]。
/// 本地地址必须直连，不能走系统 HTTP 代理（否则 macOS 沙箱下易报 Operation not permitted）。
void configureLocalHttpClient(
  HttpClient client, {
  bool Function(String host, int port)? trustCertificate,
}) {
  client.findProxy = (uri) {
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1') {
      return 'DIRECT';
    }
    return HttpClient.findProxyFromEnvironment(uri);
  };
  client.badCertificateCallback = (cert, host, port) {
    if (trustCertificate != null) return trustCertificate(host, port);
    final h = host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1';
  };
}
