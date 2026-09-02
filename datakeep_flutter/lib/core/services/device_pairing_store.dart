import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/utils/device_id.dart';

/// 记录设备是否曾成功连接（用于区分「待确认」与「离线」）
class DevicePairingStore extends ChangeNotifier {
  DevicePairingStore._();
  static final DevicePairingStore instance = DevicePairingStore._();

  static const _connectedKey = 'device_ever_connected';
  static const _migratedKey = 'device_pairing_migrated_v1';

  final Set<String> _everConnected = {};
  bool _ready = false;

  Future<void> ensureLoaded() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    _everConnected
      ..clear()
      ..addAll((prefs.getStringList(_connectedKey) ?? []).map(normDeviceId));
    _ready = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_connectedKey, _everConnected.toList());
  }

  bool hasEverConnected(String deviceId) =>
      _everConnected.contains(normDeviceId(deviceId));

  /// 首次连接或当前已连接时标记
  Future<void> markEverConnected(String deviceId) async {
    await ensureLoaded();
    final key = normDeviceId(deviceId);
    if (key.length != 56) return;
    if (_everConnected.add(key)) {
      await _save();
      notifyListeners();
    }
  }

  /// 升级后：已有配置的设备视为已完成配对，避免全部显示「待确认」
  Future<void> migrateExistingConfiguredDevices(
    Iterable<String> deviceIds,
  ) async {
    await ensureLoaded();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) return;
    var changed = false;
    for (final id in deviceIds) {
      final key = normDeviceId(id);
      if (key.length != 56) continue;
      if (_everConnected.add(key)) changed = true;
    }
    if (changed) await _save();
    await prefs.setBool(_migratedKey, true);
  }

  /// 删除设备后清除配对记录，再次添加时显示「待确认」
  Future<void> clearPairing(String deviceId) async {
    await ensureLoaded();
    final key = normDeviceId(deviceId);
    if (_everConnected.remove(key)) {
      await _save();
      notifyListeners();
    }
  }
}
