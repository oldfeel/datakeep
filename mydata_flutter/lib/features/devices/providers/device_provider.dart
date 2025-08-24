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
      type: 'desktop',
      isLocal: true,
      status: 'online',
      lastSeen: DateTime.now(),
      version: '1.0.0',
      folders: [],
    ),
  );

  // 获取所有设备
  Future<void> fetchDevices() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final devices = await ApiService.getDevices();
      _devices = devices;
    } catch (e) {
      _error = e.toString();
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
