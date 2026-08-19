/// 机器人设备模型
class RobotDevice {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String serviceName;
  final List<String> capabilities;
  final DateTime lastSeen;
  final bool localAvailable;
  final bool bound;
  final int? signalDbm;
  final int? batteryLevel;
  final int latencyMs;

  RobotDevice({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.serviceName,
    this.capabilities = const <String>[],
    DateTime? lastSeen,
    this.localAvailable = false,
    this.bound = false,
    this.signalDbm,
    this.batteryLevel,
    this.latencyMs = 0,
  }) : lastSeen = lastSeen ?? DateTime.now();

  // ---- 便捷方法 ----

  /// 检查是否具备某项能力
  bool hasCapability(String capability) {
    return capabilities.any((c) => c.toLowerCase() == capability.toLowerCase());
  }

  /// 是否支持摄像头
  bool get hasCamera => hasCapability('camera');

  /// 是否支持 SSH
  bool get hasSSH => hasCapability('ssh');

  /// 能力标签列表
  List<String> get capabilityLabels {
    final labels = <String>[];
    if (hasCamera) labels.add('摄像头');
    if (hasSSH) labels.add('SSH');
    if (hasCapability('webrtc')) labels.add('WebRTC');
    if (hasCapability('gimbal')) labels.add('云台');
    return labels;
  }

  // ---- JSON 序列化 ----

  factory RobotDevice.fromJson(Map<String, dynamic> json) {
    return RobotDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
      serviceName: json['serviceName'] as String,
      capabilities:
          (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String) ?? DateTime.now()
          : DateTime.now(),
      localAvailable: json['localAvailable'] as bool? ?? false,
      bound: json['bound'] as bool? ?? false,
      signalDbm: json['signalDbm'] as int?,
      batteryLevel: json['batteryLevel'] as int?,
      latencyMs: json['latencyMs'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'serviceName': serviceName,
      'capabilities': capabilities,
      'lastSeen': lastSeen.toIso8601String(),
      'localAvailable': localAvailable,
      'bound': bound,
      'signalDbm': signalDbm,
      'batteryLevel': batteryLevel,
      'latencyMs': latencyMs,
    };
  }

  // ---- copyWith ----

  RobotDevice copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? serviceName,
    List<String>? capabilities,
    DateTime? lastSeen,
    bool? localAvailable,
    bool? bound,
    int? signalDbm,
    int? batteryLevel,
    int? latencyMs,
  }) {
    return RobotDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      serviceName: serviceName ?? this.serviceName,
      capabilities: capabilities ?? this.capabilities,
      lastSeen: lastSeen ?? this.lastSeen,
      localAvailable: localAvailable ?? this.localAvailable,
      bound: bound ?? this.bound,
      signalDbm: signalDbm ?? this.signalDbm,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }

  // ---- 相等性 ----

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RobotDevice &&
          id == other.id &&
          name == other.name &&
          ip == other.ip &&
          port == other.port &&
          serviceName == other.serviceName;

  @override
  int get hashCode => Object.hash(id, name, ip, port, serviceName);

  @override
  String toString() => 'RobotDevice(id: $id, name: $name, ip: $ip:$port)';
}
