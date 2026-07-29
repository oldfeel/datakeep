// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'folder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Folder _$FolderFromJson(Map<String, dynamic> json) => Folder(
  id: json['id'] as String,
  name: json['name'] as String,
  path: json['path'] as String,
  deviceId: json['deviceId'] as String,
  isLocal: json['isLocal'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  status: json['status'] as String,
  fileCount: (json['fileCount'] as num).toInt(),
  totalSize: (json['totalSize'] as num).toInt(),
  access: json['access'] as String?,
);

Map<String, dynamic> _$FolderToJson(Folder instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'path': instance.path,
  'deviceId': instance.deviceId,
  'isLocal': instance.isLocal,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'status': instance.status,
  'fileCount': instance.fileCount,
  'totalSize': instance.totalSize,
  'access': instance.access,
};
