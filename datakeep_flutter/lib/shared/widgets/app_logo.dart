import 'package:flutter/material.dart';
import '../constants/app_info.dart';

/// 方形应用图标
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kAppIconAsset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// 应用 Logo（欢迎页等）
class AppBrandLogo extends StatelessWidget {
  final double height;

  const AppBrandLogo({super.key, this.height = 96});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kAppLogoAsset,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}
