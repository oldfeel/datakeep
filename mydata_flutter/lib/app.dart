import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'shared/themes/app_theme.dart';
import 'features/folders/providers/folder_provider.dart';
import 'features/devices/providers/device_provider.dart';
import 'core/services/syncthing_service_manager.dart';
import 'shared/widgets/main_navigation.dart';
import 'desktop/pages/home_page.dart';

class MyDataApp extends StatelessWidget {
  const MyDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FolderProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ChangeNotifierProvider(create: (_) => SyncthingServiceManager()),
      ],
      child: MaterialApp(
        title: 'MyData - 文件同步',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: isDesktop ? const DesktopHomePage() : const MainNavigation(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
