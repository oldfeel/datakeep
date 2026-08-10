import 'package:json_annotation/json_annotation.dart';

part 'folder.g.dart';

@JsonSerializable()
class Folder {
  final String id;
  final String name;
  final String path;
  final String deviceId;
  final bool isLocal;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String status; // 'syncing', 'synced', 'error'
  final int fileCount;
  final int totalSize; // 字节数
  /// 对端可见权限：sync / readonly（本机列表通常为空）
  final String? access;
  /// folder | app
  final String kind;

  Folder({
    required this.id,
    required this.name,
    required this.path,
    required this.deviceId,
    required this.isLocal,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.fileCount,
    required this.totalSize,
    this.access,
    this.kind = 'folder',
  });

  factory Folder.fromJson(Map<String, dynamic> json) => _$FolderFromJson(json);
  Map<String, dynamic> toJson() => _$FolderToJson(this);

  bool get isApp => kind == 'app';
  bool get isReadonlyAccess => access == 'readonly';
  bool get isSyncAccess => access == null || access == 'sync';

  Folder copyWith({
    String? id,
    String? name,
    String? path,
    String? deviceId,
    bool? isLocal,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
    int? fileCount,
    int? totalSize,
    String? access,
    String? kind,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      deviceId: deviceId ?? this.deviceId,
      isLocal: isLocal ?? this.isLocal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      fileCount: fileCount ?? this.fileCount,
      totalSize: totalSize ?? this.totalSize,
      access: access ?? this.access,
      kind: kind ?? this.kind,
    );
  }
}
