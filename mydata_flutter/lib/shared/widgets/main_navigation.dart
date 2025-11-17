import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../features/devices/providers/device_provider.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/folders/screens/folders_screen.dart';
import '../../features/devices/screens/devices_screen.dart';
import '../../features/sync/screens/sync_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(), // 首页：设备 tab + 文件夹列表
    const FoldersScreen(),
    const DevicesScreen(),
    const SyncScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 初始化数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FolderProvider>().fetchFolders();
      context.read<DeviceProvider>().fetchDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 桌面端和移动端都直接显示内容，不显示左侧菜单
    return _screens[_currentIndex];
  }

}
