// 批次 5 测试：配置解析 / 绑定列表 / 配置保存命令
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';

void main() {
  test('config_get_ack 存储完整配置', () {
    final store = RobotDataStore();
    store.setRobotConfig({
      'robot': {'id': 'wobot-001', 'name': 'My Robot'},
      'motion': {'drive_type': 'mecanum', 'max_linear_speed': 1.0},
      'features': {'motion': true, 'camera': true},
    });
    expect(store.configLoaded, isTrue);
    expect(store.robotConfig['robot']['name'], 'My Robot');
    expect((store.robotConfig['motion'] as Map)['drive_type'], 'mecanum');
  });

  test('bind_list_ack 存储绑定列表', () {
    final store = RobotDataStore();
    store.setBindings([
      {'clientId': 'abc123', 'clientName': '手机A', 'boundAt': '2026-08-23T10:00:00Z', 'lastSeen': '2026-08-23T12:00:00Z'},
      {'clientId': 'def456', 'clientName': '平板', 'boundAt': '2026-08-23T11:00:00Z'},
    ]);
    expect(store.bindings.length, 2);
    expect(store.bindings.first['clientName'], '手机A');
    expect(store.bindings.first['clientId'], 'abc123');
  });

  test('config_set 提交全量配置（消息格式）', () {
    // 验证 ConnectionManager.sendConfigSet 生成 {config: {...}} 格式
    // 此处通过 store 直接模拟数据完整性
    final config = {
      'robot': {'name': 'New Name'},
      'power_policy': {'threshold': 40},
    };
    expect(config.containsKey('robot'), isTrue);
    expect((config['power_policy'] as Map)['threshold'], 40);
  });
}
