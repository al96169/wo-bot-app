// 机器人数据模型 — 匹配 web-debug types/index.ts

// ============== 摄像头 ==============
class CameraInfo {
  final int cameraId;
  final String name;
  final String? devicePath;
  final int? width;
  final int? height;
  final int? fps;
  final String status; // active/inactive/error
  final String? streamUrl;

  const CameraInfo({required this.cameraId, required this.name, this.devicePath, this.width, this.height, this.fps, this.status = 'inactive', this.streamUrl});

  factory CameraInfo.fromJson(Map<String, dynamic> json) => CameraInfo(
    cameraId: json['camera_id'] as int? ?? json['id'] as int? ?? 0,
    name: json['name'] as String? ?? 'camera_${json['camera_id'] ?? 0}',
    devicePath: json['device_path'] as String?,
    width: json['width'] as int?,
    height: json['height'] as int?,
    fps: json['fps'] as int?,
    status: json['status'] as String? ?? 'inactive',
    streamUrl: json['stream_url'] as String?,
  );
}

// ============== 云台 ==============
class GimbalState {
  double pan; // 0-180
  double tilt; // 0-180
  GimbalState({this.pan = 90, this.tilt = 90});

  void update(double p, double t) {
    pan = p.clamp(0, 180);
    tilt = t.clamp(0, 180);
  }
}

// ============== 系统状态 ==============
class SystemStatusData {
  double batteryLevel;
  bool batteryCharging;
  double cpuUsage;
  double memoryUsage;
  double diskUsage;
  String? wifiSSID;
  int wifiSignal;
  String? ip;
  String? hostname;
  int uptime;
  double? cpuTemp;
  String? model;
  String? version;

  SystemStatusData({
    this.batteryLevel = 0, this.batteryCharging = false,
    this.cpuUsage = 0, this.memoryUsage = 0, this.diskUsage = 0,
    this.wifiSSID, this.wifiSignal = 0, this.ip, this.hostname,
    this.uptime = 0, this.cpuTemp, this.model, this.version,
  });

  void updateFromJson(Map<String, dynamic> json) {
    // 兼容两种格式：
    // - 真机 (wo-bot-control): {battery: {level, status, temperature, estimated_minutes}, system: {cpu_percent, ...}, network: {ssid, signal_strength, ip}}
    // - mock/扁平: {battery: 95, cpu: 50, wifi_ssid: "...", ...}
    Map<String, dynamic> obj(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : const {};

    final batt = obj(json['battery']);
    final sys = obj(json['system']);
    final net = obj(json['network']);

    batteryLevel = _num(batt['level']) ?? _num(json['battery']) ?? _num(json['batteryLevel']) ?? batteryLevel;
    batteryCharging = batt['status'] == 'charging' ||
        batt['charging'] == true ||
        json['battery_charging'] == true ||
        json['batteryCharging'] == true ||
        batteryCharging;
    cpuUsage = _num(sys['cpu_percent']) ?? _num(json['cpu']) ?? _num(json['cpuUsage']) ?? cpuUsage;
    memoryUsage = _num(sys['memory_percent']) ?? _num(json['memory']) ?? _num(json['memoryUsage']) ?? memoryUsage;
    diskUsage = _num(sys['disk_percent']) ?? _num(json['disk']) ?? _num(json['diskUsage']) ?? diskUsage;
    wifiSSID = net['ssid'] as String? ?? json['wifi_ssid'] as String? ?? json['wifiSSID'] as String? ?? wifiSSID;
    wifiSignal = (net['signal_strength'] as num?)?.toInt() ??
        _num(json['wifi_signal'])?.toInt() ??
        _num(json['wifiSignal'])?.toInt() ??
        wifiSignal;
    ip = net['ip'] as String? ?? json['ip'] as String? ?? ip;
    hostname = sys['hostname'] as String? ?? json['hostname'] as String? ?? hostname;
    uptime = _num(sys['uptime'])?.toInt() ?? _num(json['uptime'])?.toInt() ?? uptime;
    cpuTemp = _num(sys['temperature']) ?? _num(json['cpu_temp']) ?? _num(json['cpuTemp']) ?? cpuTemp;
    model = json['model'] as String? ?? model;
    version = json['version'] as String? ?? version;
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    return null;
  }
}

// ============== 日志 (匹配 web-debug LogEntry) ==============
class LogEntry {
  final String id;
  final int lineNo;
  final String time;
  final String level; // debug/info/warn/error
  final String source;
  final String message;

  const LogEntry({
    required this.id,
    required this.lineNo,
    required this.time,
    required this.level,
    required this.source,
    required this.message,
  });
}

// ============== 消息 (匹配 web-debug Message) ==============
/// 机器人消息 — 由机器人 `service_message` 推送产生（对齐 web-debug robotStore.messages）
class RobotMessage {
  final String id;
  final String subject;
  final DateTime time;
  final String summary;
  final String body;
  final bool read;
  final String source;
  final String severity; // info / warning / error

  const RobotMessage({
    required this.id,
    required this.subject,
    required this.time,
    this.summary = '',
    this.body = '',
    this.read = false,
    this.source = 'service_manager',
    this.severity = 'info',
  });

  RobotMessage copyWith({bool? read}) => RobotMessage(
    id: id,
    subject: subject,
    time: time,
    summary: summary,
    body: body,
    read: read ?? this.read,
    source: source,
    severity: severity,
  );
}

// ============== 模块 ==============
class Module {
  final String id;
  final String name;
  final String version;
  final String status;
  final bool enabled;

  const Module({required this.id, required this.name, required this.version, this.status = 'stopped', this.enabled = true});

  factory Module.fromJson(Map<String, dynamic> json) => Module(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    version: json['version'] as String? ?? '',
    status: json['status'] as String? ?? 'stopped',
    enabled: json['enabled'] as bool? ?? true,
  );
}

// ============== 服务 ==============
class ServiceInfo {
  final String serviceId;
  final String name;
  final String status;
  final int? pid;
  final int restartCount;
  final String? lastError;
  final int? uptime;

  const ServiceInfo({required this.serviceId, required this.name, this.status = 'stopped', this.pid, this.restartCount = 0, this.lastError, this.uptime});

  factory ServiceInfo.fromJson(Map<String, dynamic> json) => ServiceInfo(
    serviceId: json['service_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    status: json['status'] as String? ?? 'stopped',
    pid: (json['pid'] as num?)?.toInt(),
    restartCount: (json['restart_count'] as num?)?.toInt() ?? 0,
    lastError: json['last_error'] as String?,
    uptime: (json['uptime'] as num?)?.toInt(),
  );
}

// ============== 舞蹈 ==============
class DanceInfo {
  final String id;
  final String name;
  final String? icon;
  final double durationSec;

  const DanceInfo({required this.id, required this.name, this.icon, this.durationSec = 0});

  factory DanceInfo.fromJson(Map<String, dynamic> json) => DanceInfo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    icon: json['icon'] as String?,
    durationSec: (json['duration_sec'] as num?)?.toDouble() ?? 0,
  );
}

// ============== 音乐 ==============
class MusicTrack {
  final String name;
  final String filename;
  final String? path;
  final int? size;
  final String? format;
  final double? duration;

  const MusicTrack({required this.name, required this.filename, this.path, this.size, this.format, this.duration});

  factory MusicTrack.fromJson(Map<String, dynamic> json) => MusicTrack(
    name: json['name'] as String? ?? '',
    filename: json['filename'] as String? ?? json['name'] as String? ?? '',
    path: json['path'] as String?,
    size: json['size'] as int?,
    format: json['format'] as String?,
    duration: (json['duration'] as num?)?.toDouble(),
  );
}

class MusicStatus {
  String status; // stopped/playing/paused
  int volume;
  double position;
  MusicTrack? currentTrack;
  List<MusicTrack> playlist;
  bool streaming;
  String? streamType;
  List<String> activeServices;
  String? activeSource;

  MusicStatus({
    this.status = 'stopped', this.volume = 75, this.position = 0,
    this.currentTrack, this.playlist = const [], this.streaming = false,
    this.streamType, this.activeServices = const [], this.activeSource,
  });

  void updateFromJson(Map<String, dynamic> json) {
    status = json['status'] as String? ?? status;
    volume = json['volume'] as int? ?? volume;
    position = (json['position'] as num?)?.toDouble() ?? position;
    if (json['current_track'] != null) {
      currentTrack = MusicTrack.fromJson(json['current_track'] as Map<String, dynamic>);
    }
    if (json['playlist'] != null) {
      playlist = (json['playlist'] as List).map((t) => MusicTrack.fromJson(t as Map<String, dynamic>)).toList();
    }
    streaming = json['streaming'] as bool? ?? streaming;
    streamType = json['stream_type'] as String? ?? streamType;
    activeSource = json['active_source'] as String? ?? activeSource;
  }
}

// ============== 软件 ==============
class Software {
  final String name;
  final String displayName;
  final String? description;
  final String? version;
  final String? category;
  final bool critical;
  final String? icon;
  bool installed;
  bool? upgradable;

  Software({required this.name, required this.displayName, this.description, this.version, this.category, this.critical = false, this.icon, this.installed = false, this.upgradable});

  factory Software.fromJson(Map<String, dynamic> json) => Software(
    name: json['name'] as String? ?? '',
    displayName: json['display_name'] as String? ?? json['name'] as String? ?? '',
    description: json['description'] as String?,
    version: json['version'] as String?,
    category: json['category'] as String?,
    critical: json['critical'] as bool? ?? false,
    icon: json['icon'] as String?,
    installed: json['installed'] as bool? ?? false,
    upgradable: json['upgradable'] as bool?,
  );
}

// ============== Gallery ==============
class GalleryItem {
  final String id;
  final String name;
  final String type; // photo/video
  final String? thumbnailBase64;
  final int? fileSize;
  final double? durationSec;
  final String? cameraId;
  final String? timestamp;

  const GalleryItem({required this.id, required this.name, required this.type, this.thumbnailBase64, this.fileSize, this.durationSec, this.cameraId, this.timestamp});

  factory GalleryItem.fromJson(Map<String, dynamic> json) => GalleryItem(
    id: json['id'] as String? ?? json['name'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? 'photo',
    thumbnailBase64: json['thumbnail_base64'] as String?,
    fileSize: json['file_size'] as int?,
    durationSec: (json['duration_s'] as num?)?.toDouble(),
    cameraId: json['camera_id'] as String?,
    timestamp: json['timestamp'] as String?,
  );
}

class GalleryStorage {
  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  const GalleryStorage({required this.totalBytes, required this.usedBytes, required this.availableBytes});

  factory GalleryStorage.fromJson(Map<String, dynamic> json) => GalleryStorage(
    totalBytes: json['total_bytes'] as int? ?? 0,
    usedBytes: json['used_bytes'] as int? ?? 0,
    availableBytes: json['available_bytes'] as int? ?? 0,
  );
}
