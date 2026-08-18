// 日志解析测试 — 模拟真机 logs 响应验证 updateLogs
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';

void main() {
  test('updateLogs 解析真机 tail 响应', () {
    final store = RobotDataStore();
    store.updateLogs({
      'mode': 'tail',
      'logs': [
        {'line_no': 101, 'timestamp': '2026-08-19 10:00:00', 'level': 'info', 'source': 'system', 'message': '启动完成'},
        {'line_no': 102, 'timestamp': '2026-08-19 10:00:01', 'level': 'warning', 'source': 'camera', 'message': '温度偏高'},
        {'line_no': 103, 'timestamp': '2026-08-19 10:00:02', 'level': 'error', 'source': 'motion', 'message': '指令超时'},
      ],
      'total_lines': 3,
      'next_since': 103,
      'has_more': false,
    }, mode: 'tail');

    expect(store.logs.length, 3);
    expect(store.logs[0].lineNo, 101);
    expect(store.logs[0].time, '2026-08-19 10:00:00');
    expect(store.logs[0].level, 'info');
    expect(store.logs[1].level, 'warn', reason: 'warning 应映射为 warn');
    expect(store.logs[2].level, 'error');
    expect(store.logCursor, 103);
    expect(store.logHasMore, false);
    store.dispose();
  });

  test('updateLogs 处理空日志列表', () {
    final store = RobotDataStore();
    store.updateLogs({'mode': 'tail', 'logs': [], 'has_more': false}, mode: 'tail');
    expect(store.logs, isEmpty);
    store.dispose();
  });
}
