import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_bot/core/network/device_store.dart';
import 'package:wo_bot/shared/models/robot_device.dart';

void main() {
  test('发现设备只有在用户导入后才持久保存', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    await Future<void>.delayed(Duration.zero);
    final device = RobotDevice(
      id: 'robot-1',
      name: '客厅机器人',
      ip: '192.168.1.47',
      port: 8765,
      serviceName: '_wobot._tcp.local',
      localAvailable: true,
    );

    store.addDiscoveredDevices([device]);
    expect(store.state.devices, isEmpty);
    expect(store.state.discovered, [device]);

    await store.importDiscovered(device);
    expect(store.state.devices, [device]);
    expect(store.state.discovered, isEmpty);

    store.dispose();
  });
}
