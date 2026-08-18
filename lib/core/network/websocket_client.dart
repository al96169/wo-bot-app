import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants/app_constants.dart';

/// WebSocket 协议版本
const int protocolVersion = 1;

/// WebSocket 客户端
///
/// 消息格式匹配 web-debug: { "type": "...", "data": {...} }
class WsClient {
  WebSocketChannel? _channel;
  int _reconnectAttempts = 0;
  Timer? _heartbeatTimer;
  StreamSubscription? _subscription;
  String? _currentIp;
  int _currentPort = AppConstants.defaultWebSocketPort;
  Map<String, String>? _currentExtra;

  /// 收到消息回调
  void Function(Map<String, dynamic> msg)? onMessage;
  void Function()? onDisconnected;
  void Function(String error)? onError;
  void Function(String state)? onStateChanged;

  /// 连接到指定 IP:端口
  Future<void> connect(String ip, {int port = 8765, Map<String, String>? extraParams}) async {
    _currentIp = ip;
    _currentPort = port;
    _currentExtra = extraParams;
    _reconnectAttempts = 0;
    onStateChanged?.call('connecting');
    debugPrint('[WS] connect() → $ip:$port');

    try {
      var query = 'protocol_version=$protocolVersion';
      if (extraParams != null) {
        for (final entry in extraParams.entries) {
          if (entry.value.isNotEmpty) {
            query += '&${entry.key}=${Uri.encodeComponent(entry.value)}';
          }
        }
      }
      final uri = Uri.parse('ws://$ip:$port?$query');
      debugPrint('[WS] URI: $uri');

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.timeout(
        Duration(seconds: AppConstants.connectionTimeoutSec),
      );
      debugPrint('[WS] 握手完成');

      _subscription = _channel!.stream.listen(
        _onData,
        onDone: () {
          debugPrint('[WS] stream onDone');
          _handleDisconnect();
        },
        onError: (e) {
          debugPrint('[WS] stream onError: $e');
          onError?.call(e.toString());
          _handleDisconnect();
        },
        cancelOnError: true,
      );

      onStateChanged?.call('connected');
      _startHeartbeat();
    } catch (e, st) {
      debugPrint('[WS] 连接失败: $e\n$st');
      onStateChanged?.call('error');
      onError?.call(e.toString());
      _handleDisconnect();
    }
  }

  /// 发送命令 — 匹配 web-debug 格式: { "type": "...", "data": {...} }
  void sendCommand(String type, [Map<String, dynamic> data = const {}]) {
    sendRaw({'type': type, 'data': data});
  }

  /// 发送原始 JSON Map
  void sendRaw(Map<String, dynamic> msg) {
    if (_channel == null) {
      debugPrint('[WS] 未连接, 丢弃: ${msg['type']}');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(msg));
      debugPrint('[WS] → ${msg['type']}');
    } catch (e) {
      debugPrint('[WS] 发送失败 ${msg['type']}: $e');
    }
  }

  /// 发送二进制数据
  void sendBinary(List<int> bytes) {
    if (_channel == null) return;
    _channel!.sink.add(bytes);
  }

  /// 断开连接
  void disconnect() {
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    onStateChanged?.call('disconnected');
  }

  bool get isConnected => _channel != null;

  // ---- 内部方法 ----

  void _onData(dynamic data) {
    try {
      var text = data is String ? data : utf8.decode(data as List<int>);
      // 容错：wo-bot-control (Python json.dumps) 默认输出 NaN/Infinity/-Infinity，
      // 非标准 JSON — Dart jsonDecode 无法解析。仅替换 JSON 数值位置的 token
      // （前面是冒号/逗号/括号，后面是逗号/括号），避免误改字符串内容。
      if (text.contains('NaN') || text.contains('Infinity')) {
        text = text.replaceAllMapped(
          RegExp(r'(?<=[:,\[\{])\s*(NaN|-?Infinity)\s*(?=[,\}\]])'),
          (_) => 'null',
        );
      }
      final json = jsonDecode(text) as Map<String, dynamic>;
      onMessage?.call(json);
    } catch (e) {
      final s = data.toString();
      debugPrint('[WS] 解析失败: $e → ${s.length > 120 ? s.substring(0, 120) : s}');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: AppConstants.heartbeatIntervalSec),
      (_) => sendRaw({'type': 'ping'}),
    );
  }

  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _channel = null;

    if (_reconnectAttempts >= AppConstants.maxReconnectAttempts) {
      onDisconnected?.call();
      return;
    }

    final delayMs = AppConstants.reconnectBaseDelayMs * (1 << _reconnectAttempts);
    final cappedDelayMs = delayMs > AppConstants.reconnectMaxDelayMs
        ? AppConstants.reconnectMaxDelayMs
        : delayMs;
    _reconnectAttempts++;

    onStateChanged?.call('reconnecting');

    if (_currentIp != null) {
      Timer(Duration(milliseconds: cappedDelayMs), () {
        if (_currentIp != null) {
          connect(_currentIp!, port: _currentPort, extraParams: _currentExtra);
        }
      });
    }
  }
}
