import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../features/folders/providers/folder_provider.dart';
import '../../features/devices/providers/device_provider.dart';
import '../../core/services/syncthing_service_manager.dart';
import '../../features/folders/screens/folders_screen.dart';
import '../../features/devices/screens/devices_screen.dart';
import '../../features/sync/screens/sync_screen.dart';
import 'service_control_widget.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
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
      context.read<SyncthingServiceManager>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 检测是否为桌面端
    final isDesktop = MediaQuery.of(context).size.width > 600;
    
    if (isDesktop) {
      return _buildDesktopLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  // 桌面端布局 - 侧边栏导航
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 侧边栏
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // 应用标题
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync,
                        color: Theme.of(context).colorScheme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'MyData',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // 导航菜单
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      // 服务控制组件
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: ServiceControlWidget(),
                      ),
                      const Divider(),
                      _buildDesktopNavItem(
                        icon: Icons.folder,
                        label: '文件夹管理',
                        index: 0,
                      ),
                      _buildDesktopNavItem(
                        icon: Icons.devices,
                        label: '设备管理',
                        index: 1,
                      ),
                      _buildDesktopNavItem(
                        icon: Icons.sync,
                        label: '同步状态',
                        index: 2,
                      ),
                    ],
                  ),
                ),
                // 底部信息
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        '版本 1.0.0',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 主内容区域
          Expanded(
            child: _screens[_currentIndex],
          ),
        ],
      ),
    );
  }

  // 移动端布局 - 底部导航
  Widget _buildMobileLayout() {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder),
            label: '文件夹',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync),
            label: '同步',
          ),
        ],
      ),
    );
  }

  // 桌面端导航项
  Widget _buildDesktopNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected 
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected 
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onTap: () {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
    );
  }
}
