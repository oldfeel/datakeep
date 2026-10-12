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
    // Documents/<id>：与 sushitrain / SyncthingCore filesPath 一致（勿用易失效的深层绝对路径）
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, folderId);
  }
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final root = await desktopSyncRoot();
    return p.join(root, folderId);
  }
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/sync/$folderId';
}

/// iOS 应用 Documents 根目录（Files「我的 iPhone / 数据管理」可见）
Future<Directory> iosAppDocumentsDirectory() => getApplicationDocumentsDirectory();

/// 统一 iOS 路径形式（/var ↔ /private/var、解析符号链接），避免误判「不在 Documents」
String _canonicalizeIosPath(String path) {
  var n = p.normalize(path.trim());
  try {
    n = p.normalize(File(n).resolveSymbolicLinksSync());
  } catch (_) {
    // 目录尚未创建时 resolve 会失败，仅做 /private 归一化
  }
  if (n.startsWith('/private/var/')) {
    n = n.substring('/private'.length);
  } else if (n.startsWith('/private/tmp/')) {
    n = n.substring('/private'.length);
  }
  return n;
}

/// iOS：同步目录必须在应用 Documents 下，沙盒外（iCloud 等）进程内 Syncthing 无法持久写入
Future<bool> isIosAppDocumentsPath(String path) async {
  if (!Platform.isIOS) return true;
  final trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  final docs = _canonicalizeIosPath((await iosAppDocumentsDirectory()).path);
  final target = _canonicalizeIosPath(trimmed);
  return target == docs || p.isWithin(docs, target);
}

/// 将选择器路径落到应用 Documents 的规范绝对路径；沙盒外则回退默认同步目录。
/// FilePicker 常返回 `/private/var/...`，与 path_provider 的 `/var/...` 不一致，需统一后再写入 Syncthing。
Future<String> resolveIosWritableSyncPath(String? picked, String folderId) async {
  final fallback = await defaultSyncFolderPath(folderId);
  await Directory(fallback).create(recursive: true);
  final raw = picked?.trim() ?? '';
  if (raw.isEmpty) return fallback;
  if (!await isIosAppDocumentsPath(raw)) return fallback;

  final docsReal = (await iosAppDocumentsDirectory()).path;
  final docsCanon = _canonicalizeIosPath(docsReal);
  final targetCanon = _canonicalizeIosPath(raw);
  final String resolved;
  if (targetCanon == docsCanon) {
    resolved = docsReal;
  } else {
    final rel = p.relative(targetCanon, from: docsCanon);
    resolved = p.join(docsReal, rel);
  }
  await Directory(resolved).create(recursive: true);
  return resolved;
}

/// iOS 默认同步根：Documents（选择器起始目录；与 sushitrain filesPath 一致）
Future<String> iosSyncRootDirectory() async {
  final docs = await iosAppDocumentsDirectory();
  await docs.create(recursive: true);
  return docs.path;
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
  if (Platform.isIOS) {
    return iosSyncRootDirectory();
  }
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final root = await desktopSyncRoot();
    if (await Directory(root).exists()) return root;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) return home;
  }
  return null;
}

/// 检测路径是否对 Syncthing native 可写（Android 动态检测，桌面/iOS 尝试创建探测文件）
Future<bool> isSyncPathWritable(String path) async {
  if (path.isEmpty) return false;
  if (Platform.isAndroid) return AndroidStorageService.canWriteToPath(path);
  // iOS：沙盒外路径即便临时可写，Syncthing 也无法长期使用
  if (Platform.isIOS && !await isIosAppDocumentsPath(path)) return false;
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

/// iOS 同步路径说明（UI 提示）
const String kIosSyncPathHint =
    'iOS 仅支持应用「文件」中的本应用目录（我的 iPhone → 数据管理）。'
    '请勿选择 iCloud 或其他 App 目录。';

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
