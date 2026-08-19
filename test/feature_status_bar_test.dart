// 状态栏测试 — 机器人名 + 页面名 + 真实连接状态胶囊
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/shared/models/robot_device.dart';
import 'package:wo_bot/shared/widgets/feature_status_bar.dart';

class _FakeConnectionManager extends ConnectionManager {
  @override
  Future<void> connectToDevice(RobotDevice device) async {
    state = ConnState.connected;
    currentDevice = device;
  }

  @override
  void disconnect() {
    state = ConnState.disconnected;
    currentDevice = null;
    robotInfo = null;
  }
}

Widget _wrap(Widget child, ConnectionManager fake) => ProviderScope(
  overrides: [connectionManagerProvider.overrideWith((ref) => fake)],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  testWidgets('未连接时：显示页面名 + 未连接胶囊', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeConnectionManager();
    await tester.pumpWidget(_wrap(const FeatureStatusBar(title: '日志'), fake));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('日志'), findsOneWidget);
    expect(find.text('未连接'), findsOneWidget);
    expect(find.text('已连接'), findsNothing);
  });

  testWidgets('已连接时：显示机器人名 + 页面名副标题 + 已连接胶囊', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final device = RobotDevice(
      id: 'r1',
      name: '小W',
      ip: '192.168.1.47',
      port: 8765,
      serviceName: '_wobot._tcp.local',
    );
    final fake = _FakeConnectionManager();
    await fake.connectToDevice(device);
    // 模拟机器人上报的名称
    fake.robotInfo = {'name': '小W'};

    await tester.pumpWidget(_wrap(const FeatureStatusBar(title: '日志'), fake));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('小W'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget); // 副标题页面名
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('未连接'), findsNothing);
  });

  testWidgets('有电量/WiFi 数据时：显示百分比、充电图标、WiFi 高亮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeConnectionManager();
    final store = RobotDataStore();
    // 真机嵌套格式：battery{level,status} + network{ssid,signal_strength}
    store.updateFromStatus({
      'battery': {'level': 85, 'status': 'charging'},
      'network': {'ssid': 'MyWiFi', 'signal_strength': -45},
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWith((ref) => fake),
          robotDataProvider.overrideWith((ref) => store),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FeatureStatusBar(title: '日志')),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('85%'), findsOneWidget);
    expect(find.byIcon(Icons.battery_charging_full), findsOneWidget);
    // 未连接时胶囊仍为未连接
    expect(find.text('未连接'), findsOneWidget);
  });

  testWidgets('无电量数据时显示占位 --', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fake = _FakeConnectionManager();
    await tester.pumpWidget(_wrap(const FeatureStatusBar(title: '日志'), fake));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('--'), findsOneWidget);
  });
}
