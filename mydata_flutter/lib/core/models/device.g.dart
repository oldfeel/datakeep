// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['id'] as String,
  name: json['name'] as String,
  type: json['type'] as String,
  isLocal: json['isLocal'] as bool,
  status: json['status'] as String,
  lastSeen: DateTime.parse(json['lastSeen'] as String),
  version: json['version'] as String,
  folders: (json['folders'] as List<dynamic>).map((e) => e as String).toList(),
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'type': instance.type,
  'isLocal': instance.isLocal,
  'status': instance.status,
  'lastSeen': instance.lastSeen.toIso8601String(),
  'version': instance.version,
  'folders': instance.folders,
};
