import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';
import '../../shared/models/connection_state.dart';
import '../../shared/models/robot_device.dart';
import '../../shared/models/robot_status.dart';
import 'mdns_discovery.dart';
import 'websocket_client.dart';
import 'bind_service.dart';
import 'robot_data_store.dart';

/// 连接状态枚举 — 匹配 web-debug ConnectionStatus
enum ConnState { disconnected, connecting, connected, binding, error }

extension ConnStateExt on ConnState {
  String get name => toString().split('.').last;
}

/// 连接管理器 — 完整匹配 web-debug useWebSocket.ts
class ConnectionManager extends StateNotifier<ConnState> {
  final WsClient _ws = WsClient();
  final MdnsDiscovery _mdns = MdnsDiscovery();
  Timer? _statusTimer;
  final BindService _bind = BindService.instance;
  final RobotDataStore _data = RobotDataStore();

  RobotDevice? currentDevice;
  RobotStatus? robotStatus;
  Map<String, dynamic>? robotInfo;
  String? robotId;
  List<String> remoteFeatures = [];
  bool authRequired = false;
  bool isBound = false;
  String pendingShareCode = '';
  String accountToken = '';

  ConnectionManager() : super(ConnState.disconnected) {
    _bind.init();
    _ws
      ..onMessage = _handleMessage
      ..onDisconnected = () {
        state = ConnState.disconnected;
        _statusTimer?.cancel();
      }
      ..onError = (e) { state = ConnState.error; }
      ..onStateChanged = (wsState) {
        switch (wsState) {
          case 'connected':
            // 不立即设为 connected，等待服务端 connected 消息
            break;
          case 'connecting':
          case 'reconnecting':
            state = ConnState.connecting;
            break;
          case 'disconnected':
            state = ConnState.disconnected;
            _statusTimer?.cancel();
            break;
          case 'error':
            state = ConnState.error;
            break;
        }
      };
  }

  Future<List<RobotDevice>> discoverDevices() => _mdns.discover(timeout: AppConstants.mdnsDiscoveryTimeout);

  /// 连接到设备
  Future<void> connectToDevice(RobotDevice device) async {
    state = ConnState.connecting;
    currentDevice = device;
    authRequired = false;

    final cred = _bind.getCredentialFor(device.ip, device.port);
    final params = <String, String>{};
    if (cred != null) {
      params['clientId'] = cred.clientId;
      params['clientToken'] = cred.clientToken;
    } else {
      params['clientId'] = _bind.clientId;
    }
    if (pendingShareCode.isNotEmpty) {
      params['shareCode'] = pendingShareCode;
      pendingShareCode = '';
    }
    if (accountToken.isNotEmpty) {
      params['accountToken'] = accountToken;
    }

    await _ws.connect(device.ip, port: device.port, extraParams: params);
  }

  // ===================== 发送方法 (匹配 web-debug) =====================

  /// 通用发送 — { type: "...", data: {...} }
  void send(String type, [Map<String, dynamic>? data]) {
    if (data != null) _ws.sendCommand(type, data);
    else _ws.sendRaw({'type': type});
  }

  void sendRaw(Map<String, dynamic> msg) => _ws.sendRaw(msg);

  // ---- 运动控制 ----
  void sendMotion(double vx, double vy, double vz) =>
      send('motion', {'v_x': vx, 'v_y': vy, 'v_z': vz});
  void sendMotionStop() => send('motion_stop');
  void sendEmergencyStop() => send('emergency_stop');
  void sendEmergencyRelease() => send('emergency_release');

  // ---- 系统操作 (匹配 web-debug sendSystemAction) ----
  void sendSystemAction(String action) =>
      send('system', {'action': action});

  // ---- 云台控制 (匹配 web-debug gimbal action) ----
  void sendGimbalMoveBegin(double panSpeed, double tiltSpeed) =>
      send('gimbal', {'action': 'move_begin', 'pan_speed': panSpeed, 'tilt_speed': tiltSpeed});
  void sendGimbalMoveUpdate(double panSpeed, double tiltSpeed) =>
      send('gimbal', {'action': 'move_update', 'pan_speed': panSpeed, 'tilt_speed': tiltSpeed});
  void sendGimbalMoveEnd() =>
      send('gimbal', {'action': 'move_end'});
  void sendGimbalCenter() =>
      send('gimbal', {'action': 'center'});

  // ---- 设备控制 (匹配 web-debug device_control) ----
  void sendDeviceControl(String action, bool enabled) =>
      send('device_control', {'action': action, 'enabled': enabled});

  // ---- 摄像头 ----
  void sendCamera(String action, int cameraId) =>
      send('camera', {'action': action, 'camera_id': cameraId});
  void sendCameraCapture([String quality = 'high']) =>
      send('camera_capture', {'quality': quality});
  void sendCameraRecordStart(int cameraId, [String quality = 'high']) =>
      send('camera_record_start', {'camera_id': cameraId, 'quality': quality, 'resolution': '1080p', 'segment_duration_s': 60});
  void sendCameraRecordStop() =>
      send('camera_record_stop');
  void sendStreamQuality(String mode) =>
      send('camera_stream_quality', {'mode': mode});

  // ---- 音乐 ----
  void sendMusicPlay([String? songId]) =>
      send('music_play', songId != null ? {'songId': songId} : {});
  void sendMusicPause() => send('music_pause');
  void sendMusicNext() => send('music_next');
  void sendMusicPrev() => send('music_prev');
  void sendMusicVolume(int volume) =>
      send('music_volume', {'volume': volume});

  // ---- 舞蹈 ----
  void sendDancePlay(String danceId) =>
      send('dance_play', {'danceId': danceId});
  void sendDanceStop() => send('dance_stop');

  // ---- 查询类 ----
  void sendGetStatus() => send('get_status');
  void sendGetModuleList() => send('get_module_list');
  void sendGetServiceStatus() => send('get_service_status');
  void sendGetDanceList() => send('dance_list');
  void sendGetMusicList() => send('music_list');
  void sendGetSoftwareList() => send('software_list');
  void sendGetSoftwareAvailable() => send('software_available');
  void sendSoftwareInstall(String id) =>
      send('software_install', {'id': id});
  void sendSoftwareUninstall(String id) =>
      send('software_uninstall', {'id': id});
  void sendSoftwareUpgrade(String id) =>
      send('software_upgrade', {'id': id});

  // ---- WiFi ----
  void sendWifiScan() => send('wifi_scan');

  // ---- 省电策略 ----
  void sendGetPowerPolicy() => send('get_power_policy');
  void sendSetPowerPolicy(Map<String, dynamic> policy) =>
      send('set_power_policy', policy);

  // ---- 配置 ----
  void sendConfigGet(String key) =>
      send('config_get', {'key': key});
  void sendConfigSet(String key, dynamic value) =>
      send('config_set', {'key': key, 'value': value});

  // ---- 绑定管理 ----
  void sendBindList() => send('bind_list');
  void sendBindRemove(String clientId) =>
      send('bind_remove', {'clientId': clientId});
  void sendBindRemoveAll() => send('bind_remove_all');
  void sendBindShareCreate() => send('bind_share_create');

  // ---- WebRTC 信令 ----
  void sendWebRtcOffer(String sdp) =>
      send('webrtc_offer', {'sdp': sdp});
  void sendWebRtcIceCandidate(dynamic candidate, String? sdpMid, int? sdpMLineIndex) =>
      send('webrtc_ice_candidate', {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      });

  // ---- 订阅 ----
  void sendSubscribe(List<String> events) =>
      send('subscribe', {'events': events});

  // ---- exec ----
  void sendExec(String command) =>
      send('exec', {'command': command});

  // ===================== 内部方法 =====================

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      Duration(seconds: AppConstants.statusUpdateIntervalSec),
      (_) => sendGetStatus(),
    );
  }

  void disconnect() {
    _ws.disconnect();
    _mdns.stop();
    _statusTimer?.cancel();
    currentDevice = null;
    robotStatus = null;
    robotInfo = null;
    state = ConnState.disconnected;
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String? ?? '';
    final d = msg['data'] as Map<String, dynamic>? ?? msg['payload'] as Map<String, dynamic>? ?? msg;

    switch (type) {
      // ---- 连接与认证 ----
      case 'connected':
        robotId = d['robot_id'] as String?;
        final features = d['features'] as List?;
        if (features != null) {
          remoteFeatures = features.map((e) => e.toString()).toList();
          _data.setRemoteFeatures(features);
        }
        // 检查是否已有 clientToken (分享码自动绑定成功)
        final clientToken = d['clientToken'] as String?;
        if (clientToken != null && clientToken.isNotEmpty && currentDevice != null) {
          _bind.handleBindSuccess(d, currentDevice!.ip, currentDevice!.port);
        }
        isBound = true;
        authRequired = false;
        state = ConnState.connected;
        _startStatusPolling();
        // 连接后请求初始数据
        sendGetModuleList();
        sendGetServiceStatus();
        break;

      case 'auth_required':
        authRequired = true;
        isBound = false;
        state = ConnState.binding;
        _bind.handleAuthRequired(d);
        break;

      case 'force_disconnect':
        authRequired = true;
        isBound = false;
        state = ConnState.disconnected;
        _bind.handleAuthRequired({});
        break;

      // ---- 绑定消息 ----
      case 'bind_request_ack':
        _bind.handleBindRequestAck(d);
        break;
      case 'bind_success':
        if (currentDevice != null) {
          _bind.handleBindSuccess(d, currentDevice!.ip, currentDevice!.port);
        }
        isBound = true;
        authRequired = false;
        state = ConnState.connected;
        _startStatusPolling();
        break;
      case 'bind_failed':
        _bind.handleBindFailed(d);
        break;
      case 'bind_share_created':
        _bind.handleShareCreated(d);
        break;
      case 'bind_list_ack':
      case 'bind_list_update':
        // TODO: 更新绑定列表 UI
        debugPrint('[CM] bind_list: $d');
        break;
      case 'bind_replay_ack':
        debugPrint('[CM] bind_replay_ack: ${d['method']}');
        break;
      case 'bind_cancel_ack':
        debugPrint('[CM] bind_cancel_ack');
        break;

      // ---- 状态 ----
      case 'status':
        _data.updateFromStatus(d);
        robotStatus = RobotStatus.fromJson(d);
        break;
      case 'pong':
        break;
      case 'robot_info':
        robotInfo = d;
        final riFeatures = d['features'] as List?;
        if (riFeatures != null) {
          remoteFeatures = riFeatures.map((e) => e.toString()).toList();
          _data.setRemoteFeatures(riFeatures);
        }
        if (d['robot_id'] != null) {
          robotId = d['robot_id'] as String;
        }
        break;
      case 'features_update':
        final fuFeatures = d['features'] as List?;
        if (fuFeatures != null) {
          remoteFeatures = fuFeatures.map((e) => e.toString()).toList();
          _data.setRemoteFeatures(fuFeatures);
        }
        break;

      // ---- 模块与服务 ----
      case 'module_list':
        _data.setModules(d['modules'] as List? ?? []);
        break;
      case 'service_status':
        _data.setServices(d['services'] as List? ?? []);
        break;

      // ---- 舞蹈 ----
      case 'dance_list':
        _data.setDances(d['dances'] as List? ?? []);
        break;
      case 'dance_status':
        _data.setDanceStatus(
          d['status'] as String? ?? 'stopped',
          danceId: d['id'] as String?,
          progress: (d['progress'] as num?)?.toDouble(),
          loop: d['loop'] as bool?,
        );
        break;

      // ---- 音乐 ----
      case 'music_status':
      case 'music_action':
      case 'music_stream':
      case 'music_playlist':
        _data.updateMusicFromJson(d);
        break;
      case 'music_list':
        _data.setMusicSongs(d['songs'] as List? ?? []);
        break;
      case 'music_volume':
        _data.music.volume = d['volume'] as int? ?? _data.music.volume;
        _data.notify();
        break;

      // ---- 摄像头 ----
      case 'camera_status':
        _data.setCamerasFromList(d['cameras'] ?? d);
        break;
      case 'camera_capture_result':
        debugPrint('[CM] capture: ${d['file_name']}');
        break;
      case 'camera_record_result':
        _data.isRecording = d['action'] == 'start';
        _data.notify();
        break;
      case 'camera_record_status':
        _data.isRecording = d['recording'] as bool? ?? _data.isRecording;
        _data.notify();
        break;
      case 'camera_media_list_result':
        _data.setGalleryItems(d['items'] as List? ?? []);
        _data.setGalleryStorageFromJson(d['storage'] as Map<String, dynamic>?);
        _data.setGalleryPageInfo(
          d['page'] as int? ?? 1,
          d['total'] as int? ?? 0,
          d['has_more'] as bool? ?? false,
        );
        break;
      case 'camera_stream_quality_ack':
      case 'camera_stream_quality_changed':
        _data.streamQuality = d['mode'] as String? ?? _data.streamQuality;
        _data.notify();
        break;

      // ---- 云台 ----
      case 'gimbal_status':
        _data.setGimbal(
          (d['pan'] as num?)?.toDouble() ?? 90,
          (d['tilt'] as num?)?.toDouble() ?? 90,
        );
        break;
      case 'gimbal_limit':
        debugPrint('[CM] gimbal_limit: ${d['axis']}');
        break;

      // ---- 软件 ----
      case 'software_list':
        _data.setSoftwareInstalled(d['software'] as List? ?? []);
        break;
      case 'software_available':
        _data.setSoftwareAvailable(d['software'] as List? ?? []);
        break;
      case 'software_progress':
        debugPrint('[CM] sw_progress: ${d['progress']}');
        break;
      case 'software_install_ack':
      case 'software_uninstall_ack':
      case 'software_upgrade_ack':
        debugPrint('[CM] sw_ack: $type');
        break;
      case 'software_updates_available':
        debugPrint('[CM] sw_updates: $d');
        break;

      // ---- WiFi ----
      case 'wifi_scan_result':
        _data.setWiFiResult(d);
        break;

      // ---- 省电策略 ----
      case 'power_policy_status':
      case 'power_policy_config':
        _data.setPowerPolicy(d);
        break;

      // ---- 配置 ----
      case 'config_get_ack':
      case 'config_set_ack':
        debugPrint('[CM] config_ack: $type → $d');
        break;

      // ---- 运动确认 ----
      case 'motion_ack':
        debugPrint('[CM] motion_ack: v=${d['v_x']} ${d['v_y']} ${d['v_z']}');
        break;
      case 'emergency_stop_ack':
        debugPrint('[CM] emergency_stop_ack');
        break;
      case 'device_control_ack':
        debugPrint('[CM] device_control_ack: ${d['action']}=${d['enabled']}');
        break;

      // ---- WebRTC 信令 ----
      case 'webrtc_answer':
        debugPrint('[CM] webrtc_answer received');
        // 由 WebRTCService 处理
        break;
      case 'webrtc_ice_candidate':
        debugPrint('[CM] webrtc_ice_candidate received');
        break;

      // ---- exec ----
      case 'exec_result':
        debugPrint('[CM] exec_result: ok');
        break;

      // ---- 错误 ----
      case 'error':
        debugPrint('[CM] server_error: ${d['message']}');
        break;

      default:
        AppLogger.debug('[CM] 未处理消息: $type');
    }
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// 兼容旧代码 — 连接状态
AppConnectionState connStateToAppState(ConnState s) {
  switch (s) {
    case ConnState.disconnected: return AppConnectionState.disconnected;
    case ConnState.connecting: return AppConnectionState.connecting;
    case ConnState.connected: return AppConnectionState.connected;
    case ConnState.binding: return AppConnectionState.connecting;
    case ConnState.error: return AppConnectionState.error;
  }
}

final connectionManagerProvider = StateNotifierProvider<ConnectionManager, ConnState>((ref) => ConnectionManager());
