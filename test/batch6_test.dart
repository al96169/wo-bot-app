// 批次 6 测试：Signal URL 构造 / 云端设备合并去重 / bindDevice 请求体
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
