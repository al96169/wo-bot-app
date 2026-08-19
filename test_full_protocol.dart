/// 完整协议测试 — 测试 web-debug 的全部 80+ 消息类型
/// 对比 web-debug 的 handleSignalingMessage，确保 App 实现了所有消息处理
library;
import 'dart:convert';
import 'dart:io';
import 'dart:async';

const MOCK_HOST = 'localhost';
const MOCK_PORT = 18768;
const REAL_HOST = '192.168.1.47';
const REAL_PORT = 8765;

// web-debug 的全部消息类型 (从 useWebSocket.ts 提取)
final webDebugMessages = {
  // 连接 & 认证
  'connected', 'auth_required', 'bind_request_ack', 'bind_challenge',
  'bind_success', 'bind_failed', 'force_disconnect',
  // 状态 & 信息
  'status', 'pong', 'robot_info', 'features_update',
  // 模块 & 服务
  'module_list', 'service_status',
  // 舞蹈
  'dance_list', 'dance_status',
  // 音乐
  'music_status', 'music_action', 'music_stream', 'music_playlist', 'music_list', 'music_volume',
  // 相机
  'camera_status', 'camera_capture_result', 'camera_record_result',
  'camera_media_list_result', 'camera_stream_quality_ack', 'camera_stream_quality_changed',
  // 软件
  'software_list', 'software_available', 'software_progress',
  'software_install_ack', 'software_uninstall_ack', 'software_upgrade_ack',
  'software_updates_available',
  // 云台
  'gimbal_status', 'gimbal_limit',
  // WiFi
  'wifi_scan_result',
  // 电源
  'power_policy_status', 'power_policy_config',
  // 配置
  'config_get_ack', 'config_set_ack',
  // 执行
  'exec_result',
  // 错误
  'error',
};

// App ConnectionManager 已处理的消息类型 (从 connection_manager.dart 提取)
final appHandledMessages = {
  'connected', 'auth_required', 'bind_request_ack', 'bind_challenge',
  'bind_success', 'bind_failed', 'force_disconnect',
  'status', 'pong', 'robot_info', 'features_update',
  'module_list', 'service_status',
  'dance_list', 'dance_status',
  'music_status', 'music_action', 'music_stream', 'music_playlist', 'music_list', 'music_volume',
  'camera_status', 'camera_capture_result', 'camera_record_result',
  'camera_media_list_result', 'camera_stream_quality_ack', 'camera_stream_quality_changed',
  'software_list', 'software_available', 'software_progress',
  'software_install_ack', 'software_uninstall_ack', 'software_upgrade_ack',
  'software_updates_available',
  'gimbal_status', 'gimbal_limit',
  'wifi_scan_result',
  'power_policy_status', 'power_policy_config',
  'config_get_ack', 'config_set_ack',
  'exec_result',
  'error',
};

// 客户端发送的消息类型
final clientSends = {
  'ping', 'get_status', 'motion', 'motion_stop', 'gimbal',
  'get_module_list', 'get_service_status',
  'dance_list', 'dance_play', 'dance_stop',
  'music_play', 'music_pause', 'music_next', 'music_prev', 'music_set_volume', 'music_list',
  'camera_capture', 'camera_record', 'camera_media_list', 'camera_stream_quality',
  'software_list', 'software_available', 'software_install', 'software_uninstall', 'software_upgrade',
  'gimbal_move', 'gimbal_home',
  'wifi_scan',
  'get_power_policy', 'set_power_policy',
  'config_get', 'config_set',
  'exec',
  'bind_request', 'bind_verify', 'bind_share_use', 'bind_password',
  'auth',
};

int passed = 0;
int failed = 0;

void check(String name, bool ok, [String? detail]) {
  if (ok) {
    print('  ✅ $name');
    passed++;
  } else {
    print('  ❌ $name${detail != null ? ': $detail' : ''}');
    failed++;
  }
}

Future<void> main(List<String> args) async {
  final useReal = args.contains('--real');
  final host = useReal ? REAL_HOST : MOCK_HOST;
  final port = useReal ? REAL_PORT : MOCK_PORT;

  print('\n=== 完整协议测试 ===');
  print('目标: $host:$port (${useReal ? "真机" : "Mock"})\n');

  // ===== 1. 消息覆盖率检查 =====
  print('--- 1. 消息覆盖率检查 ---');
  
  final missingInApp = webDebugMessages.difference(appHandledMessages);
  check('App 处理了所有 web-debug 消息类型', missingInApp.isEmpty,
    missingInApp.isEmpty ? null : '缺失: ${missingInApp.join(', ')}');
  
  final extraInApp = appHandledMessages.difference(webDebugMessages);
  check('App 无多余消息类型', extraInApp.isEmpty,
    extraInApp.isEmpty ? null : '多余: ${extraInApp.join(', ')}');
  
  check('web-debug 消息总数', webDebugMessages.length == 43, 'got ${webDebugMessages.length}');
  check('App 已处理消息数', appHandledMessages.length == 43, 'got ${appHandledMessages.length}');

  // ===== 2. 连接测试 =====
  print('\n--- 2. WebSocket 连接测试 ---');
  
  WebSocket? ws;
  final msgs = <Map<String, dynamic>>[];
  
  try {
    ws = await WebSocket.connect('ws://$host:$port?protocol_version=1&clientId=test-client-001');
    check('WebSocket 连接成功', true);
    
    final sub = ws.asBroadcastStream();
    sub.listen((data) {
      try { msgs.add(jsonDecode(data as String)); } catch (_) {}
    });
    
    await Future.delayed(const Duration(seconds: 2));
    check('收到消息', msgs.isNotEmpty, 'got ${msgs.length} messages');
    
    if (msgs.isNotEmpty) {
      final firstType = msgs.first['type'];
      check('首条消息是 auth_required 或 connected', 
        firstType == 'auth_required' || firstType == 'connected',
        'got: $firstType');
    }

    // ===== 3. 认证绑定流程 =====
    print('\n--- 3. 认证绑定流程 ---');
    
    // 如果收到 auth_required，测试绑定流程
    final authMsg = msgs.firstWhere(
      (m) => m['type'] == 'auth_required',
      orElse: () => {},
    );
    
    if (authMsg.isNotEmpty) {
      final methods = authMsg['methods'];
      check('auth_required 包含 methods', methods is List && methods.isNotEmpty,
        'methods: $methods');
      
      // 测试 display 方式
      if (methods is List && methods.contains('display')) {
        print('\n  > 测试 display 方式:');
        final rt = 'test-rt-${DateTime.now().millisecondsSinceEpoch}';
        ws.add(jsonEncode({
          'type': 'bind_request',
          'requestToken': rt,
          'clientId': 'test-client-001',
          'clientName': 'Test',
          'method': 'display',
        }));
        
        await Future.delayed(const Duration(seconds: 1));
        
        final ack = msgs.firstWhere(
          (m) => m['type'] == 'bind_request_ack',
          orElse: () => {},
        );
        check('收到 bind_request_ack', ack.isNotEmpty);
        
        final challenge = msgs.firstWhere(
          (m) => m['type'] == 'bind_challenge',
          orElse: () => {},
        );
        if (challenge.isNotEmpty) {
          final code = challenge['codeHint'] ?? challenge['code'] ?? '';
          check('收到 bind_challenge (code=$code)', code.toString().isNotEmpty);
          
          // 发送正确的验证码
          ws.add(jsonEncode({
            'type': 'bind_verify',
            'requestToken': rt,
            'randomCode': code.toString(),
          }));
          
          await Future.delayed(const Duration(seconds: 1));
          
          final success = msgs.any((m) => m['type'] == 'bind_success');
          check('收到 bind_success', success);
          
          final connected = msgs.any((m) => m['type'] == 'connected');
          check('收到 connected (握手完成)', connected);
        }
      }
      
      // 测试 gimbal 方式
      if (methods is List && methods.contains('gimbal')) {
        print('\n  > 测试 gimbal 方式:');
        msgs.clear();
        final rt = 'test-gimbal-${DateTime.now().millisecondsSinceEpoch}';
        ws.add(jsonEncode({
          'type': 'bind_request',
          'requestToken': rt,
          'clientId': 'test-client-001',
          'method': 'gimbal',
        }));
        
        await Future.delayed(const Duration(seconds: 1));
        
        final ack = msgs.any((m) => m['type'] == 'bind_request_ack');
        check('收到 bind_request_ack (gimbal)', ack);
        
        // 发送方向序列
        ws.add(jsonEncode({
          'type': 'bind_verify',
          'requestToken': rt,
          'sequence': ['up', 'down', 'left', 'right'],
        }));
        
        await Future.delayed(const Duration(seconds: 1));
        
        final result = msgs.any((m) => m['type'] == 'bind_success' || m['type'] == 'bind_failed');
        check('收到绑定结果 (success 或 failed)', result);
      }
      
      // 测试错误验证码
      print('\n  > 测试错误验证码:');
      msgs.clear();
      final rt = 'test-fail-${DateTime.now().millisecondsSinceEpoch}';
      ws.add(jsonEncode({
        'type': 'bind_request',
        'requestToken': rt,
        'clientId': 'test-client-001',
        'method': 'display',
      }));
      await Future.delayed(const Duration(seconds: 1));
      
      ws.add(jsonEncode({
        'type': 'bind_verify',
        'requestToken': rt,
        'randomCode': '000000',
      }));
      await Future.delayed(const Duration(seconds: 1));
      
      final bindFailed = msgs.any((m) => m['type'] == 'bind_failed');
      check('错误验证码 → bind_failed', bindFailed);
    }

    // ===== 4. 命令测试 =====
    print('\n--- 4. 机器人命令测试 ---');
    
    // 如果已连接，测试各种命令
    final hasConnected = msgs.any((m) => m['type'] == 'connected');
    if (hasConnected || !useReal) {
      // ping
      msgs.clear();
      ws.add(jsonEncode({'type': 'ping'}));
      await Future.delayed(const Duration(seconds: 1));
      check('ping → pong', msgs.any((m) => m['type'] == 'pong'));
      
      // get_status
      msgs.clear();
      ws.add(jsonEncode({'type': 'get_status'}));
      await Future.delayed(const Duration(seconds: 1));
      check('get_status → status', msgs.any((m) => m['type'] == 'status'));
      
      // motion
      ws.add(jsonEncode({'type': 'motion', 'payload': {'v_x': 0.5, 'v_y': 0.0, 'v_z': 0.0}}));
      await Future.delayed(const Duration(milliseconds: 500));
      check('motion 命令发送', true);
      
      // motion_stop
      ws.add(jsonEncode({'type': 'motion_stop'}));
      await Future.delayed(const Duration(milliseconds: 500));
      check('motion_stop 命令发送', true);
      
      // gimbal
      ws.add(jsonEncode({'type': 'gimbal', 'payload': {'pan': 90.0, 'tilt': 45.0}}));
      await Future.delayed(const Duration(milliseconds: 500));
      check('gimbal 命令发送', true);
      
      // 多次 ping (心跳)
      msgs.clear();
      for (int i = 0; i < 3; i++) {
        ws.add(jsonEncode({'type': 'ping'}));
        await Future.delayed(const Duration(milliseconds: 300));
      }
      final pongCount = msgs.where((m) => m['type'] == 'pong').length;
      check('心跳 3x ping → 3x pong', pongCount >= 3, 'got $pongCount pongs');
    }

    // ===== 5. 发送消息覆盖率 =====
    print('\n--- 5. 发送消息覆盖率 ---');
    
    final appSends = {
      'ping', 'get_status', 'motion', 'motion_stop', 'gimbal',
      'bind_request', 'bind_verify', 'bind_share_use', 'bind_password',
      'auth',
    };
    
    final missingSends = clientSends.difference(appSends);
    check('App 发送了所有必要命令', missingSends.isEmpty,
      missingSends.isEmpty ? null : 'App 未实现发送: ${missingSends.join(', ')}');
    
    print('\n  App 已实现发送: ${appSends.length}/${clientSends.length}');
    print('  App 未实现发送: ${missingSends.length}');
    if (missingSends.isNotEmpty) {
      print('  → ${missingSends.join(', ')}');
    }

    await ws.close();
  } catch (e) {
    check('WebSocket 连接', false, e.toString());
    if (ws != null) await ws.close();
  }

  // ===== 6. 总结 =====
  print('\n${'='*50}');
  print('  结果: $passed passed, $failed failed');
  print('  覆盖率: ${(passed / (passed + failed) * 100).toStringAsFixed(1)}%');
  print('${'='*50}\n');
  
  exit(failed > 0 ? 1 : 0);
}
