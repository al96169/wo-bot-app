// 账号服务测试 — 云端设备列表获取与解绑（HTTP 层使用 MockClient）
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/account_service.dart';
import 'package:wo_bot/core/network/device_store.dart';

/// 构造一个已登录状态的 AccountService（注入 token + MockClient）
Future<AccountService> _loggedInService(MockClient client) async {
  SharedPreferences.setMockInitialValues({
    'wobot_access_token': 'test-access-token',
    'wobot_refresh_token': 'test-refresh-token',
    'wobot_token_expires_at': DateTime.now()
        .add(const Duration(hours: 1))
        .millisecondsSinceEpoch,
  });
  final service = AccountService.instance;
  // 重置单例状态，避免跨测试残留
  service.resetForTest();
  service.httpClient = client;
  await service.init();
  expect(service.isAuthenticated, true, reason: '测试前置：应处于已登录状态');
  return service;
}

void main() {
  tearDown(() {
    // 清理自动刷新 Timer 与单例状态
    AccountService.instance.resetForTest();
  });

  group('fetchCloudDevices', () {
    test('登录状态下返回类型化设备列表', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/devices');
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'robotId': 'robot-001',
                'robotName': '客厅机器人',
                'status': 'online',
                'lastSeenAt': '2026-08-01T10:00:00Z',
                'boundAt': '2026-07-20T08:00:00Z',
              },
              {
                'robotId': 'robot-002',
                'status': 'offline',
                'boundAt': '2026-07-21T08:00:00Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = await _loggedInService(client);
      final devices = await service.fetchCloudDevices();

      expect(devices.length, 2);
      expect(devices.first.robotId, 'robot-001');
      expect(devices.first.robotName, '客厅机器人');
      expect(devices.first.status, 'online');
      expect(devices[1].robotName, isNull);
      expect(devices[1].status, 'offline');
    });

    test('未登录时返回空列表且不发请求', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 401);
      });

      SharedPreferences.setMockInitialValues({});
      final service = AccountService.instance;
      service.resetForTest();
      service.httpClient = client;
      await service.init();

      final devices = await service.fetchCloudDevices();
      expect(devices, isEmpty);
      expect(called, false);
    });

    test('接口异常时返回空列表（不抛出）', () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });

      final service = await _loggedInService(client);
      final devices = await service.fetchCloudDevices();
      expect(devices, isEmpty);
    });
  });

  group('unbindDevice', () {
    test('成功解绑返回 true，并携带 Bearer 头', () async {
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/api/devices/robot-001');
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        return http.Response('{"data":{}}', 200);
      });

      final service = await _loggedInService(client);
      final ok = await service.unbindDevice('robot-001');
      expect(ok, true);
    });

    test('失败返回 false', () async {
      final client = MockClient((request) async {
        return http.Response('{"error":"not found"}', 404);
      });

      final service = await _loggedInService(client);
      final ok = await service.unbindDevice('robot-404');
      expect(ok, false);
    });
  });

  group('CloudDevice.fromJson', () {
    test('解析完整字段', () {
      final device = CloudDevice.fromJson({
        'robotId': 'r1',
        'robotName': '小蜗',
        'status': 'online',
        'lastSeenAt': '2026-08-01T00:00:00Z',
        'boundAt': '2026-07-01T00:00:00Z',
      });
      expect(device.robotId, 'r1');
      expect(device.robotName, '小蜗');
      expect(device.status, 'online');
      expect(device.boundAt, '2026-07-01T00:00:00Z');
    });

    test('缺省字段有兜底值', () {
      final device = CloudDevice.fromJson({'robotId': 'r2'});
      expect(device.robotName, isNull);
      expect(device.status, 'offline');
      expect(device.boundAt, '');
    });
  });
}
