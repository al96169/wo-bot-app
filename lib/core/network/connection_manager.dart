import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../utils/app_toast.dart';
import '../utils/logger.dart';
import '../../shared/models/connection_state.dart';
import '../../shared/models/robot_data.dart';
import '../../shared/models/robot_device.dart';
import '../../shared/models/robot_status.dart';
import 'mdns_discovery.dart';
import 'websocket_client.dart';
import 'bind_service.dart';
import 'account_service.dart';
import 'signal_client.dart';
import 'robot_data_store.dart';
import 'webrtc_service.dart';

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
  late final RobotDataStore _data;

  /// WebRTC 服务（视频 + DataChannel 业务通道）— 对齐 web-debug useWebRTC
  final WebRtcService webrtc = WebRtcService.instance;

  /// 云端信令客户端（批次 6：跨网络远程控制，wss://signal 服务器）
  SignalClient? signal;

  RobotDevice? currentDevice;
  RobotStatus? robotStatus;
  Map<String, dynamic>? robotInfo;
  String? robotId;
  List<String> remoteFeatures = [];
  bool authRequired = false;
  bool isBound = false;
  String pendingShareCode = '';
  String accountToken = '';

  /// 分块下载状态（对齐 web-debug ChunkedDownload）：file_name → 组装缓冲
  final Map<String, _ChunkedDownload> _chunkedDownloads = {};

  /// [data]: 外部注入的 RobotDataStore（与 UI 共享同一实例）。
  /// 关键：若不注入，ConnectionManager 自建实例，UI 通过 provider 读的将是另一实例，
  /// 导致 status/logs 等数据永远不同步（web-debug 用单一 store 共享）。
  ConnectionManager({RobotDataStore? data}) : super(ConnState.disconnected) {
    _data = data ?? RobotDataStore();
    _bind.init();
    // WebRTC DataChannel 消息与 WebSocket 消息同格式 {type, data}，统一分发
    webrtc.onDataChannelMessage = (msg) {
      debugPrint('[CM] DC 消息: ${msg['type']}');
      _handleMessage(msg);
    };
    _ws
      ..onMessage = _handleMessage
      ..onDisconnected = () {
        state = ConnState.disconnected;
        _statusTimer?.cancel();
      }
      ..onError = (e) {
        state = ConnState.error;
      }
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

  Future<List<RobotDevice>> discoverDevices() => _mdns.discover();

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
    if (data != null) {
      _ws.sendCommand(type, data);
    } else {
      _ws.sendRaw({'type': type});
    }
  }

  void sendRaw(Map<String, dynamic> msg) => _ws.sendRaw(msg);

  // ---- 运动控制 ----
  /// 发送运动指令 — DataChannel 就绪时优先走 P2P（对齐 web-debug sendViaDataChannel），WS 兜底
  void sendMotion(double vx, double vy, double vz) {
    if (webrtc.isDataChannelReady) {
      webrtc.sendViaDataChannel('motion', {'v_x': vx, 'v_y': vy, 'v_z': vz});
    } else {
      send('motion', {'v_x': vx, 'v_y': vy, 'v_z': vz});
    }
  }

  void sendMotionStop() {
    if (webrtc.isDataChannelReady) {
      webrtc.sendViaDataChannel('motion_stop');
    } else {
      send('motion_stop');
    }
  }

  void sendEmergencyStop() => send('emergency_stop');
  void sendEmergencyRelease() => send('emergency_release');

  // ---- 系统操作 (匹配 web-debug sendSystemAction) ----
  void sendSystemAction(String action) => send('system', {'action': action});

  // ---- 云台控制 (匹配 web-debug gimbal action) — DataChannel 优先 ----
  void sendGimbalMoveBegin(double panSpeed, double tiltSpeed) => _sendHighFreq(
    'gimbal',
    {'action': 'move_begin', 'pan_speed': panSpeed, 'tilt_speed': tiltSpeed},
  );
  void sendGimbalMoveUpdate(double panSpeed, double tiltSpeed) => _sendHighFreq(
    'gimbal',
    {'action': 'move_update', 'pan_speed': panSpeed, 'tilt_speed': tiltSpeed},
  );
  /// 云台停止：WS + DC 双通道都发 move_end。
  /// 摇杆过程可能恰逢 DC/WS 切换，若 begin/update 走 A 通道、end 走 B 通道，
  /// 迟到的 begin/update 会在 end 之后到达并重新启动移动循环 → 云台停不下来。
  /// 双通道各发一次 end，保证无论 begin/update 走哪条通道，同通道的 end 都在其后。
  void sendGimbalMoveEnd() {
    send('gimbal', {'action': 'move_end'}); // WS 兜底（有序）
    _sendHighFreq('gimbal', {'action': 'move_end'}); // DC 优先（有序）
  }
  void sendGimbalCenter() => _sendHighFreq('gimbal', {'action': 'center'});

  /// 高频命令：DataChannel 就绪时优先走 P2P（motion/gimbal 对齐 web-debug），WS 兜底
  void _sendHighFreq(String type, [Map<String, dynamic>? data]) {
    if (webrtc.isDataChannelReady) {
      webrtc.sendViaDataChannel(type, data);
    } else {
      send(type, data);
    }
  }

  // ---- 设备控制 (匹配 web-debug device_control) ----
  void sendDeviceControl(String action, bool enabled) =>
      send('device_control', {'action': action, 'enabled': enabled});

  // ---- 摄像头 ----
  void sendCamera(String action, int cameraId) {
    debugPrint('[CM] camera → action=$action camera_id=$cameraId');
    send('camera', {'action': action, 'camera_id': cameraId});
  }
  void sendCameraCapture([String quality = 'high']) =>
      send('camera_capture', {'quality': quality});
  void sendCameraRecordStart(int cameraId, [String quality = 'high']) =>
      send('camera_record_start', {
        'camera_id': cameraId,
        'quality': quality,
        'resolution': '1080p',
        'segment_duration_s': 60,
      });
  void sendCameraRecordStop() => send('camera_record_stop');
  void sendStreamQuality(String mode) =>
      send('camera_stream_quality', {'mode': mode});

  // ---- 音乐 ----
  void sendMusicPlay([String? filename]) =>
      send('music_play', filename != null ? {'filename': filename} : {});
  void sendMusicPause() => send('music_pause');
  void sendMusicNext() => send('music_next');
  void sendMusicPrev() => send('music_previous');
  void sendMusicVolume(int volume) => send('music_volume', {'volume': volume});

  // ---- 舞蹈 (对齐 web-debug: {type:"dance", data:{command}}) ----
  void sendDanceCommand(String command, [Map<String, dynamic>? data]) =>
      send('dance', {'command': command, ...?data});
  void sendDancePlay(String danceId) =>
      send('dance', {'command': 'play', 'dance_id': danceId});
  void sendDanceStop() => send('dance', {'command': 'stop'});
  void sendDancePause() => send('dance', {'command': 'pause'});

  // ---- 查询类 ----
  void sendGetStatus() => send('get_status');
  // 请求 type 与响应 type 相同（对齐 web-debug：真机只响应 module_list / service_status）
  void sendGetModuleList() => send('module_list');
  void sendGetServiceStatus() => send('service_status');

  /// 生成消息 ID — 对齐 web-debug (Date.now().toString(36) + 随机)
  static String _genMessageId() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      DateTime.now().microsecond.toRadixString(36);
  // 服务控制 (匹配 web-debug sendServiceControl)
  void sendServiceControl(String serviceId, String action) =>
      send('service_control', {'service_id': serviceId, 'action': action});
  void sendGetDanceList() => send('dance', {'command': 'list'});
  void sendGetMusicList() => send('music_list');
  void sendGetSoftwareList() => send('software_list');
  void sendGetSoftwareAvailable() => send('software_available');
  void sendSoftwareInstall(String package) =>
      send('software_install', {'package': package});
  void sendSoftwareUninstall(String package) =>
      send('software_uninstall', {'package': package});
  void sendSoftwareUpgrade(String package) =>
      send('software_upgrade', {'package': package});

  // ---- WiFi (匹配 web-debug sendWifiScan/sendWifiConnect) ----
  void sendWifiScan() => send('wifi_scan');
  void sendWifiConnect(String ssid, String password) =>
      send('wifi_connect', {'ssid': ssid, 'password': password});
  void sendWifiDisconnect(String device) =>
      send('wifi_disconnect', {'device': device});

  // ---- 图库 (对齐 web-debug GalleryView) ----
  void sendGetGalleryList({String type = 'all', int page = 1, int pageSize = 20}) =>
      send('camera_media_list', {
        'type': type,
        'page': page,
        'page_size': pageSize,
      });
  void sendGalleryDelete(List<String> fileNames) =>
      send('camera_media_delete', {'file_names': fileNames});
  /// 请求下载媒体文件 — 走 WebSocket（可靠到达机器人端）；
  /// 机器人端收到后经已建立的 DataChannel 分块回传 start/chunk/end（远程 WebRTC 场景同样适用）。
  /// 不再走 DC 发送：App 客户端 DC 消息在机器人端 server-DC 覆盖后可能丢失（subscribe 能到、后续消息丢）。
  void sendGalleryDownload(String fileName) =>
      send('camera_media_download', {'file_name': fileName});

  // ---- 音乐补充 (对齐 web-debug sendMusicCommand) ----
  void sendMusicResume() => send('music_resume');
  void sendMusicStop() => send('music_stop');
  void sendMusicSeek(double position) =>
      send('music_seek', {'position': position});
  void sendMusicPlaylistAdd(String filename) =>
      send('music_playlist_add', {'filename': filename});
  void sendMusicPlaylistRemove(int index) =>
      send('music_playlist_remove', {'index': index});
  void sendMusicPlaylistClear() => send('music_playlist_clear');
  void sendGetMusicStatus() => send('music_status');

  // ---- 省电策略 ----
  void sendGetPowerPolicy() => send('get_power_policy');
  void sendSetPowerPolicy(Map<String, dynamic> policy) =>
      send('set_power_policy', policy);

  // ---- 配置 ----
  // 对齐 web-debug：config_get 无 key 时取全量配置
  void sendConfigGet([String? key]) =>
      send('config_get', key != null ? {'key': key} : {});
  /// 提交全量配置（对齐 web-debug config_set {config: {...}}，机器人端深度合并）
  void sendConfigSet(Map<String, dynamic> config) =>
      send('config_set', {'config': config});

  // ---- 绑定管理 ----
  void sendBindList() => send('bind_list');
  void sendBindRemove(String clientId) =>
      send('bind_remove', {'clientId': clientId});
  void sendBindRemoveAll() => send('bind_remove_all');
  void sendBindShareCreate() => send('bind_share_create');
  /// 使用分享码绑定（对齐机器人端 bind_share_use: {shareCode, clientId, clientName}）
  void sendBindShareUse(String code, {String? clientId, String? clientName}) =>
      send('bind_share_use', {
        'shareCode': code,
        if (clientId != null) 'clientId': clientId,
        if (clientName != null) 'clientName': clientName,
      });
  void sendBindPasswordConfig() => send('bind_password_config');
  /// 更新密码绑定：修改密码或开关（对齐机器人端 bind_password_update: {password, enabled}）
  void sendBindPasswordUpdate({String? password, bool? enabled}) =>
      send('bind_password_update', {
        if (password != null) 'password': password,
        if (enabled != null) 'enabled': enabled,
      });
  /// 绑定证明（批次 6：把本地绑定设备挂到云端帐号）
  void sendBindingProofRequest(String accountId, String clientId) =>
      send('binding_proof_request', {
        'accountId': accountId,
        'clientId': clientId,
      });

  // ---- WebRTC 信令 ----
  void sendWebRtcOffer(String sdp) => send('webrtc_offer', {'sdp': sdp});
  void sendWebRtcIceCandidate(
    dynamic candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) => send('webrtc_ice_candidate', {
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  });

  /// 建立 WebRTC 连接（视频 + DataChannel）— 对齐 web-debug establishConnection
  /// 真机 features 可能不含 'webrtc'（web-debug 实测可用），因此不以此作为硬性门槛，
  /// 总是尝试建立；不支持时 establishConnection 内部捕获失败，不影响 WS 控制。
  Future<void> startWebRtc() async {
    debugPrint('[CM] startWebRtc, features=$remoteFeatures');
    await webrtc.establishConnection(
      sendOffer: sendWebRtcOffer,
      sendIceCandidate: sendWebRtcIceCandidate,
    );
  }

  /// 云端远控连接（批次 6）— 对齐 web-debug connectViaSignal
  ///
  /// [robotId] 云端设备 ID；[signalUrl] 信令服务器地址（默认 wss://signal.wo-bot.com/ws）。
  /// 依赖 AccountService 已登录（JWT），业务消息经 DataChannel 统一走 _handleMessage。
  Future<bool> connectViaSignal(
    String robotId, {
    String signalUrl = 'wss://signal.wo-bot.com/ws',
  }) async {
    final account = AccountService.instance;
    final token = account.accessToken;
    if (token == null || token.isEmpty) {
      debugPrint('[CM] connectViaSignal: 未登录');
      return false;
    }

    // 预填 robotInfo（信令模式无 connected 消息）
    robotId = robotId;
    robotInfo = {
      'robot_id': robotId,
      'name': '',
      'model': '',
      'version': '',
      'features': <String>[],
    };
    isBound = true; // JWT 已验证归属，信令模式免本地绑定
    authRequired = false;
    state = ConnState.connecting;

    // 清理旧连接
    disconnect();
    await signal?.disconnect();
    signal = SignalClient(signalUrl: signalUrl, robotId: robotId);

    signal!
      ..onDataChannelMessage = (msg) {
        debugPrint('[CM] Signal DC 消息: ${msg['type']}');
        _handleMessage(msg);
      }
      ..onDataChannelReady = (ready) {
        if (ready) {
          state = ConnState.connected;
          _startStatusPolling();
        }
      }
      ..onVideoStream = webrtc.onVideoStream
      ..onError = (msg) {
        debugPrint('[CM] Signal 错误: $msg');
        if (state == ConnState.connecting) {
          state = ConnState.error;
        }
      }
      ..onDisconnected = () {
        if (state == ConnState.connected) {
          state = ConnState.disconnected;
        }
      };

    await signal!.connect(token);
    // 等待连接（最多 10s）
    final ok = await _waitSignalConnected(const Duration(seconds: 10));
    return ok;
  }

  Future<bool> _waitSignalConnected(Duration timeout) async {
    final completer = Completer<bool>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    // 轮询 isConnected（DC open 后置 true）
    late final Timer poll;
    poll = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (signal?.isConnected == true && !completer.isCompleted) {
        completer.complete(true);
        poll.cancel();
      }
    });
    try {
      if (signal?.isConnected == true) return true;
      return await completer.future;
    } finally {
      timer.cancel();
      poll.cancel();
    }
  }

  /// 断开云端连接
  Future<void> disconnectSignal() async {
    await signal?.disconnect();
    signal = null;
    state = ConnState.disconnected;
  }

  /// 确保 DataChannel 就绪（图库下载需要 DC 分块传输；远程 WebRTC 场景无直连 HTTP）
  /// 若 DC 未就绪则启动 WebRTC 并等待 DC 打开，最多等待 [timeout]。
  /// 返回 true=DC 可用。
  Future<bool> ensureDataChannelForDownload({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (webrtc.isDataChannelReady) return true;
    // 已连接但 DC 未就绪（或从未建立）→ 启动 WebRTC
    if (state == ConnState.connected && !webrtc.isDataChannelReady) {
      try {
        await startWebRtc();
      } catch (e) {
        debugPrint('[CM] ensureDC 启动失败: $e');
      }
    }
    // 等待 DC 打开
    final completer = Completer<bool>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    void onReady(bool ready) {
      if (ready && !completer.isCompleted) {
        completer.complete(true);
      }
    }

    webrtc.onDataChannelReady = onReady;
    try {
      if (webrtc.isDataChannelReady) return true;
      return await completer.future;
    } finally {
      timer.cancel();
      // 仅当回调仍是我们的监听器时清理（避免覆盖遥控页已设置的监听）
      if (identical(webrtc.onDataChannelReady, onReady)) {
        webrtc.onDataChannelReady = null;
      }
    }
  }

  /// 发送二进制消息（语音对讲 voice_broadcast）— 对齐 web-debug sendBinary
  /// 帧格式: [4 字节 JSON 头长度 big-endian] + [JSON header {type,data}] + [二进制音频]
  /// [preferDataChannel]: true=电话模式优先 DataChannel（低延迟），false=WebSocket（无大小限制）
  void sendBinaryMessage(
    String type,
    Map<String, dynamic> data,
    List<int> bytes, {
    bool preferDataChannel = false,
  }) {
    final header = jsonEncode({'type': type, 'data': data});
    final headerBytes = utf8.encode(header);
    final total = Uint8List(4 + headerBytes.length + bytes.length);
    final bd = ByteData.sublistView(total);
    bd.setUint32(0, headerBytes.length); // 大端序，与后端 struct.unpack('>I') 一致
    total.setAll(4, headerBytes);
    total.setAll(4 + headerBytes.length, bytes);

    if (preferDataChannel && webrtc.isDataChannelReady) {
      webrtc.sendBinaryViaDataChannel(total);
    } else {
      _ws.sendBinary(total);
    }
  }

  // ---- 订阅 ----
  void sendSubscribe(List<String> events) =>
      send('subscribe', {'events': events});

  // ---- 日志 (匹配 web-debug requestLogs，字段与 web-debug 完全一致) ----
  void requestLogs({
    String mode = 'tail',
    int limit = 200,
    int? sinceLine,
    int? beforeLine,
    String? level,
  }) {
    final data = <String, dynamic>{
      'mode': mode,
      'since_line': sinceLine ?? 0,
      'before_line': beforeLine ?? 0,
      'limit': limit,
      'level': level ?? '',
    };
    send('logs', data);
  }

  // ---- exec ----
  void sendExec(String command) => send('exec', {'command': command});

  // ===================== 内部方法 =====================

  void _startStatusPolling() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(
      const Duration(seconds: AppConstants.statusUpdateIntervalSec),
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
    final d =
        msg['data'] as Map<String, dynamic>? ??
        msg['payload'] as Map<String, dynamic>? ??
        msg;

    switch (type) {
      // ---- 连接与认证 ----
      case 'connected':
        robotId = d['robot_id'] as String?;
        final features = d['features'] as List?;
        if (features != null) {
          remoteFeatures = features.cast<String>();
          _data.setRemoteFeatures(features);
        }
        // 检查是否已有 clientToken (分享码自动绑定成功)
        final clientToken = d['clientToken'] as String?;
        if (clientToken != null &&
            clientToken.isNotEmpty &&
            currentDevice != null) {
          _bind.handleBindSuccess(d, currentDevice!.ip, currentDevice!.port);
        }
        isBound = true;
        authRequired = false;
        state = ConnState.connected;
        _startStatusPolling();
        // 连接后请求初始数据（对齐 web-debug connected：subscribe + camera list + 模块/服务）
        send('subscribe', {
          'events': ['status'],
        });
        send('camera', {'action': 'list'});
        sendGetModuleList();
        sendGetServiceStatus();
        // robotInfo 补充 name/model/version（对齐 web-debug setRobotInfo）
        if (d['name'] != null || d['model'] != null || d['version'] != null) {
          robotInfo = {...?robotInfo, ...d};
        }
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
        _data.setBindings(d['bindings'] as List? ?? d['clients'] as List? ?? []);
        break;
      case 'binding_proof_response':
        // 绑定证明结果（批次 6：把本地绑定设备挂到云端帐号）
        // {success, payload: {...}, proof: "hex"} → POST /api/devices/bind {payload, proof}
        if (d['success'] == true &&
            d['payload'] is Map &&
            d['proof'] != null) {
          final payload = Map<String, dynamic>.from(d['payload'] as Map);
          final proof = d['proof'] as String;
          debugPrint('[CM] binding_proof 成功，提交云端绑定');
          // 异步提交（不阻塞消息处理）
          Future<void>(() async {
            final ok = await AccountService.instance.bindDevice(payload, proof);
            AppToast.show(
              ok ? '已绑定到云端账号' : '云端绑定失败',
              type: ok ? AppToastType.success : AppToastType.error,
            );
          });
        } else {
          debugPrint('[CM] binding_proof 失败: ${d['error']}');
          AppToast.show(
            '绑定证明失败: ${d['error'] ?? '未知错误'}',
            type: AppToastType.error,
          );
        }
        break;
      case 'bind_replay_ack':
        debugPrint('[CM] bind_replay_ack: ${d['method']}');
        break;
      case 'bind_cancel_ack':
        debugPrint('[CM] bind_cancel_ack');
        break;

      // ---- 状态 ----
      case 'status':
        // 先同步服务列表（对齐 web-debug），状态解析异常不阻断服务更新
        if (d['services'] is List) {
          _data.setServices(d['services'] as List);
        }
        // features 同步（对齐 web-debug status 处理）
        // 注意：JSON decode 后 features 为 List<dynamic>，必须显式 .cast<String>()，
        // 否则 .map(...).toList() 推断为 List<dynamic>，赋给 List<String> 字段时抛类型错误
        if (d['features'] is List) {
          remoteFeatures = (d['features'] as List).cast<String>();
          _data.setRemoteFeatures(d['features'] as List);
        }
        // power_policy 内嵌解析（对齐 web-debug DC 路径）
        if (d['power_policy'] is Map) {
          _data.setPowerPolicy(
            Map<String, dynamic>.from(d['power_policy'] as Map),
          );
        }
        try {
          _data.updateFromStatus(d);
          robotStatus = RobotStatus.fromJson(d);
        } catch (e) {
          debugPrint('[CM] status 解析异常(已隔离): $e');
        }
        break;
      case 'pong':
        break;
      case 'robot_info':
        robotInfo = d;
        final riFeatures = d['features'] as List?;
        if (riFeatures != null) {
          remoteFeatures = riFeatures.cast<String>();
          _data.setRemoteFeatures(riFeatures);
        }
        if (d['robot_id'] != null) {
          robotId = d['robot_id'] as String;
        }
        break;
      case 'features_update':
        final fuFeatures = d['features'] as List?;
        if (fuFeatures != null) {
          remoteFeatures = fuFeatures.cast<String>();
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
      case 'service_message':
        // 机器人服务管理器推送的通知（对齐 web-debug handleSignalingMessage）
        _data.addMessage(
          RobotMessage(
            id: d['id'] as String? ?? _genMessageId(),
            subject: d['subject'] as String? ?? '服务通知',
            time: DateTime.now(),
            summary: d['summary'] as String? ?? '',
            body: d['body'] as String? ?? '',
            source: d['source'] as String? ?? 'service_manager',
            severity: ['info', 'warning', 'error'].contains(d['severity'])
                ? d['severity'] as String
                : 'info',
          ),
        );
        break;

      // ---- 舞蹈 ----
      case 'dance_list':
        _data.setDances(d['dances'] as List? ?? []);
        break;
      case 'dance_status':
        _data.setDanceStatus(
          d['status'] as String? ?? 'stopped',
          danceId: d['dance_id'] as String? ?? d['id'] as String?,
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
        _data.music.volume =
            (d['volume'] as num?)?.toInt() ?? _data.music.volume;
        _data.notify();
        break;

      // ---- 摄像头 ----
      case 'camera_status':
        debugPrint('[CM] camera_status: $d');
        if (d['cameras'] is List) {
          _data.setCamerasFromList(d['cameras'] as List);
        } else if (d['id'] != null || d['camera_id'] != null) {
          // 单对象增量更新（对齐 web-debug：{id,status,stream_url}，按 id 合并不清空）
          _data.upsertCamera(d);
        }
        break;
      case 'camera_capture_result':
        // 对齐 web-debug：success/photos → 拍照结果反馈
        if (d['success'] == true) {
          final photos = d['photos'] is List ? (d['photos'] as List).length : 0;
          AppToast.show(
            photos > 0 ? '拍照成功，已保存 $photos 张照片' : '拍照成功',
            type: AppToastType.success,
          );
        } else {
          AppToast.show(
            '拍照失败: ${d['error'] ?? d['message'] ?? '未知错误'}',
            type: AppToastType.error,
          );
        }
        break;
      case 'camera_record_result':
        // 对齐 web-debug：data.is_recording / data.success
        _data.setCameraRecord(
          isRecording:
              d['is_recording'] as bool? ?? d['success'] as bool? ?? false,
          cameraId: (d['camera_id'] as num?)?.toString() ??
              d['camera_id'] as String?,
          fileSizeBytes: (d['size_bytes'] as num?)?.toInt(),
        );
        break;
      case 'camera_record_status':
        // 对齐 web-debug：data.is_recording + camera_id/elapsed_s/file_size_bytes
        _data.setCameraRecord(
          isRecording: d['is_recording'] as bool? ??
              d['recording'] as bool? ??
              _data.isRecording,
          cameraId: (d['camera_id'] as num?)?.toString() ??
              d['camera_id'] as String?,
          elapsedS: (d['elapsed_s'] as num?)?.toInt(),
          fileSizeBytes: (d['file_size_bytes'] as num?)?.toInt(),
        );
        break;
      case 'camera_media_list_result':
        // 对齐 web-debug：data.files（兼容旧 items）
        // 合并单次 notify，避免多次重建导致缩略图闪烁；翻页追加不清空
        final mPage = (d['page'] as num?)?.toInt() ?? 1;
        final mTotal = (d['total'] as num?)?.toInt() ?? 0;
        final mPageSize = _data.galleryPageSize;
        _data.updateGalleryResult(
          items: d['files'] as List? ?? d['items'] as List? ?? [],
          storage: d['storage'] as Map<String, dynamic>?,
          page: mPage,
          total: mTotal,
          // 对齐 web-debug：has_more = page*pageSize < total（真机可能不返回 has_more）
          hasMore: d['has_more'] as bool? ?? (mPage * mPageSize < mTotal),
          reset: mPage <= 1,
        );
        break;
      case 'camera_media_delete_result':
        // 对齐 web-debug：data.deleted（文件名数组）→ 从列表移除
        if (d['deleted'] is List || d['file_names'] is List) {
          final removed = (d['deleted'] as List? ?? d['file_names'] as List?)
              ?.map((e) => e.toString())
              .toList();
          if (removed != null && removed.isNotEmpty) {
            _data.galleryItems.removeWhere((g) => removed.contains(g.name));
            _data.notify();
            AppToast.show('已删除 ${removed.length} 个文件', type: AppToastType.success);
          }
        } else {
          AppToast.show(
            '删除失败: ${d['error'] ?? d['message'] ?? '未知错误'}',
            type: AppToastType.error,
          );
        }
        break;

      // ---- 图库分块下载（对齐 web-debug handleChunkedDownloadMessage） ----
      case 'camera_media_download_start': {
        final name = d['file_name'] as String? ?? '';
        if (name.isEmpty) break;
        _chunkedDownloads[name] = _ChunkedDownload(
          fileName: name,
          sizeBytes: (d['size_bytes'] as num?)?.toInt() ?? 0,
          totalChunks: (d['total_chunks'] as num?)?.toInt() ?? 0,
        );
        break;
      }
      case 'camera_media_download_chunk': {
        final name = d['file_name'] as String? ?? '';
        final dl = _chunkedDownloads[name];
        if (dl == null) break;
        final idx = (d['chunk_index'] as num?)?.toInt() ?? -1;
        final chunkB64 = d['data'] as String? ?? '';
        if (idx >= 0 && chunkB64.isNotEmpty) {
          dl.chunks[idx] = chunkB64;
        }
        break;
      }
      case 'camera_media_download_end': {
        final name = d['file_name'] as String? ?? '';
        final dl = _chunkedDownloads.remove(name);
        if (dl == null) break;
        // 按索引排序并组装 base64 → bytes
        final keys = dl.chunks.keys.toList()..sort();
        final fullB64 = keys.map((k) => dl.chunks[k]).join();
        try {
          final bytes = base64Decode(fullB64);
          _data.notifyGalleryDownload(
            GalleryDownloadResult(
              fileName: name,
              bytes: bytes,
              sizeBytes: dl.sizeBytes,
            ),
          );
        } catch (e) {
          debugPrint('[CM] 图库下载组装失败: $e');
          _data.notifyGalleryDownload(
            GalleryDownloadResult(fileName: name, bytes: const [], error: '组装失败: $e'),
          );
        }
        break;
      }
      case 'camera_media_download_data': {
        // WS 回退：单次 file_base64（小文件）
        final name = d['file_name'] as String? ?? '';
        if (d['error'] != null) {
          _data.notifyGalleryDownload(
            GalleryDownloadResult(
              fileName: name,
              bytes: const [],
              error: d['error'] as String?,
            ),
          );
          break;
        }
        final b64 = d['file_base64'] as String? ?? '';
        try {
          final bytes = base64Decode(b64);
          _data.notifyGalleryDownload(
            GalleryDownloadResult(
              fileName: name,
              bytes: bytes,
              sizeBytes: (d['size_bytes'] as num?)?.toInt() ?? bytes.length,
            ),
          );
        } catch (e) {
          _data.notifyGalleryDownload(
            GalleryDownloadResult(fileName: name, bytes: const [], error: '解析失败: $e'),
          );
        }
        break;
      }
      case 'camera_media_download_done':
        // 分块传输完成确认（已在 end 处理组装）
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
        _data.setSoftwareInstalled(
          d['packages'] as List? ?? d['software'] as List? ?? [],
        );
        break;
      case 'software_available':
        _data.setSoftwareAvailable(
          d['packages'] as List? ?? d['software'] as List? ?? [],
        );
        break;
      case 'software_progress':
        // 对齐 web-debug：更新进行中任务的进度/阶段/输出
        _data.updateSoftwareTask(
          d['package'] as String? ?? '',
          progress: (d['progress'] as num?)?.toDouble(),
          stage: d['stage'] as String?,
          output: d['output'] as String?,
        );
        break;
      case 'software_install_ack':
      case 'software_uninstall_ack':
      case 'software_upgrade_ack': {
        // 对齐 web-debug：失败状态集合 → success/failed + 版本变化
        const failStatuses = {
          'failed',
          'protected',
          'permission_denied',
          'not_in_whitelist',
          'error',
        };
        final action = type
            .replaceFirst('software_', '')
            .replaceFirst('_ack', '');
        final pkg = d['package'] as String? ?? '';
        final status = d['status'] as String? ?? 'failed';
        final ok = !failStatuses.contains(status);
        _data.updateSoftwareTask(
          pkg,
          action: action,
          status: ok ? 'success' : 'failed',
          toVersion: d['new_version'] as String?,
        );
        debugPrint('[CM] sw_ack: $type success=$ok');
        // already_latest 特殊提示（对齐 web-debug）
        if (status == 'already_latest') {
          AppToast.show('$pkg 已是最新版本');
        }
        // 操作完成后刷新列表（对齐 web-debug：成功后重发 software_list/available）
        sendGetSoftwareList();
        sendGetSoftwareAvailable();
        break;
      }
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
        _data.setRobotConfig(d);
        debugPrint('[CM] config_get_ack keys=${d.keys.length}');
        break;
      case 'config_set_ack':
        debugPrint('[CM] config_set_ack: success=${d['success']} changes=${d['changes']}');
        if (d['success'] == true) {
          // 重新拉取最新配置
          sendConfigGet();
        }
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
        webrtc.handleAnswer(d['sdp'] as String? ?? '');
        break;
      case 'webrtc_ice_candidate':
        debugPrint('[CM] webrtc_ice_candidate received');
        webrtc.handleRemoteIceCandidate(
          d['candidate'],
          d['sdpMid'] as String?,
          (d['sdpMLineIndex'] as num?)?.toInt(),
        );
        break;

      // ---- exec ----
      case 'exec_result':
        debugPrint('[CM] exec_result: ok');
        break;

      // ---- 日志 ----
      case 'logs':
        debugPrint('[CM] logs 消息: keys=${d.keys.toList()}');
        debugPrint(
          '[CM] logs 条数=${(d['logs'] as List?)?.length ?? (d['line_no'] != null ? '单条推送' : '0')}',
        );
        // 无 mode 字段且非批量数组 → 流式推送，追加而非覆盖
        final isPush =
            d['mode'] == null && d['logs'] is! List && d['line_no'] != null;
        _data.updateLogs(
          d,
          mode: isPush ? 'push' : (d['mode'] as String? ?? 'tail'),
        );
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

  /// 共享的 RobotDataStore（供 UI 与测试读取）
  RobotDataStore get dataStore => _data;
}

/// 兼容旧代码 — 连接状态
AppConnectionState connStateToAppState(ConnState s) {
  switch (s) {
    case ConnState.disconnected:
      return AppConnectionState.disconnected;
    case ConnState.connecting:
      return AppConnectionState.connecting;
    case ConnState.connected:
      return AppConnectionState.connected;
    case ConnState.binding:
      return AppConnectionState.connecting;
    case ConnState.error:
      return AppConnectionState.error;
  }
}

// ConnectionManager 与 RobotDataStore 共享同一实例（web-debug 单一 store 模式）
final connectionManagerProvider =
    StateNotifierProvider<ConnectionManager, ConnState>(
      (ref) => ConnectionManager(data: ref.read(robotDataProvider.notifier)),
    );

/// 分块下载缓冲（对齐 web-debug ChunkedDownload）
class _ChunkedDownload {
  final String fileName;
  final int sizeBytes;
  final int totalChunks;
  final Map<int, String> chunks = {};
  _ChunkedDownload({
    required this.fileName,
    required this.sizeBytes,
    required this.totalChunks,
  });
}
