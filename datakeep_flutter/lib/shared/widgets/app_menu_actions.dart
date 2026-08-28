import 'package:flutter/material.dart';

import '../../core/services/native_service.dart';
import '../../features/apps/screens/market_screen.dart';
import '../../features/feedback/screens/feedback_screen.dart';
import '../../features/notifications/screens/notifications_page.dart';
import '../../core/services/api_service.dart';
import '../constants/app_info.dart';
import '../utils/open_syncthing_gui.dart';
import 'app_logo.dart';
import 'folder_edit_dialog.dart';

/// 桌面设置菜单 / 手机底部菜单的共用项 value
abstract final class AppMenuActions {
  static const messages = 'messages';
  static const qr = 'qr';
  static const market = 'market';
  static const syncthing = 'syncthing';
  static const feedback = 'feedback';
  static const refresh = 'refresh';
  static const about = 'about';
  static const exit = 'exit';
}

Future<void> confirmAndExitApp(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('退出应用'),
      content: const Text('将停止同步服务并退出应用，确定吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('退出'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await NativeService.exitAppCompletely();
}

Future<void> handleSharedAppMenuAction(
  BuildContext context,
  String value, {
  VoidCallback? onRefresh,
}) async {
  switch (value) {
    case AppMenuActions.messages:
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsPage()),
      );
      break;
    case AppMenuActions.qr:
      try {
        final id = await ApiService.getLocalDeviceId();
        if (!context.mounted) return;
        await LocalDeviceQrDialog.show(
          context,
          deviceId: id,
          deviceName: '本机设备',
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('获取本机 ID 失败: $e')),
          );
        }
      }
      break;
    case AppMenuActions.market:
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MarketScreen()),
      );
      break;
    case AppMenuActions.syncthing:
      if (!context.mounted) return;
      openSyncthingGui(context);
      break;
    case AppMenuActions.feedback:
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FeedbackScreen()),
      );
      break;
    case AppMenuActions.refresh:
      onRefresh?.call();
      break;
    case AppMenuActions.about:
      if (!context.mounted) return;
      showAboutDialog(
        context: context,
        applicationName: kAppDisplayName,
        applicationVersion: '1.0.0',
        applicationIcon: const AppLogo(size: 48),
      );
      break;
    case AppMenuActions.exit:
      if (!context.mounted) return;
      await confirmAndExitApp(context);
      break;
  }
}

List<PopupMenuEntry<String>> buildSharedSettingsMenuItems({
  required int unreadCount,
}) {
  return [
    PopupMenuItem(
      value: AppMenuActions.messages,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Badge(
          isLabelVisible: unreadCount > 0,
          label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
          child: const Icon(Icons.notifications_outlined),
        ),
        title: const Text('消息'),
      ),
    ),
    const PopupMenuItem(
      value: AppMenuActions.qr,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.qr_code_2),
        title: Text('本机配对二维码'),
      ),
    ),
    const PopupMenuItem(
      value: AppMenuActions.market,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.storefront_outlined),
        title: Text('应用市场'),
      ),
    ),
    const PopupMenuItem(
      value: AppMenuActions.syncthing,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.open_in_browser),
        title: Text('Syncthing 管理页'),
      ),
    ),
    const PopupMenuItem(
      value: AppMenuActions.feedback,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.feedback_outlined),
        title: Text('意见反馈'),
      ),
    ),
    const PopupMenuItem(
      value: AppMenuActions.refresh,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.refresh),
        title: Text('刷新'),
      ),
    ),
    const PopupMenuItem(
      value: AppMenuActions.about,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.info_outline),
        title: Text('关于'),
      ),
    ),
    const PopupMenuDivider(),
    const PopupMenuItem(
      value: AppMenuActions.exit,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.exit_to_app, color: Colors.red),
        title: Text('退出', style: TextStyle(color: Colors.red)),
      ),
    ),
  ];
}

/// 手机底部菜单中的共用区块（不含设备管理/同步状态）
List<Widget> buildSharedMobileMenuTiles(
  BuildContext context, {
  required VoidCallback closeSheet,
  required int unreadCount,
  VoidCallback? onRefresh,
}) {
  Widget tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required String action,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: color != null ? TextStyle(color: color) : null),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: action == AppMenuActions.messages && unreadCount > 0
          ? Badge(label: Text(unreadCount > 99 ? '99+' : '$unreadCount'))
          : null,
      onTap: () async {
        closeSheet();
        await handleSharedAppMenuAction(
          context,
          action,
          onRefresh: onRefresh,
        );
      },
    );
  }

  return [
    tile(
      icon: Icons.notifications_outlined,
      title: '消息',
      action: AppMenuActions.messages,
    ),
    tile(
      icon: Icons.qr_code_2,
      title: '本机配对二维码',
      action: AppMenuActions.qr,
    ),
    tile(
      icon: Icons.storefront_outlined,
      title: '应用市场',
      subtitle: '浏览并安装应用',
      action: AppMenuActions.market,
    ),
    tile(
      icon: Icons.open_in_browser,
      title: 'Syncthing 管理页',
      subtitle: '高级配置出口',
      action: AppMenuActions.syncthing,
    ),
    tile(
      icon: Icons.feedback_outlined,
      title: '意见反馈',
      subtitle: '提交问题或建议',
      action: AppMenuActions.feedback,
    ),
    tile(
      icon: Icons.refresh,
      title: '刷新',
      action: AppMenuActions.refresh,
    ),
    tile(
      icon: Icons.info_outline,
      title: '关于',
      action: AppMenuActions.about,
    ),
    const Divider(),
    tile(
      icon: Icons.exit_to_app,
      title: '退出',
      action: AppMenuActions.exit,
      color: Colors.red,
    ),
  ];
}
