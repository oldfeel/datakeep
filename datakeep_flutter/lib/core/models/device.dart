import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';

@JsonSerializable()
class Device {
  @JsonKey(name: 'deviceID')
  final String id;
  @JsonKey(name: 'name', defaultValue: '未知设备')
  final String name;
  final List<String>? addresses;
  final String? compression;
  final String? certName;
  final bool introducer;
  final bool connected;
  @JsonKey(name: 'connectionType')
  final String? connectionType;
  @JsonKey(name: 'clientVersion')
  final String? version;
  @JsonKey(name: 'inBytesTotal')
  final int? inBytesTotal;
  @JsonKey(name: 'outBytesTotal')
  final int? outBytesTotal;
  final bool isLocalNetwork;
  final String? crypto;
  
  // 额外字段（不在 JSON 中）
  @JsonKey(includeFromJson: false, includeToJson: false)
  final DateTime? lastSeen;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final List<String> folders;
  /// 是否已完成首次配对（曾成功连接）；false 时 UI 显示「待确认」
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bool pairingComplete;

  Device({
    required this.id,
    required this.name,
    this.addresses,
    this.compression,
    this.certName,
    this.introducer = false,
    this.connected = false,
    this.connectionType,
    this.version,
    this.inBytesTotal,
    this.outBytesTotal,
    this.isLocalNetwork = false,
    this.crypto,
    this.lastSeen,
    this.folders = const [],
    this.pairingComplete = true,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    // 确保必需字段不为 null
    final deviceID = json['deviceID']?.toString();
    if (deviceID == null || deviceID.isEmpty) {
      throw FormatException('Device JSON missing required field: deviceID', json);
    }
    
    final nameRaw = json['name']?.toString().trim() ?? '';
    final name = nameRaw.isNotEmpty ? nameRaw : '未知设备';
    
    // 创建清理后的 JSON
    final cleanedJson = Map<String, dynamic>.from(json);
    cleanedJson['deviceID'] = deviceID;
    cleanedJson['name'] = name;
    
    return _$DeviceFromJson(cleanedJson);
  }
  Map<String, dynamic> toJson() => _$DeviceToJson(this);

  // 判断是否为本机设备
  bool get isLocal {
    return id == 'local' ||
        connectionType == 'local' ||
        version == 'local' ||
        crypto == 'local';
  }

  // 获取设备类型（根据名称推断）
  String get type {
    final nameLower = name.toLowerCase();
    if (nameLower.contains('android') || nameLower.contains('mobile')) {
      return 'mobile';
    } else if (nameLower.contains('server')) {
      return 'server';
    } else {
      return 'desktop';
    }
  }

  // 获取状态：未完成首次配对 → 待确认；之后按连接显示在线/离线
  String get status {
    if (isLocal) return 'online';
    if (!pairingComplete) return 'pending';
    if (connected) return 'online';
    return 'offline';
  }

  /// 连接状态文案（本机 / 待确认 / 在线 / 离线）
  String get connectionLabel {
    if (isLocal) return '本机设备';
    switch (status) {
      case 'pending':
        return '待确认';
      case 'online':
        return '在线';
      default:
        return '离线';
    }
  }

  /// 用于 UI 展示的名称（空名/localhost/设备 ID 时做友好化处理）
  String get displayName {
    final n = name.trim();
    final norm = (String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    final shortId = id.contains('-') ? id.split('-').first.toUpperCase() : '';
    if (n.isNotEmpty &&
        n.toLowerCase() != 'localhost' &&
        norm(n) != norm(id) &&
        (shortId.isEmpty || n.toUpperCase() != shortId)) {
      return n;
    }
    if (id.contains('-')) return id.split('-').first;
    final clean = id.replaceAll(RegExp(r'[\s-]'), '');
    return clean.length >= 7 ? clean.substring(0, 7) : id;
  }

  Device copyWith({
    String? id,
    String? name,
    List<String>? addresses,
    String? compression,
    String? certName,
    bool? introducer,
    bool? connected,
    String? connectionType,
    String? version,
    int? inBytesTotal,
    int? outBytesTotal,
    bool? isLocalNetwork,
    String? crypto,
    DateTime? lastSeen,
    List<String>? folders,
    bool? pairingComplete,
  }) {
    return Device(
      id: id ?? this.id,
      name: name ?? this.name,
      addresses: addresses ?? this.addresses,
      compression: compression ?? this.compression,
      certName: certName ?? this.certName,
      introducer: introducer ?? this.introducer,
      connected: connected ?? this.connected,
      connectionType: connectionType ?? this.connectionType,
      version: version ?? this.version,
      inBytesTotal: inBytesTotal ?? this.inBytesTotal,
      outBytesTotal: outBytesTotal ?? this.outBytesTotal,
      isLocalNetwork: isLocalNetwork ?? this.isLocalNetwork,
      crypto: crypto ?? this.crypto,
      lastSeen: lastSeen ?? this.lastSeen,
      folders: folders ?? this.folders,
      pairingComplete: pairingComplete ?? this.pairingComplete,
    );
  }
}
