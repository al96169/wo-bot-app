// 日志解析测试 — 批量响应 + 流式推送两种真机格式
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';

void main() {
  test('批量响应：logs 数组 + tail 模式', () {
    final store = RobotDataStore();
    store.updateLogs({
      'mode': 'tail',
      'logs': [
        {'line_no': 81279, 'timestamp': '2026-08-19 06:52:07,882', 'level': 'INFO', 'source': 'wobot', 'message': 'DHT11: 30.5°C, 62.0%'},
        {'line_no': 81280, 'timestamp': '2026-08-19 06:52:08,001', 'level': 'DEBUG', 'source': 'wobot', 'message': 'heartbeat'},
      ],
      'total_lines': 2,
      'next_since': 81280,
      'has_more': false,
    }, mode: 'tail');

    expect(store.logs.length, 2);
    expect(store.logs[0].lineNo, 81279);
    expect(store.logs[0].level, 'info', reason: 'INFO 大写应转小写');
    expect(store.logs[0].source, 'wobot');
    expect(store.logs[0].message, 'DHT11: 30.5°C, 62.0%');
    expect(store.logCursor, 81280);
    store.dispose();
  });

  test('流式推送：单条日志在 data 顶层，push 模式追加', () {
    final store = RobotDataStore();
    // 先 tail 一批
    store.updateLogs({
      'mode': 'tail',
      'logs': [
        {'line_no': 1, 'timestamp': 't1', 'level': 'INFO', 'source': 's', 'message': 'first'},
      ],
    }, mode: 'tail');
    expect(store.logs.length, 1);

    // 流式推送单条（data 顶层即日志，无 mode/logs 字段）
    store.updateLogs({
      'line_no': 2,
      'timestamp': 't2',
      'level': 'INFO',
      'source': 's',
      'message': 'second',
    }, mode: 'push');

    expect(store.logs.length, 2, reason: 'push 应追加而非覆盖');
    expect(store.logs[1].lineNo, 2);
    expect(store.logs[1].message, 'second');
    store.dispose();
  });

  test('无 mode 的单条推送由 ConnectionManager 判定为 push', () {
    final store = RobotDataStore();
    // 模拟 ConnectionManager 判定：d['mode']==null 且 line_no 存在 → push
    final d = {'line_no': 5, 'timestamp': 't5', 'level': 'WARN', 'source': 's', 'message': 'warn msg'};
    final isPush = d['mode'] == null && d['logs'] is! List && d['line_no'] != null;
    expect(isPush, true);
    store.updateLogs(d, mode: isPush ? 'push' : 'tail');
    expect(store.logs.length, 1);
    expect(store.logs[0].level, 'warn');
    store.dispose();
  });
}
