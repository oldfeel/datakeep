import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/services/android_storage_service.dart';

/// 各平台默认同步目录
Future<String> defaultSyncFolderPath(String folderId) async {
  if (Platform.isAndroid) {
    final path = await AndroidStorageService.getDefaultSyncFolderPath(folderId);
    if (path.isNotEmpty) return path;
    // Platform Channel 不可用时的回退
    final media = '/storage/emulated/0/Android/media/tech.shupi.mydata/sync/$folderId';
    return media;
  }
  if (Platform.isIOS) {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/sync/$folderId';
  }
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/sync/$folderId';
}

/// 检测路径是否对 Syncthing native 可写（Android 动态检测，桌面恒 true）
Future<bool> isSyncPathWritable(String path) async {
  if (path.isEmpty) return false;
  if (!Platform.isAndroid) return true;
  return AndroidStorageService.canWriteToPath(path);
}

/// 路径是否可能需要 All files access 才能写入（用于 UI 提示，非阻断）
bool isPublicStoragePath(String path) {
  if (!Platform.isAndroid) return false;
  final p = path.replaceAll('\\', '/');
  if (p.contains('/Android/data/') || p.contains('/Android/media/')) return false;
  if (p.startsWith('/data/user/')) return false;
  if (p.startsWith('/storage/emulated/0/')) return true;
  if (p == '/sdcard' || p.startsWith('/sdcard/')) return true;
  return false;
}
