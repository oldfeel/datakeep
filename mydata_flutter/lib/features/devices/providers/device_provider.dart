import 'package:flutter/foundation.dart';
import '../../../core/models/device.dart';
import '../../../core/services/api_service.dart';

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

  // 获取所有设备；silent=true 时不显示全屏 loading（后台刷新用）
  Future<void> fetchDevices({bool silent = false}) async {
    try {
      if (!silent) {
        _isLoading = true;
        _error = null;
        notifyListeners();
      }

      final devices = await ApiService.getDevices();
      _devices = devices;
      if (silent) _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) _isLoading = false;
      notifyListeners();
    }
  }

  // 添加设备
  Future<void> addDevice({
    required String deviceID,
    required String name,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await ApiService.addDevice(
        deviceID: deviceID,
        name: name,
      );
      
      // 刷新设备列表
      await fetchDevices();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 删除设备
  Future<void> removeDevice(String deviceId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await ApiService.removeDevice(deviceId);
      
      // 刷新设备列表
      await fetchDevices();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
