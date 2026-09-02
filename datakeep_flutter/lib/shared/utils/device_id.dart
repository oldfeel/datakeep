String normDeviceId(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

/// Syncthing 标准设备 ID（8 组连字符）
String formatDeviceId(String id) {
  final clean = normDeviceId(id);
  if (clean.length != 56) return id.trim();
  return List.generate(8, (i) => clean.substring(i * 7, i * 7 + 7)).join('-');
}
