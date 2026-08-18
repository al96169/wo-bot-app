/// 自动化认证流程测试 (使用 stream subscription)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const host = 'localhost';
const port = 18767;
final clientId = 'test_${Random().nextInt(999999).toString().padLeft(6, '0')}';

void log(String s) => print('[TEST] $s');

Future<void> main() async {
  log('=== 认证绑定流程测试 ===');
  log('clientId: $clientId');

  final ws = await WebSocket.connect('ws://$host:$port?protocol_version=1');
  log('1. WS 已连接');

  final completer = Completer<void>();
  int step = 0;

  ws.listen((data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    final type = msg['type'] as String;
    log(' <-- $type');

    switch (type) {
      case 'auth_required':
        step++;
        assert(step == 1, 'Expected step 1');
        log('2. auth_required: ${msg['methods']}');
        // Send wrong password
        ws.add(jsonEncode({'type': 'bind_password', 'clientId': clientId, 'password': 'wrong'}));
        break;

      case 'bind_failed':
        if (step == 1) {
          step++;
          log('3. bind_failed (wrong password): ${msg['data']?['error']}');
          // Send correct password
          ws.add(jsonEncode({'type': 'bind_password', 'clientId': clientId, 'password': 'wobot123'}));
        }
        break;

      case 'bind_success':
        step++;
        assert(step == 3, 'Expected step 3');
        log('4. bind_success: token=${msg['data']?['clientToken']}');
        break;

      case 'connected':
        step++;
        log('5. connected: ${msg['data']?['name']}');
        // Send get_status
        ws.add(jsonEncode({'type': 'get_status'}));
        break;

      case 'status':
        step++;
        log('6. status: battery=${msg['data']?['battery']}%');
        ws.add(jsonEncode({'type': 'motion', 'payload': {'v_x': 1.0}}));
        log('7. motion sent');
        ws.close();
        completer.complete();
        break;
    }
  }, onDone: () {
    if (!completer.isCompleted) {
      log('WS closed at step $step');
      completer.complete();
    }
  }, onError: (e) {
    log('ERROR: $e');
    completer.completeError(e);
  });

  await completer.future.timeout(const Duration(seconds: 15));
  log('=== 认证流程测试通过 ===');
}
