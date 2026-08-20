import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC 连接状态
enum WebRtcState { idle, connecting, connected, disconnected, failed }

extension WebRtcStateExt on WebRtcState {
  String get label {
    switch (this) {
      case WebRtcState.idle:
        return '未连接';
      case WebRtcState.connecting:
        return '连接中';
      case WebRtcState.connected:
        return '已连接';
      case WebRtcState.disconnected:
        return '已断开';
      case WebRtcState.failed:
        return '连接失败';
    }
  }
}

/// WebRTC 服务 — 匹配 web-debug useWebRTC.ts
///
/// 负责:
/// 1. 创建 RTCPeerConnection
/// 2. 创建 DataChannel "wobot-control"
/// 3. 接收双摄像头视频流
/// 4. SDP 交换 (offer/answer)
/// 5. ICE 候选交换
class WebRtcService {
  static WebRtcService? _instance;
  static WebRtcService get instance => _instance ??= WebRtcService._();
  WebRtcService._();

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  final List<RTCRtpReceiver> _videoReceivers = [];

  // 状态
  WebRtcState state = WebRtcState.idle;
  String connectionState = '';
  String iceConnectionState = '';
  String iceGatheringState = '';
  String signalingState = '';
  String dcReadyState = '';
  final List<String> localCandidates = [];
  final List<String> remoteCandidates = [];

  // 视频流
  MediaStream? videoStream0; // 左摄像头
  MediaStream? videoStream1; // 右摄像头

  // 回调
  void Function(WebRtcState state)? onStateChanged;
  void Function(MediaStream stream, int cameraIndex)? onVideoStream;
  void Function(Map<String, dynamic> msg)? onDataChannelMessage;
  void Function(bool ready)? onDataChannelReady;

  bool get isDataChannelReady =>
      _dc?.state == RTCDataChannelState.RTCDataChannelOpen;
  bool get isConnected => state == WebRtcState.connected;

  /// 建立 WebRTC 连接
  ///
  /// [sendOffer] 回调: 发送 webrtc_offer 消息到 WebSocket
  /// [sendIceCandidate] 回调: 发送 webrtc_ice_candidate 消息到 WebSocket
  Future<bool> establishConnection({
    required void Function(String sdp) sendOffer,
    required void Function(
      dynamic candidate,
      String? sdpMid,
      int? sdpMLineIndex,
    )
    sendIceCandidate,
  }) async {
    try {
      state = WebRtcState.connecting;
      onStateChanged?.call(state);

      // 清理旧连接
      await _cleanup();

      // 创建 PeerConnection
      final config = <String, dynamic>{
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };
      _pc = await createPeerConnection(config, {});

      // 创建 DataChannel "wobot-control"
      _dc = await _pc!.createDataChannel(
        'wobot-control',
        RTCDataChannelInit()..ordered = true,
      );
      _setupDataChannel();

      // 添加 2 个 Video Transceiver (recvonly) — 双摄像头
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      // ICE 候选事件
      _pc!.onIceCandidate = (candidate) {
        localCandidates.add(candidate.candidate ?? '');
        sendIceCandidate(
          candidate.candidate,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        );
      };

      // ICE 状态变化
      _pc!.onIceConnectionState = (s) {
        iceConnectionState = s.toString();
        debugPrint('[WebRTC] ICE: $iceConnectionState');
        if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _checkConnected();
        } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          state = WebRtcState.failed;
          onStateChanged?.call(state);
        }
      };

      _pc!.onIceGatheringState = (s) {
        iceGatheringState = s.toString();
        debugPrint('[WebRTC] ICE gathering: $iceGatheringState');
      };

      _pc!.onConnectionState = (s) {
        connectionState = s.toString();
        debugPrint('[WebRTC] connection: $connectionState');
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _checkConnected();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          state = WebRtcState.disconnected;
          onStateChanged?.call(state);
        }
      };

      _pc!.onSignalingState = (s) {
        signalingState = s.toString();
      };

      // 接收视频轨道（双摄像头）
      // web-debug 用 JS === 比较底层 stream 检测共享；dart 的 == 比较的是 flutter_webrtc
      // 包装对象引用（每次事件新建实例），共享检测不可靠 → 每个 video track 总是新建
      // 独立 MediaStream（createLocalMediaStream + addTrack），保证双画面各自独立
      int videoIndex = 0;
      _pc!.onTrack = (RTCTrackEvent event) {
        if (event.track.kind != 'video') return;
        final idx = videoIndex++;
        final streamCount = event.streams.length;
        debugPrint(
          '[WebRTC] onTrack#$idx trackId=${event.track.id} streams=$streamCount',
        );
        Future<void>(() async {
          try {
            final stream = await createLocalMediaStream('wobot-cam-$idx');
            stream.addTrack(event.track);
            debugPrint(
              '[WebRTC] stream#$idx ready id=${stream.id} tracks=${stream.getVideoTracks().length}',
            );
            if (idx == 0) {
              videoStream0 = stream;
            } else {
              videoStream1 = stream;
            }
            onVideoStream?.call(stream, idx);

            event.track.onEnded = () {
              debugPrint('[WebRTC] 视频 track $idx ended');
            };
          } catch (e) {
            debugPrint('[WebRTC] 分配视频流失败#$idx: $e');
          }
        });
      };

      // 创建 Offer
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      debugPrint('[WebRTC] 发送 offer');

      // 发送 offer 到信令通道
      sendOffer(offer.sdp!);

      // 启动兜底定时器
      _startFallbacks();

      return true;
    } catch (e, st) {
      debugPrint('[WebRTC] establishConnection 错误: $e\n$st');
      state = WebRtcState.failed;
      onStateChanged?.call(state);
      return false;
    }
  }

  /// 处理远程 answer
  Future<void> handleAnswer(String sdp) async {
    if (_pc == null) {
      debugPrint('[WebRTC] handleAnswer: PC 为空');
      return;
    }
    try {
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      debugPrint('[WebRTC] 已设置 remoteDescription');
    } catch (e) {
      debugPrint('[WebRTC] handleAnswer 错误: $e');
    }
  }

  /// 处理远程 ICE 候选
  Future<void> handleRemoteIceCandidate(
    dynamic candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  ) async {
    if (_pc == null) return;
    try {
      final cand = RTCIceCandidate(
        candidate is String ? candidate : jsonEncode(candidate),
        sdpMid,
        sdpMLineIndex,
      );
      await _pc!.addCandidate(cand);
      remoteCandidates.add(candidate.toString());
    } catch (e) {
      debugPrint('[WebRTC] addCandidate 错误: $e');
    }
  }

  /// 通过 DataChannel 发送消息
  void sendViaDataChannel(String type, [Map<String, dynamic>? data]) {
    if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      final msg = data != null
          ? jsonEncode({'type': type, 'data': data})
          : jsonEncode({'type': type});
      _dc!.send(RTCDataChannelMessage(msg));
      debugPrint('[WebRTC] DC → $type');
    } else {
      debugPrint('[WebRTC] DC 未就绪，丢弃: $type');
    }
  }

  /// 发送二进制数据
  void sendBinaryViaDataChannel(Uint8List bytes) {
    if (_dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dc!.send(RTCDataChannelMessage.fromBinary(bytes));
    }
  }

  void _setupDataChannel() {
    _dc!.onDataChannelState = (state) {
      switch (state) {
        case RTCDataChannelState.RTCDataChannelOpen:
          dcReadyState = 'open';
          debugPrint('[WebRTC] DataChannel opened');
          onDataChannelReady?.call(true);

          // 发送初始订阅
          sendViaDataChannel('subscribe', {
            'events': ['status'],
          });

          // 延迟请求初始数据
          Future.delayed(const Duration(milliseconds: 500), () {
            sendViaDataChannel('camera_record_query');
            sendViaDataChannel('config_get');
          });

          _checkConnected();
          break;
        case RTCDataChannelState.RTCDataChannelClosed:
          dcReadyState = 'closed';
          onDataChannelReady?.call(false);
          break;
        default:
          break;
      }
    };

    _dc!.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) return;
      try {
        final json = jsonDecode(msg.text) as Map<String, dynamic>;
        // 解包信封: { type: "response", data: { type: "xxx", data: {...} } }
        if (json['type'] == 'response' && json['data'] is Map) {
          final inner = json['data'] as Map<String, dynamic>;
          onDataChannelMessage?.call(inner.cast<String, dynamic>());
        } else {
          onDataChannelMessage?.call(json);
        }
      } catch (e) {
        debugPrint('[WebRTC] DC 消息解析失败: $e');
      }
    };
  }

  void _checkConnected() {
    if (state == WebRtcState.connected) return;
    if (isDataChannelReady) {
      state = WebRtcState.connected;
      onStateChanged?.call(state);
      debugPrint('[WebRTC] ✅ 已连接');
    }
  }

  // 兜底定时器
  Timer? _iceFallback;
  Timer? _gatheringFallback;

  void _startFallbacks() {
    _iceFallback?.cancel();
    _iceFallback = Timer(const Duration(seconds: 5), () {
      if (state == WebRtcState.connecting) {
        _checkConnected();
      }
    });

    _gatheringFallback?.cancel();
    _gatheringFallback = Timer(const Duration(seconds: 8), () {
      if (state == WebRtcState.connecting) {
        state = WebRtcState.connected;
        onStateChanged?.call(state);
        debugPrint('[WebRTC] gathering 兜底: 强制 connected');
      }
    });
  }

  /// 清理资源
  Future<void> _cleanup() async {
    _iceFallback?.cancel();
    _gatheringFallback?.cancel();
    _videoReceivers.clear();
    localCandidates.clear();
    remoteCandidates.clear();
    videoStream0 = null;
    videoStream1 = null;

    await _dc?.close();
    _dc = null;

    await _pc?.close();
    _pc = null;
  }

  /// 关闭连接
  Future<void> close() async {
    await _cleanup();
    state = WebRtcState.idle;
    onStateChanged?.call(state);
  }
}
