import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/syncthing_api.dart';

/// 旧版删除设备会写入 remoteIgnoredDevices，导致双方删除后再添加无法弹窗。
/// 升级后清空一次忽略列表（用户曾点「忽略」的设备可能再弹一次，可再忽略）。
class DeviceIgnoreMigration {
  DeviceIgnoreMigration._();

  static const _prefKey = 'cleared_delete_remote_ignores_v1';

  static Future<void> runOnceWhenReady() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefKey) == true) return;

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        if (await SyncthingApi().isRunning()) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!await SyncthingApi().isRunning()) {
        debugPrint('[migrate] Syncthing 未就绪，跳过清空 remoteIgnoredDevices');
        return;
      }

      final result = await SyncthingApi().clearAllRemoteIgnoredDevices();
      if (result.containsKey('error')) {
        debugPrint('[migrate] 清空 remoteIgnoredDevices 失败: ${result['error']}');
        return;
      }
      await prefs.setBool(_prefKey, true);
      debugPrint('[migrate] 已清空 remoteIgnoredDevices（删除即忽略 迁移）');
    } catch (e, st) {
      debugPrint('[migrate] remoteIgnoredDevices 迁移异常: $e\n$st');
    }
  }
}
