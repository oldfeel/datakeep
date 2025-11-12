// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['deviceID'] as String,
  name: json['name'] as String,
  addresses: (json['addresses'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  compression: json['compression'] as String?,
  certName: json['certName'] as String?,
  introducer: json['introducer'] as bool? ?? false,
  connected: json['connected'] as bool? ?? false,
  connectionType: json['connectionType'] as String?,
  version: json['clientVersion'] as String?,
  inBytesTotal: (json['inBytesTotal'] as num?)?.toInt(),
  outBytesTotal: (json['outBytesTotal'] as num?)?.toInt(),
  isLocalNetwork: json['isLocalNetwork'] as bool? ?? false,
  crypto: json['crypto'] as String?,
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'deviceID': instance.id,
  'name': instance.name,
  'addresses': instance.addresses,
  'compression': instance.compression,
  'certName': instance.certName,
  'introducer': instance.introducer,
  'connected': instance.connected,
  'connectionType': instance.connectionType,
  'clientVersion': instance.version,
  'inBytesTotal': instance.inBytesTotal,
  'outBytesTotal': instance.outBytesTotal,
  'isLocalNetwork': instance.isLocalNetwork,
  'crypto': instance.crypto,
};
