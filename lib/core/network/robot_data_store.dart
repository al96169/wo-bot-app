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
      if (s is Map) softwareInstalled.add(Software.fromJson(s.cast<String, dynamic>()));
    }
    notify();
  }

  void setSoftwareAvailable(List<dynamic> list) {
    softwareAvailable.clear();
    for (final s in list) {
      if (s is Map) softwareAvailable.add(Software.fromJson(s.cast<String, dynamic>()));
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
}

final robotDataProvider = StateNotifierProvider<RobotDataStore, int>((ref) => RobotDataStore());
