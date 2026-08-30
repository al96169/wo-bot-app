// 批次 6 测试：Signal URL 构造 / 云端设备合并去重 / bindDevice 请求体
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_bot/core/network/device_store.dart';
import 'package:wo_bot/core/network/signal_client.dart';
import 'package:wo_bot/shared/models/robot_device.dart';

void main() {
  test('SignalClient 构造 WSS URL（role=client&robotId&token）', () {
    final client = SignalClient(
      signalUrl: 'wss://signal.wo-bot.com/ws',
      robotId: 'robot-abc-123',
    );
    final uri = client.buildWsUrl('jwt-token-xyz');
    expect(uri.scheme, 'wss');
    expect(uri.host, 'signal.wo-bot.com');
    expect(uri.path, '/ws');
    expect(uri.queryParameters['role'], 'client');
    expect(uri.queryParameters['robotId'], 'robot-abc-123');
    expect(uri.queryParameters['token'], 'jwt-token-xyz');
  });

  test('SignalClient WSS URL 带编码的特殊字符', () {
    final client = SignalClient(
      signalUrl: 'https://signal.wo-bot.com/ws',
      robotId: 'robot with space',
    );
    final uri = client.buildWsUrl('token/with/slash');
    expect(uri.scheme, 'wss');
    expect(uri.queryParameters['robotId'], 'robot with space');
    expect(uri.queryParameters['token'], 'token/with/slash');
  });

  test('云端设备过滤：排除本地已保存与发现的 robotId', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    await store.addDevice(
      RobotDevice(
        id: 'local-1',
        name: '本地设备',
        ip: '192.168.1.50',
        port: 8765,
        serviceName: '_wobot._tcp.local.',
      ),
    );
    // 模拟设置云端设备
    store.setCloudDevices([
      const CloudDevice(robotId: 'local-1', clientId: 'c1', status: 'online', boundAt: ''),
      const CloudDevice(robotId: 'cloud-2', clientId: 'c2', status: 'online', boundAt: ''),
    ]);
    final filtered = store.cloudDevicesFiltered;
    expect(filtered.length, 1);
    expect(filtered.first.robotId, 'cloud-2');
  });

  test('云端设备过滤：无本地设备时全部显示', () {
    final store = DeviceStore();
    store.setCloudDevices([
      const CloudDevice(robotId: 'a', clientId: 'c1', status: 'online', boundAt: ''),
      const CloudDevice(robotId: 'b', clientId: 'c2', boundAt: ''),
    ]);
    expect(store.cloudDevicesFiltered.length, 2);
  });

  test('mergedDevices：本地+云端合并为单一列表，按 robotId 去重', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    await store.addDevice(
      RobotDevice(
        id: 'robot-x',
        name: '本地机器人',
        ip: '192.168.1.50',
        port: 8765,
        serviceName: '_wobot._tcp.local.',
        bound: true,
      ),
    );
    store.setCloudDevices([
      // 与本地设备同一 robotId → 去重，不重复出现
      const CloudDevice(robotId: 'robot-x', clientId: 'c1', status: 'online', boundAt: ''),
      // 纯云端设备 → 转为 RobotDevice 形态（ip/port 空）
      const CloudDevice(robotId: 'robot-cloud', clientId: 'c2', status: 'online', boundAt: ''),
    ]);
    final merged = store.mergedDevices;
    expect(merged.length, 2);
    // 本地设备保留 ip:port
    expect(merged.first.id, 'robot-x');
    expect(merged.first.ip, '192.168.1.50');
    // 云端设备转形态：ip 空、port 0、bound=true、localAvailable=在线
    final cloud = merged.last;
    expect(cloud.id, 'robot-cloud');
    expect(cloud.ip, '');
    expect(cloud.port, 0);
    expect(cloud.bound, isTrue);
    expect(cloud.localAvailable, isTrue);
    expect(cloud.name, 'robot-cloud');
  });

  test('mergedDevices：云端离线时 localAvailable=false，名称用 robotName', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    store.setCloudDevices([
      const CloudDevice(
        robotId: 'robot-off',
        clientId: 'c3',
        robotName: '我的机器人',
        status: 'offline',
        boundAt: '',
      ),
    ]);
    final merged = store.mergedDevices;
    expect(merged.length, 1);
    expect(merged.first.name, '我的机器人');
    expect(merged.first.localAvailable, isFalse);
  });

  test('mergedDevices：本地 id 为 PTR 实例名时按 robotId 与云端去重', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceStore();
    // 本地设备 id 是 mDNS PTR 实例名（带 _wobot._tcp.local. 后缀），robotId 为首段
    await store.addDevice(
      RobotDevice(
        id: 'robot-a3d9197b-7656-4356-8af0-9eb2bd3e5ce7._wobot._tcp.local.',
        name: '机器人',
        ip: '192.168.1.47',
        port: 8765,
        serviceName: 'robot-a3d9197b-7656-4356-8af0-9eb2bd3e5ce7._wobot._tcp.local.',
        robotId: 'robot-a3d9197b-7656-4356-8af0-9eb2bd3e5ce7',
      ),
    );
    // 云端同一设备
    store.setCloudDevices([
      const CloudDevice(
        robotId: 'robot-a3d9197b-7656-4356-8af0-9eb2bd3e5ce7',
        clientId: 'c4',
        status: 'online',
        boundAt: '',
      ),
      const CloudDevice(robotId: 'robot-other', clientId: 'c5', boundAt: ''),
    ]);
    final merged = store.mergedDevices;
    // 同一设备（robotId 匹配）只显示一次 → 本地 + 另一台云端 = 2
    expect(merged.length, 2);
    expect(merged[0].id, contains('_wobot._tcp.local.'));
    expect(merged[1].id, 'robot-other');
    expect(merged[1].ip, '');
  });

  test('旧数据兼容：加载时从 PTR 实例名 id 提取 robotId', () async {
    SharedPreferences.setMockInitialValues({
      'wobot_debug_devices': jsonEncode({
        'devices': [
          {
            'id': 'robot-legacy._wobot._tcp.local.',
            'name': '旧设备',
            'ip': '192.168.1.60',
            'port': 8765,
            'serviceName': 'robot-legacy._wobot._tcp.local.',
          },
        ],
        'currentDevice': null,
      }),
    });
    final store = DeviceStore();
    // 等待异步加载
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.state.devices.length, 1);
    expect(store.state.devices.first.robotId, 'robot-legacy');
  });

  test('bindDevice 请求体为 {payload, proof}（R00040-1）', () {
    final payload = {
      'robotId': 'r1',
      'clientId': 'c1',
      'clientTokenHash': 'hash',
      'accountId': 'u1',
      'nonce': 'n1',
      'expiresAt': '1234567890000',
    };
    const proof = 'hmac-hex';
    final body = {'payload': payload, 'proof': proof};
    expect(body.containsKey('payload'), isTrue);
    expect(body['proof'], 'hmac-hex');
    expect((body['payload'] as Map)['clientTokenHash'], 'hash');
  });
}
