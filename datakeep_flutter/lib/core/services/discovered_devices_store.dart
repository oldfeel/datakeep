import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'event_service.dart';

String normDeviceId(String id) =>
    id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

/// 局域网发现的、尚未添加到本机的设备（对齐 Sushitrain）
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.deviceId,
    this.name = '',
    this.address = '',
  });

  final String deviceId;
  final String name;
  final String address;

  String get displayName {
    if (name.isNotEmpty && name != deviceId && !name.contains('-')) return name;
    return deviceId;
  }
}

/// 发现列表 + 本机忽略（不写 Syncthing remoteIgnoredDevices）
class DiscoveredDevicesStore extends ChangeNotifier {
  DiscoveredDevicesStore._();
  static final DiscoveredDevicesStore instance = DiscoveredDevicesStore._();

  static const _prefsKey = 'ignore_discovered_devices';

  final Map<String, DiscoveredDevice> _seen = {};
  final Set<String> _ignored = {};
  bool _ready = false;

  Set<String> get ignoredNormIds => Set.unmodifiable(_ignored);

  bool isIgnored(String deviceId) => _ignored.contains(normDeviceId(deviceId));

  List<DiscoveredDevice> available(Iterable<String> configuredIds) {
    final configured = configuredIds.map(normDeviceId).toSet();
    return _seen.values.where((d) {
      final key = normDeviceId(d.deviceId);
      return !configured.contains(key) && !_ignored.contains(key);
    }).toList()
      ..sort((a, b) => a.deviceId.compareTo(b.deviceId));
  }

  Future<void> ensureLoaded() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    _ignored
      ..clear()
      ..addAll((prefs.getStringList(_prefsKey) ?? []).map(normDeviceId));
    _ready = true;
    notifyListeners();
  }

  Future<void> _saveIgnored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _ignored.toList());
  }

  void note({
    required String deviceId,
    String name = '',
    String address = '',
  }) {
    final key = normDeviceId(deviceId);
    if (key.length < 20) return;
    final prev = _seen[key];
    _seen[key] = DiscoveredDevice(
      deviceId: deviceId,
      name: name.isNotEmpty ? name : (prev?.name ?? ''),
      address: address.isNotEmpty ? address : (prev?.address ?? ''),
    );
    notifyListeners();
  }

  void ingestEvent(SyncthingEvent event) {
    switch (event.type) {
      case 'DeviceDiscovered':
        final id = event.data['device']?.toString() ?? '';
        final addrs = event.data['addrs'];
        var addr = '';
        if (addrs is List && addrs.isNotEmpty) {
          addr = addrs.first.toString();
        }
        note(deviceId: id, address: addr);
        break;
      case 'PendingDevicesChanged':
        final added = event.data['added'];
        if (added is List) {
          for (final item in added) {
            if (item is! Map) continue;
            note(
              deviceId: item['deviceID']?.toString() ?? '',
              name: item['name']?.toString() ?? '',
              address: item['address']?.toString() ?? '',
            );
          }
        }
        break;
    }
  }

  Future<void> refresh() async {
    await ensureLoaded();
    try {
      final devices = await ApiService.fetchDiscoveredDevicesOnce();
      for (final d in devices) {
        final id = d['id'] ?? '';
        if (id.isEmpty) continue;
        note(deviceId: id, name: d['name'] ?? '');
      }
    } catch (e) {
      debugPrint('[discovery] 刷新失败: $e');
    }
    try {
      final pending = await ApiService.getPendingDevices();
      if (pending == null) return;
      for (final entry in pending.entries) {
        final info = entry.value;
        note(
          deviceId: entry.key,
          name: info is Map ? info['name']?.toString() ?? '' : '',
          address: info is Map ? info['address']?.toString() ?? '' : '',
        );
      }
    } catch (_) {}
  }

  /// 从发现列表藏起来（本机偏好，不写 Syncthing 忽略）
  Future<void> ignore(String deviceId) async {
    await ensureLoaded();
    _ignored.add(normDeviceId(deviceId));
    await _saveIgnored();
    notifyListeners();
  }

  Future<void> unignore(String deviceId) async {
    await ensureLoaded();
    _ignored.remove(normDeviceId(deviceId));
    await _saveIgnored();
    notifyListeners();
  }
}
