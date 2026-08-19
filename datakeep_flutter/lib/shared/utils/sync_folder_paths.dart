import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/android_storage_service.dart';

const _desktopSyncRootKey = 'desktop_sync_root';

/// 桌面端同步根目录。
/// 优先级：环境变量 DATAKEEP_SYNC_ROOT → SharedPreferences → ~/Sync
Future<String> desktopSyncRoot() async {
  final fromEnv = Platform.environment['DATAKEEP_SYNC_ROOT']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

  final prefs = await SharedPreferences.getInstance();
  final fromPrefs = prefs.getString(_desktopSyncRootKey)?.trim();
  if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;

  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  if (home.isNotEmpty) return p.join(home, 'Sync');

  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, 'sync');
}

/// 接受后记住桌面同步根目录（路径为 `<根>/<folderId>` 时保存 `<根>`）
Future<void> rememberDesktopSyncRoot(String folderPath, {String? folderId}) async {
  if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) return;
  final trimmed = folderPath.trim();
  if (trimmed.isEmpty) return;
  var root = trimmed;
  final id = folderId?.trim();
  if (id != null && id.isNotEmpty && p.basename(trimmed) == id) {
    root = p.dirname(trimmed);
  }
  if (root.isEmpty) return;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_desktopSyncRootKey, root);
}

/// 各平台默认同步目录
Future<String> defaultSyncFolderPath(String folderId) async {
  if (Platform.isAndroid) {
    final path = await AndroidStorageService.getDefaultSyncFolderPath(folderId);
    if (path.isNotEmpty) return path;
    // Platform Channel 不可用时的回退
    final media = '/storage/emulated/0/Android/media/site.datakeep/sync/$folderId';
    return media;
  }
  if (Platform.isIOS) {
    // Documents/sync/<id>：Files App 可见，与 SyncthingCore filesPath 一致
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/sync/$folderId';
  }
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final root = await desktopSyncRoot();
    return p.join(root, folderId);
  }
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/sync/$folderId';
}

/// 打开目录选择器时的起始目录
Future<String?> syncFolderPickerInitialDirectory(String currentPath) async {
  final trimmed = currentPath.trim();
  if (trimmed.isNotEmpty) {
    final dir = Directory(trimmed);
    if (await dir.exists()) return trimmed;
    final parent = p.dirname(trimmed);
    if (parent.isNotEmpty && parent != trimmed && await Directory(parent).exists()) {
      return parent;
    }
  }
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final root = await desktopSyncRoot();
    if (await Directory(root).exists()) return root;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) return home;
  }
  return null;
}

/// 检测路径是否对 Syncthing native 可写（Android 动态检测，桌面尝试创建探测文件）
Future<bool> isSyncPathWritable(String path) async {
  if (path.isEmpty) return false;
  if (Platform.isAndroid) return AndroidStorageService.canWriteToPath(path);
  try {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final probe = File(p.join(path, '.datakeep_write_probe'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// 路径是否可能需要 All files access 才能写入（用于 UI 提示，非阻断）
bool isPublicStoragePath(String path) {
  if (!Platform.isAndroid) return false;
  final normalized = path.replaceAll('\\', '/');
  if (normalized.contains('/Android/data/') || normalized.contains('/Android/media/')) return false;
  if (normalized.startsWith('/data/user/')) return false;
  if (normalized.startsWith('/storage/emulated/0/')) return true;
  if (normalized == '/sdcard' || normalized.startsWith('/sdcard/')) return true;
  return false;
}
