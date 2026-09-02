import 'package:flutter/foundation.dart';
import '../../../core/models/device.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/discovered_devices_store.dart';
import '../../../core/services/device_pairing_store.dart';

class DeviceProvider with ChangeNotifier {
  List<Device> _devices = [];
  bool _isLoading = false;
  String? _error;

  List<Device> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // 获取本地设备
  Device? get localDevice => _devices.firstWhere(
    (device) => device.isLocal,
    orElse: () => Device(
      id: 'local',
      name: '本地设备',
      connectionType: 'local',
      version: 'local',
      connected: true,
      isLocalNetwork: true,
      crypto: 'local',
      lastSeen: DateTime.now(),
      folders: [],
    ),
  );

  Future<List<Device>> _applyPairingState(
    List<Device> devices,
    DevicePairingStore store,
  ) async {
    final out = <Device>[];
    for (final d in devices) {
      if (d.isLocal) {
        out.add(d.copyWith(pairingComplete: true));
        continue;
      }
      if (d.connected) {
        await store.markEverConnected(d.id);
      }
      final complete = store.hasEverConnected(d.id);
      out.add(d.copyWith(pairingComplete: complete));
    }
    return out;
  }

  /// 标记设备已完成首次连接（DeviceConnected 事件后调用）
  Future<void> noteDeviceConnected(String deviceId) async {
    if (deviceId.trim().isEmpty) return;
    await DevicePairingStore.instance.markEverConnected(deviceId);
    _devices = await _applyPairingState(_devices, DevicePairingStore.instance);
    notifyListeners();
  }

  // 获取所有设备；silent=true 时不显示全屏 loading（后台刷新用）
  Future<void> fetchDevices({bool silent = false}) async {
    try {
      if (!silent) {
        _isLoading = true;
        _error = null;
        notifyListeners();
      }

      final devices = await ApiService.getDevices();
      final store = DevicePairingStore.instance;
      await store.ensureLoaded();
      await store.migrateExistingConfiguredDevices(
        devices.where((d) => !d.isLocal).map((d) => d.id),
      );
      _devices = await _applyPairingState(devices, store);
      if (silent) _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) _isLoading = false;
      notifyListeners();
    }
  }

  // 添加设备（不走全屏 loading，避免父页重建导致添加弹框关不掉）
  Future<void> addDevice({
    required String deviceID,
    required String name,
  }) async {
    try {
      await ApiService.addDevice(
        deviceID: deviceID,
        name: name,
      );
      // 先刷新已配置列表，再依赖 configured 过滤发现弹窗（勿 unignore，否则会短暂再次弹出）
      await fetchDevices(silent: true);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // 删除设备（不走全屏 loading，避免移动端卸掉当前页导致无法跳回本机）
  Future<void> removeDevice(String deviceId) async {
    try {
      await ApiService.removeDevice(deviceId);
      await DiscoveredDevicesStore.instance.ignore(deviceId);
      await DevicePairingStore.instance.clearPairing(deviceId);
      await fetchDevices(silent: true);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
