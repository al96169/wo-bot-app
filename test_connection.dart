/// 独立测试脚本 — 直接测 WebSocket 连接 + 完整协议交互
/// 运行: dart run test_connection.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const robotHost = 'localhost';
const robotPort = 18765;

void log(String msg) => print('[TEST] $msg');

Future<void> main() async {
  log('=== 开始连接测试 ===');
  log('目标: ws://$robotHost:$robotPort');

  try {
    // 1. 连接
    final uri = Uri.parse('ws://$robotHost:$robotPort?protocol_version=1');
    final ws = await WebSocket.connect(uri.toString());
    log('WebSocket 已连接');

    // 2. 等待握手
    final handshake = await ws.first.timeout(const Duration(seconds: 5));
    final hsData = jsonDecode(handshake as String) as Map<String, dynamic>;
    log('握手响应: type=${hsData['type']}, data=${hsData['data']}');
    assert(hsData['type'] == 'connected', '握手失败: ${hsData['type']}');

    // 3. 发送命令
    log('--- 测试 motion 命令 ---');
    ws.add(jsonEncode({
      'type': 'motion',
      'payload': {'v_x': 1.0, 'v_y': 0.0, 'v_z': 0.0}
    }));
    log('motion 已发送');

    ws.add(jsonEncode({'type': 'motion_stop'}));
    log('motion_stop 已发送');

    // 4. ping/pong
    ws.add(jsonEncode({'type': 'ping'}));
    final pong = await ws.first.timeout(const Duration(seconds: 3));
    final pongData = jsonDecode(pong as String);
    assert(pongData['type'] == 'pong', 'ping失败');
    log('ping/pong OK');

    // 5. 获取状态
    ws.add(jsonEncode({'type': 'get_status'}));
    final status = await ws.first.timeout(const Duration(seconds: 3));
    final stData = jsonDecode(status as String);
    assert(stData['type'] == 'status', '状态获取失败');
    log('状态: ${stData['data']}');

    // 6. gimbal 控制
    ws.add(jsonEncode({
      'type': 'gimbal',
      'payload': {'action': 'move', 'axis': 'yaw', 'angle': 45.0}
    }));
    log('gimbal 已发送');

    // 7. 测试多轮回合
    log('--- 多轮命令测试 ---');
    for (var i = 0; i < 3; i++) {
      ws.add(jsonEncode({'type': 'ping'}));
      final resp = await ws.first.timeout(const Duration(seconds: 3));
      final r = jsonDecode(resp as String);
      assert(r['type'] == 'pong', '第${i+1}轮ping失败');
      log('  第${i+1}轮 OK');
    }

    ws.close();
    log('=== 全部测试通过 ===');

  } catch (e, st) {
    log('测试失败: $e');
    log('堆栈: $st');
    exit(1);
  }
}
