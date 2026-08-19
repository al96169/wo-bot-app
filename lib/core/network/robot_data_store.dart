import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/robot_data.dart';

/// 机器人全部数据状态 — 匹配 web-debug src/stores/robot.ts
class RobotDataStore extends StateNotifier<int> {
  // 系统状态
  final SystemStatusData system = SystemStatusData();
  // 摄像头
  final List<CameraInfo> cameras = [];
  // 云台
  final GimbalState gimbal = GimbalState();
  // 模块
  final List<Module> modules = [];
  // 服务
  final List<ServiceInfo> services = [];
  // 舞蹈
  final List<DanceInfo> dances = [];
  String danceStatus = 'stopped';
  String? danceCurrentId;
  double danceProgress = 0;
  bool danceLoop = false;
  // 音乐
  final MusicStatus music = MusicStatus();
  final List<MusicTrack> musicSongs = [];
  // 软件
  final List<Software> softwareInstalled = [];
  final List<Software> softwareAvailable = [];
  // 日志 (匹配 web-debug robotStore.logs)
  final List<LogEntry> logs = [];
  int logCursor = 0;
  bool logHasMore = false;
  // 消息 (匹配 web-debug robotStore.messages)
  final List<RobotMessage> messages = [];
  // 图库
  final List<GalleryItem> galleryItems = [];
  GalleryStorage? galleryStorage;
  int galleryPage = 1;
  int galleryTotal = 0;
  int galleryPageSize = 20;
  bool galleryHasMore = false;
  bool galleryLoading = false;
  // 录制
  bool isRecording = false;
  String? recordingCameraId;
  int recordingElapsedS = 0;
  // 画质
  String streamQuality = 'auto';
  // WiFi 扫描
  final List<Map<String, dynamic>> wifiNetworks = [];
  String wifiCurrentSSID = '';
  // 省电策略
  String powerMode = 'normal';
  int powerThreshold = 30;
  // 功能列表
  final List<String> remoteFeatures = [];

  RobotDataStore() : super(0);

  void notify() => state++; // 每次数据变化递增版本号触发 UI 重建

  // ---- 状态更新 ----
  void updateFromStatus(Map<String, dynamic> data) {
    system.updateFromJson(data);
    notify();
  }

  void setCamerasFromList(dynamic list) {
    cameras.clear();
    if (list is List) {
      for (final c in list) {
        if (c is Map) cameras.add(CameraInfo.fromJson(c.cast<String, dynamic>()));
      }
    }
    notify();
  }

  void updateCameraStatus(int id, String status, String? streamUrl) {
    for (final c in cameras) {
      if (c.cameraId == id) {
        // Immutable - replace with new instance logic handled at list level
        break;
      }
    }
    notify();
  }

  void setGimbal(double pan, double tilt) {
    gimbal.update(pan, tilt);
    notify();
  }

  void setModules(List<dynamic> list) {
    modules.clear();
    for (final m in list) {
      if (m is Map) modules.add(Module.fromJson(m.cast<String, dynamic>()));
    }
    notify();
  }

  void setServices(List<dynamic> list) {
    services.clear();
    for (final s in list) {
      if (s is Map) services.add(ServiceInfo.fromJson(s.cast<String, dynamic>()));
    }
    notify();
  }

  void setDances(List<dynamic> list) {
    dances.clear();
    for (final d in list) {
      if (d is Map) dances.add(DanceInfo.fromJson(d.cast<String, dynamic>()));
    }
    notify();
  }

  void setDanceStatus(String s, {String? danceId, double? progress, bool? loop}) {
    danceStatus = s;
    if (danceId != null) danceCurrentId = danceId;
    if (progress != null) danceProgress = progress;
    if (loop != null) danceLoop = loop;
    notify();
  }

  void updateMusicFromJson(Map<String, dynamic> data) {
    music.updateFromJson(data);
    notify();
  }

  void setMusicSongs(List<dynamic> list) {
    musicSongs.clear();
    for (final t in list) {
      if (t is Map) musicSongs.add(MusicTrack.fromJson(t.cast<String, dynamic>()));
    }
    notify();
  }

  void setSoftwareInstalled(List<dynamic> list) {
    softwareInstalled.clear();
    for (final s in list) {
      if (s is Map) {
        softwareInstalled.add(Software.fromJson(s.cast<String, dynamic>()));
      }
    }
    notify();
  }

  void setSoftwareAvailable(List<dynamic> list) {
    softwareAvailable.clear();
    for (final s in list) {
      if (s is Map) {
        softwareAvailable.add(Software.fromJson(s.cast<String, dynamic>()));
      }
    }
    notify();
  }

  void appendGalleryItems(List<dynamic> items) {
    for (final i in items) {
      if (i is Map) galleryItems.add(GalleryItem.fromJson(i.cast<String, dynamic>()));
    }
    notify();
  }

  void setGalleryItems(List<dynamic> items) {
    galleryItems.clear();
    appendGalleryItems(items);
  }

  void setGalleryPageInfo(int page, int total, bool hasMore) {
    galleryPage = page;
    galleryTotal = total;
    galleryHasMore = hasMore;
    notify();
  }

  void setGalleryStorageFromJson(Map<String, dynamic>? data) {
    if (data != null) {
      galleryStorage = GalleryStorage.fromJson(data);
    }
    notify();
  }

  void setWiFiResult(Map<String, dynamic> data) {
    wifiNetworks.clear();
    if (data['networks'] is List) {
      for (final n in data['networks']) {
        wifiNetworks.add(n as Map<String, dynamic>);
      }
    }
    wifiCurrentSSID = data['current_ssid'] as String? ?? '';
    notify();
  }

  void setPowerPolicy(Map<String, dynamic> data) {
    powerMode = data['mode'] as String? ?? powerMode;
    powerThreshold = data['threshold'] as int? ?? powerThreshold;
    notify();
  }

  void setRemoteFeatures(List<dynamic>? features) {
    remoteFeatures.clear();
    if (features != null) {
      for (final f in features) {
        remoteFeatures.add(f.toString());
      }
    }
    notify();
  }

  /// 更新日志 — 匹配 web-debug handleLogsMessage
  ///
  /// 兼容两种真机格式：
  /// 1. 批量响应: {logs: [{line_no, timestamp, level, source, message}], next_since, has_more, mode}
  /// 2. 流式推送: {line_no, timestamp, level, source, message}（单条，data 顶层即日志）
  /// [mode]: tail(首次加载) / since(增量) / before(历史) / push(流式)
  void updateLogs(Map<String, dynamic> data, {required String mode}) {
    // 单条日志对象（流式推送）：data 顶层就是日志字段
    final rawLogs = data['logs'] is List
        ? (data['logs'] as List)
        : (data['line_no'] != null ? [data] : const []);

    final items = rawLogs.map((e) {
      final m = e is Map ? Map<String, dynamic>.from(e) : const <String, dynamic>{};
      final rawLevel = (m['level'] as String? ?? 'info').toLowerCase();
      final level = rawLevel == 'warning'
          ? 'warn'
          : ['debug', 'info', 'warn', 'error'].contains(rawLevel)
              ? rawLevel
              : 'info';
      final lineNo = m['line_no'] is num ? (m['line_no'] as num).toInt() : 0;
      return LogEntry(
        id: m['id'] as String? ?? 'ln-$lineNo',
        lineNo: lineNo,
        time: m['timestamp'] as String? ?? m['time'] as String? ?? '',
        level: level,
        source: m['source'] as String? ?? 'remote',
        message: m['message'] as String? ?? '',
      );
    }).toList();

    // 游标：服务端返回 next_since（对齐 web-debug）
    final cursor = data['next_since'] is num ? (data['next_since'] as num).toInt() : 0;
    final hasMore = data['has_more'] as bool? ?? false;

    switch (mode) {
      case 'tail':
        logs
          ..clear()
          ..addAll(items);
        break;
      case 'since':
      case 'push':
        // 去重后追加（流式推送逐条追加）
        final known = logs.map((l) => l.lineNo).toSet();
        logs.addAll(items.where((l) => !known.contains(l.lineNo)));
        break;
      case 'before':
        logs.insertAll(0, items);
        break;
    }
    if (cursor > 0) logCursor = cursor;
    logHasMore = hasMore;
    notify();
  }

  // ---- 消息 ----
  /// 新增一条机器人消息（最新在上，对齐手机消息列表习惯；web-debug 为追加）
  void addMessage(RobotMessage msg) {
    messages.insert(0, msg);
    notify();
  }

  /// 标记消息已读/未读
  void markMessageRead(String id, bool read) {
    final i = messages.indexWhere((m) => m.id == id);
    if (i >= 0 && messages[i].read != read) {
      messages[i] = messages[i].copyWith(read: read);
      notify();
    }
  }
}

final robotDataProvider = StateNotifierProvider<RobotDataStore, int>((ref) => RobotDataStore());
