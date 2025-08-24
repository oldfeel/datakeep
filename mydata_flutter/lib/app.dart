import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'shared/themes/app_theme.dart';
import 'features/folders/providers/folder_provider.dart';
import 'features/devices/providers/device_provider.dart';
import 'shared/widgets/main_navigation.dart';

class MyDataApp extends StatelessWidget {
  const MyDataApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FolderProvider()),
        ChangeNotifierProvider(create: (_) => DeviceProvider()),
      ],
      child: MaterialApp(
        title: 'MyData - 文件同步',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const MainNavigation(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
