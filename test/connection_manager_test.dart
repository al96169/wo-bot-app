// 架构测试 — ConnectionManager 与 RobotDataStore 共享实例（修复数据不同步根因）
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';

void main() {
  test('ConnectionManager 与 UI 共享同一 RobotDataStore 实例', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // provider 创建 ConnectionManager 时注入共享 data
    final manager = container.read(connectionManagerProvider.notifier);
    final uiStore = container.read(robotDataProvider.notifier);

    // 两者必须是同一实例（关键断言）
    expect(
      identical(manager.dataStore, uiStore),
      isTrue,
      reason: 'ConnectionManager 与 UI 必须共享同一 RobotDataStore，否则日志/状态不同步',
    );

    // ConnectionManager 更新 logs → UI 立即可读
    manager.dataStore.updateLogs({
      'mode': 'tail',
      'logs': [
        {
          'line_no': 1,
          'timestamp': 't',
          'level': 'INFO',
          'source': 'wobot',
          'message': '共享实例测试',
        },
      ],
    }, mode: 'tail');

    final uiLogs = container.read(robotDataProvider.notifier).logs;
    expect(uiLogs.length, 1);
    expect(uiLogs[0].message, '共享实例测试');
  });

  test('默认无注入时自建实例（兼容独立使用）', () {
    final manager = ConnectionManager();
    expect(manager.dataStore, isNotNull);
    expect(identical(manager.dataStore, RobotDataStore()), isFalse);
    manager.dispose();
  });
}
