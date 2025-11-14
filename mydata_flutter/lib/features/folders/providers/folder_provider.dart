import 'package:flutter/foundation.dart';
import '../../../core/models/folder.dart';
import '../../../core/services/api_service.dart';

class FolderProvider with ChangeNotifier {
  List<Folder> _folders = [];
  bool _isLoading = false;
  String? _error;

  List<Folder> get folders => _folders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // 获取所有文件夹
  Future<void> fetchFolders() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final folders = await ApiService.getFolders();
      _folders = folders;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 创建文件夹
  Future<void> createFolder({
    required String id,
    required String name,
    required String path,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final newFolder = await ApiService.createFolder(
        id: id,
        name: name,
        path: path,
      );
      
      _folders.add(newFolder);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 删除文件夹
  Future<void> deleteFolder(String folderId) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await ApiService.deleteFolder(folderId);
      _folders.removeWhere((folder) => folder.id == folderId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 获取指定设备的文件夹
  Future<List<Folder>> getDeviceFolders(String deviceId) async {
    try {
      final folders = await ApiService.getDeviceFolders(deviceId);
      return folders;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  // 清除错误
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
