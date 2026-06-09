class NetworkModel {
  final String id;
  final String ownerId;
  final String name;
  final String? gatewayMac;
  final String? gatewayIp;

  NetworkModel({
    required this.id,
    required this.ownerId,
    required this.name,
    this.gatewayMac,
    this.gatewayIp,
  });

  factory NetworkModel.fromJson(Map<String, dynamic> json) {
    return NetworkModel(
      id: json['id'],
      ownerId: json['owner_id'],
      name: json['name'],
      gatewayMac: json['gateway_mac'],
      gatewayIp: json['gateway_ip'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'owner_id': ownerId,
      'name': name,
      'gateway_mac': gatewayMac,
      'gateway_ip': gatewayIp,
    };
  }
}

class DeviceModel {
  final String? id;
  final String networkId;
  final String ipAddress;
  final String? macAddress;
  final String? hostname;
  final String? brand;
  final String? customName;
  final String iconType;
  final bool isFavorite;
  final DateTime? lastSeen;
  final String? personId;

  DeviceModel({
    this.id,
    required this.networkId,
    required this.ipAddress,
    this.macAddress,
    this.hostname,
    this.brand,
    this.customName,
    this.iconType = 'device_unknown',
    this.isFavorite = false,
    this.lastSeen,
    this.personId,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'],
      networkId: json['network_id'],
      ipAddress: json['ip_address'],
      macAddress: json['mac_address'],
      hostname: json['hostname'],
      brand: json['brand'],
      customName: json['custom_name'],
      iconType: json['icon_type'] ?? 'device_unknown',
      isFavorite: json['is_favorite'] ?? false,
      lastSeen: json['last_seen'] != null ? DateTime.parse(json['last_seen']) : null,
      personId: json['person_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'network_id': networkId,
      'ip_address': ipAddress,
      'mac_address': macAddress,
      'hostname': hostname,
      'brand': brand,
      'custom_name': customName,
      'icon_type': iconType,
      'is_favorite': isFavorite,
      if (lastSeen != null) 'last_seen': lastSeen!.toIso8601String(),
      if (personId != null) 'person_id': personId,
    };
  }
}

class PersonModel {
  final String id;
  final String userId;
  final String name;

  PersonModel({
    required this.id,
    required this.userId,
    required this.name,
  });

  factory PersonModel.fromJson(Map<String, dynamic> json) {
    return PersonModel(
      id: json['id'],
      userId: json['user_id'],
      name: json['name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'user_id': userId,
      'name': name,
    };
  }
}
