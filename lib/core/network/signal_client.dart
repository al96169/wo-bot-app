import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

/// 云端信令客户端 — 对齐 web-debug connectViaSignal
///
/// 职责:
/// 1. WSS 连接信令服务器 (role=client&robotId&token)
/// 2. WebRTC 协商: call / call-ack(TURN) / answer / ice（扁平消息，无 data 包装）
/// 3. DataChannel 业务通道（复用 webrtc_service 的消息分发）
/// 4. 双心跳 + 分级重连
///
/// 业务消息统一走 DataChannel（信令 WS 只跑信令），
/// DC 消息通过 [onDataChannelMessage] 回调交给 ConnectionManager 统一处理。
class SignalClient {
  /// 信令服务器地址（如 wss://signal.wo-bot.com/ws）
  String signalUrl;

  /// 云端设备 ID（机器人注册 ID）
  String robotId;

  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;

  // 状态
  bool _connecting = false;
  bool _handshakeAccepted = false;
  int _reconnectCount = 0;
  bool _intentionalClose = false;

  // 心跳
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  int _lastPongTime = 0;

  // ICE fallback
  Timer? _iceFallbackTimer;
  Timer? _mediaTimeoutTimer;

  // 回调
  void Function(String sdp)? onAnswer; // 供上层测试/调试
  void Function(Map<String, dynamic> msg)? onDataChannelMessage;
  void Function(bool ready)? onDataChannelReady;
  void Function(MediaStream stream, int cameraIndex)? onVideoStream;
  void Function(bool online)? onPresence;
  void Function(String message)? onError;
  void Function()? onConnected;
  void Function()? onDisconnected;

  /// 是否已建立（信令握手 + DC 打开）
  bool get isConnected => _handshakeAccepted && _dc?.state == RTCDataChannelState.RTCDataChannelOpen;

  SignalClient({required this.signalUrl, required this.robotId});

  /// 构造 WSS URL — 对齐 web-debug:
  /// `wss://host/ws?role=client&robotId=<id>&token=<jwt>`
  Uri buildWsUrl(String accessToken) {
    // 支持输入 https:// 或 wss:// 前缀
    final secure = signalUrl.startsWith('https://') || signalUrl.startsWith('wss://');
    final host = signalUrl
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^wss?://'), '');
    final wsHost = host.endsWith('/ws') ? host : '$host/ws';
    final protocol = secure ? 'wss' : 'ws';
    return Uri.parse('$protocol://$wsHost').replace(
      queryParameters: {
        'role': 'client',
        'robotId': robotId,
        'token': accessToken,
      },
    );
  }

  /// 建立云端连接（登录后调用）
  Future<void> connect(String accessToken) async {
    if (_connecting) return;
    _connecting = true;
    _intentionalClose = false;
    final url = buildWsUrl(accessToken);
    debugPrint('[Signal] 连接 $url');
    try {
      _ws = WebSocketChannel.connect(url);
      _ws!.stream.listen(
        _handleSignalMessage,
        onError: (e) {
          debugPrint('[Signal] WS 错误: $e');
          _maybeReconnect(accessToken);
        },
        onDone: () {
          debugPrint('[Signal] WS 关闭');
          _maybeReconnect(accessToken);
        },
      );
      // 连接建立后发起 WebRTC 协商
      _initiateWebRtc(accessToken);
      _startHeartbeat();
    } catch (e) {
      debugPrint('[Signal] 连接失败: $e');
      _connecting = false;
      onError?.call('信令连接失败: $e');
    }
  }

  /// 发起 WebRTC 协商（onopen 后调用）
  Future<void> _initiateWebRtc(String accessToken) async {
    try {
      // 清理旧 PC
      await _cleanupPc();
      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      });
      _setupPcEvents();

      // DataChannel "wobot-control"
      _dc = await _pc!.createDataChannel(
        'wobot-control',
        RTCDataChannelInit()..ordered = true,
      );
      _setupDataChannel();

      // 双视频 transceiver (recvonly)
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // 创建 offer 并发送 call
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      _sendSignal({
        'type': 'call',
        'sdp': {'type': 'offer', 'sdp': offer.sdp},
      });
      debugPrint('[Signal] 已发送 call');

      // ICE fallback: 5s 未连接 → restartIce
      _iceFallbackTimer?.cancel();
      _iceFallbackTimer = Timer(const Duration(seconds: 5), () {
        if (_pc != null &&
            _pc!.iceConnectionState != RTCIceConnectionState.RTCIceConnectionStateConnected &&
            _pc!.iceConnectionState != RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          debugPrint('[Signal] ICE 5s 未连接，restartIce');
          _pc!.restartIce();
        }
      });
    } catch (e) {
      debugPrint('[Signal] WebRTC 协商失败: $e');
      onError?.call('WebRTC 协商失败: $e');
    }
  }

  void _setupPcEvents() {
    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _sendSignal({
        'type': 'ice',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onIceConnectionState = (s) {
      debugPrint('[Signal] ICE: $s');
      if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        onError?.call('ICE 连接失败');
      }
    };

    _pc!.onConnectionState = (s) {
      debugPrint('[Signal] connection: $s');
    };

    // 双视频轨 → 独立 MediaStream
    int videoIndex = 0;
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind != 'video') return;
      final idx = videoIndex++;
      Future<void>(() async {
        try {
          final stream = await createLocalMediaStream('wobot-signal-cam-$idx');
          stream.addTrack(event.track);
          onVideoStream?.call(stream, idx);
        } catch (e) {
          debugPrint('[Signal] 视频流分配失败#$idx: $e');
        }
      });
    };

    // 远端 DC 兜底
    _pc!.onDataChannel = (dc) {
      debugPrint('[Signal] 远端 DC: ${dc.label}');
      _dc = dc;
      _setupDataChannel();
    };
  }

  void _setupDataChannel() {
    _dc!.onDataChannelState = (state) {
      switch (state) {
        case RTCDataChannelState.RTCDataChannelOpen:
          debugPrint('[Signal] DataChannel opened');
          _handshakeAccepted = true;
          _reconnectCount = 0;
          onDataChannelReady?.call(true);
          onConnected?.call();
          // 初始化业务订阅（对齐 web-debug setupSignalDataChannel）
          _sendDc('subscribe', {'events': ['status']});
          _sendDc('get_status');
          _sendDc('camera', {'action': 'list'});
          break;
        case RTCDataChannelState.RTCDataChannelClosed:
          debugPrint('[Signal] DataChannel closed');
          _handshakeAccepted = false;
          onDataChannelReady?.call(false);
          onDisconnected?.call();
          break;
        default:
          break;
      }
    };

    _dc!.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) return;
      try {
        final json = jsonDecode(msg.text) as Map<String, dynamic>;
        // 解包 response 信封
        if (json['type'] == 'response' && json['data'] is Map) {
          final inner = json['data'] as Map<String, dynamic>;
          onDataChannelMessage?.call(inner.cast<String, dynamic>());
        } else {
          onDataChannelMessage?.call(json);
        }
      } catch (e) {
        debugPrint('[Signal] DC 消息解析失败: $e');
      }
    };
  }

  /// 处理信令服务器消息（扁平 JSON）
  void _handleSignalMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? '';

      switch (type) {
        case 'pong':
          _lastPongTime = DateTime.now().millisecondsSinceEpoch;
          break;
        case 'call-ack':
          // 配置 TURN（对齐 web-debug：STUN + TURN UDP/TCP）
          final turn = msg['turn'] as Map<String, dynamic>?;
          if (turn != null && _pc != null) {
            _configureTurn(turn);
          }
          break;
        case 'answer':
          final sdp = msg['sdp'];
          final sdpStr = sdp is Map ? sdp['sdp'] as String? : sdp as String?;
          if (sdpStr == null || _pc == null) return;
          // 状态守卫: have-local-offer
          if (_pc!.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
            _pc!.setRemoteDescription(RTCSessionDescription(sdpStr, 'answer'));
            debugPrint('[Signal] 已设置 answer');
          }
          onAnswer?.call(sdpStr);
          break;
        case 'ice':
          final candidate = msg['candidate'];
          if (candidate == null || _pc == null) return;
          if (candidate is String && candidate.isEmpty) return;
          if (candidate is Map && (candidate['candidate'] == null || candidate['candidate'].toString().isEmpty)) return;
          _pc!.addCandidate(
            candidate is String
                ? RTCIceCandidate(candidate, '', 0)
                : RTCIceCandidate(
                    candidate['candidate'] as String? ?? '',
                    candidate['sdpMid'] as String?,
                    (candidate['sdpMLineIndex'] as num?)?.toInt() ?? 0,
                  ),
          );
          break;
        case 'presence':
          final online = msg['online'] as bool? ?? false;
          if (!online) {
            debugPrint('[Signal] 设备不在线');
            onPresence?.call(false);
            onError?.call('设备不在线');
          } else {
            onPresence?.call(true);
          }
          break;
        case 'error':
          final message = msg['message'] as String? ?? '信令错误';
          debugPrint('[Signal] 服务器错误: $message');
          onError?.call(message);
          break;
        default:
          debugPrint('[Signal] 未知信令消息: $type');
      }
    } catch (e) {
      debugPrint('[Signal] 信令消息处理失败: $e');
    }
  }

  /// 配置 TURN 服务器（call-ack 后）
  Future<void> _configureTurn(Map<String, dynamic> turn) async {
    try {
      final host = _turnHost();
      if (host.isEmpty || _pc == null) return;
      final username = turn['username'] as String? ?? '';
      final credential = turn['credential'] as String? ?? '';
      await _pc!.setConfiguration({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {
            'urls': 'turn:$host:3478',
            'username': username,
            'credential': credential,
          },
          {
            'urls': 'turn:$host:3478?transport=tcp',
            'username': username,
            'credential': credential,
          },
        ],
      });
      debugPrint('[Signal] TURN 已配置: turn:$host:3478');
    } catch (e) {
      debugPrint('[Signal] TURN 配置失败: $e');
    }
  }

  String _turnHost() {
    // 从 signalUrl 提取主机（去掉协议和 /ws 路径）
    final host = signalUrl.replaceFirst(RegExp(r'^https?://'), '');
    final noPath = host.split('/').first;
    return noPath;
  }

  // ===================== 发送 =====================

  void _sendSignal(Map<String, dynamic> msg) {
    if (_ws != null) {
      try {
        _ws!.sink.add(jsonEncode(msg));
      } catch (e) {
        debugPrint('[Signal] 发送失败: $e');
      }
    }
  }

  void _sendDc(String type, [Map<String, dynamic>? data]) {
    if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dc!.send(
        RTCDataChannelMessage(
          data != null ? jsonEncode({'type': type, 'data': data}) : jsonEncode({'type': type}),
        ),
      );
    }
  }

  // ===================== 心跳 =====================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      // 信令 WS ping
      _sendSignal({'type': 'ping'});
      // DC 业务 ping（已连接时）
      if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
        _sendDc('ping', {'ts': DateTime.now().millisecondsSinceEpoch});
      }
      // pong 超时检查（15s + 5s）
      if (_lastPongTime > 0 &&
          DateTime.now().millisecondsSinceEpoch - _lastPongTime > 20000) {
        debugPrint('[Signal] pong 超时，主动断开');
        _ws?.sink.close();
      }
    });
  }

  // ===================== 重连 =====================

  void _maybeReconnect(String accessToken) {
    if (_intentionalClose) return;
    // close code >= 4000 不重连
    _reconnectCount++;
    final maxRetries = _handshakeAccepted ? 30 : 3;
    if (_reconnectCount > maxRetries) {
      debugPrint('[Signal] 重连次数超限，放弃');
      onDisconnected?.call();
      return;
    }
    final delay = Duration(seconds: 3 * _reconnectCount);
    debugPrint('[Signal] ${delay.inSeconds}s 后重连 (第 $_reconnectCount 次)');
    Timer(delay, () {
      if (!_intentionalClose) {
        _connecting = false;
        connect(accessToken);
      }
    });
  }

  // ===================== 清理 =====================

  Future<void> _cleanupPc() async {
    _handshakeAccepted = false;
    _iceFallbackTimer?.cancel();
    _mediaTimeoutTimer?.cancel();
    try {
      await _dc?.close();
    } catch (_) {}
    _dc = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  /// 断开（主动，不重连）
  Future<void> disconnect() async {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    try {
      await _ws?.sink.close(ws_status.goingAway);
    } catch (_) {}
    _ws = null;
    await _cleanupPc();
    _connecting = false;
  }
}
