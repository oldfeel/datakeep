import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'shared/themes/app_theme.dart';
import 'shared/constants/app_info.dart';
import 'features/folders/providers/folder_provider.dart';
import 'features/devices/providers/device_provider.dart';
import 'core/services/syncthing_service_manager.dart';
import 'shared/widgets/main_navigation.dart';
import 'shared/widgets/android_storage_gate.dart';
import 'desktop/pages/home_page.dart';

class DataKeepApp extends StatelessWidget {
  const DataKeepApp({super.key});

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
        title: kAppDisplayName,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: isDesktop
            ? const DesktopHomePage()
            : const AndroidStorageGate(child: MainNavigation()),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
