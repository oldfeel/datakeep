import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'app.dart';
import 'core/services/native_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 桌面端：自动启动 Backend 服务
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    try {
      debugPrint('正在启动 Backend 服务...');
      final started = await NativeService.startBackendService();
      if (started) {
        debugPrint('Backend 服务启动成功');
      } else {
        debugPrint('Backend 服务启动失败，但继续启动应用');
      }
    } catch (e) {
      debugPrint('启动 Backend 服务时出错: $e');
    }
  }
  
  runApp(const MyDataApp());
}
