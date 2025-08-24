import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';

@JsonSerializable()
class Device {
  final String id;
  final String name;
  final String type; // 'desktop', 'mobile', 'server'
  final bool isLocal;
  final String status; // 'online', 'offline', 'syncing'
  final DateTime lastSeen;
  final String version;
  final List<String> folders; // 文件夹ID列表

  Device({
    required this.id,
    required this.name,
    required this.type,
    required this.isLocal,
    required this.status,
    required this.lastSeen,
    required this.version,
    required this.folders,
  });

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceToJson(this);

  Device copyWith({
    String? id,
    String? name,
    String? type,
    bool? isLocal,
    String? status,
    DateTime? lastSeen,
    String? version,
    List<String>? folders,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      isLocal: isLocal ?? this.isLocal,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      version: version ?? this.version,
      folders: folders ?? this.folders,
    );
  }
}
