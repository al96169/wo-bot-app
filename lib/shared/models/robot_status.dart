/// 机器人运行时状态模型
class RobotStatus {
  final int batteryLevel;
  final bool batteryCharging;
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final String? wifiSSID;
  final int? wifiSignal;
  final String? ip;
  final int uptime;
  final double? temperature;

  const RobotStatus({
    this.batteryLevel = 0,
    this.batteryCharging = false,
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.diskUsage = 0,
    this.wifiSSID,
    this.wifiSignal,
    this.ip,
    this.uptime = 0,
    this.temperature,
  });

  // ---- 计算属性：电池 ----

  /// 电池状态文字
  String get batteryStatusText {
    if (batteryCharging) return '充电中';
    if (batteryLevel <= 10) return '电量极低';
    return '$batteryLevel%';
  }

  /// 电池图标名 (Material Icons)
  String get batteryIcon {
    if (batteryCharging) return 'battery_charging_full';
    if (batteryLevel >= 100) return 'battery_full';
    if (batteryLevel >= 80) return 'battery_6_bar';
    if (batteryLevel >= 60) return 'battery_5_bar';
    if (batteryLevel >= 50) return 'battery_4_bar';
    if (batteryLevel >= 30) return 'battery_3_bar';
    if (batteryLevel >= 20) return 'battery_2_bar';
    return 'battery_1_bar';
  }

  // ---- 计算属性：Wi-Fi ----

  /// Wi-Fi 信号文字描述 (dBm)
  String get wifiSignalText {
    if (wifiSignal == null) return '未知';
    if (wifiSignal! >= -50) return '极好';
    if (wifiSignal! >= -65) return '良好';
    if (wifiSignal! >= -75) return '一般';
    return '较弱';
  }

  /// Wi-Fi 信号图标
  String get wifiIcon {
    if (wifiSignal == null) return 'wifi';
    if (wifiSignal! >= -55) return 'wifi';
    if (wifiSignal! >= -65) return 'network_wifi_3_bar';
    if (wifiSignal! >= -75) return 'network_wifi_2_bar';
    return 'network_wifi_1_bar';
  }

  // ---- 计算属性：运行时间 ----

  /// 运行时间文字 "Xh Ym Zs"
  String get uptimeText {
    final h = uptime ~/ 3600;
    final m = (uptime % 3600) ~/ 60;
    final s = uptime % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// 运行天数
  double get uptimeDays => uptime / 86400.0;

  // ---- 计算属性：温度 ----

  String get temperatureText {
    if (temperature == null) return '--';
    return '${temperature!.toStringAsFixed(1)}°C';
  }

  // ---- 百分比格式化 ----

  String formatPercent(double value) => '${value.toStringAsFixed(1)}%';

  // ---- JSON 序列化 ----

  factory RobotStatus.fromJson(Map<String, dynamic> json) {
    // 真机线格式（对齐 web-debug useWebSocket.ts L1408-1432）：
    // battery.{level,status,temperature} / system.{cpu_percent,memory_percent,disk_percent,uptime,hostname,temperature} / network.{ssid,signal_strength,ip}
    final batt = json['battery'] is Map
        ? Map<String, dynamic>.from(json['battery'] as Map)
        : const <String, dynamic>{};
    final sys = json['system'] is Map
        ? Map<String, dynamic>.from(json['system'] as Map)
        : const <String, dynamic>{};
    final net = json['network'] is Map
        ? Map<String, dynamic>.from(json['network'] as Map)
        : const <String, dynamic>{};

    return RobotStatus(
      batteryLevel: (batt['level'] as num?)?.toInt() ?? 0,
      batteryCharging: batt['status'] == 'charging',
      cpuUsage: (sys['cpu_percent'] as num?)?.toDouble() ?? 0,
      memoryUsage: (sys['memory_percent'] as num?)?.toDouble() ?? 0,
      diskUsage: (sys['disk_percent'] as num?)?.toDouble() ?? 0,
      wifiSSID: net['ssid'] as String?,
      wifiSignal: _parseSignalDbm(net['signal_strength']),
      ip: net['ip'] as String?,
      uptime: _parseUptime(sys['uptime'] ?? json['uptime']),
      temperature: (sys['temperature'] as num?)?.toDouble(),
    );
  }

  static int? _parseSignalDbm(dynamic signal) {
    if (signal == null) return null;
    if (signal is int) return signal;
    // 可能是字符串 "-55 dBm" 或 "good"
    final str = signal.toString();
    final match = RegExp(r'(-?\d+)').firstMatch(str);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static int _parseUptime(dynamic uptime) {
    if (uptime == null) return 0;
    if (uptime is int) return uptime;
    if (uptime is double) return uptime.toInt();
    // 可能是字符串 "1h 30m" — 简化：当作秒
    final secs = int.tryParse(uptime.toString());
    if (secs != null) return secs;
    return 0;
  }
}
