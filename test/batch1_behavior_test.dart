// 批次 1 行为测试 — Toast 系统 + 设备切换确认 + 设备卡片菜单
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/app.dart';
import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/device_store.dart';
import 'package:wo_bot/core/utils/app_toast.dart';
import 'package:wo_bot/shared/models/robot_device.dart';

/// 伪 ConnectionManager — 不发起真实 WebSocket 连接
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
  }
}

void main() {
  testWidgets('AppToast 显示并在 3 秒后消失', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: WoBotApp()));
    await tester.pump(const Duration(milliseconds: 300));

    AppToast.show('测试提示', type: AppToastType.info);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('测试提示'), findsOneWidget);

    // 3 秒后自动消失
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('测试提示'), findsNothing);

    AppToast.dismiss();
  });

  testWidgets('切换已保存设备时弹出确认', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deviceA = RobotDevice(
      id: 'a',
      name: '设备A',
      ip: '192.168.1.10',
      port: 8765,
      serviceName: '_wobot._tcp.local',
    );
    final deviceB = RobotDevice(
      id: 'b',
      name: '设备B',
      ip: '192.168.1.11',
      port: 8765,
      serviceName: '_wobot._tcp.local',
    );
    final store = DeviceStore();
    await store.addDevice(deviceA);
    await store.addDevice(deviceB);
    await store.setCurrentDevice(deviceA);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceStoreProvider.overrideWith((ref) => store),
          connectionManagerProvider
              .overrideWith((ref) => _FakeConnectionManager()),
        ],
        child: const WoBotApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('设备A'), findsOneWidget);
    expect(find.text('设备B'), findsOneWidget);

    // 点击设备B（当前设备是A）→ 应弹出切换确认
    await tester.tap(find.text('设备B'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('确认切换设备'), findsOneWidget);

    // 取消
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确认切换设备'), findsNothing);

    // 再次点击设备B → 确认切换
    await tester.tap(find.text('设备B'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('确认切换设备'), findsOneWidget);
    await tester.tap(find.text('确认切换'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('确认切换设备'), findsNothing);
    // 当前设备应切换为 B
    expect(store.state.currentDevice?.id, 'b');

    AppToast.dismiss();
  });

  testWidgets('已连接设备卡片菜单包含断开/忘记，未连接包含移除', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final deviceC = RobotDevice(
      id: 'c',
      name: '设备C',
      ip: '192.168.1.12',
      port: 8765,
      serviceName: '_wobot._tcp.local',
    );
    final store = DeviceStore();
    await store.addDevice(deviceC);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceStoreProvider.overrideWith((ref) => store),
          connectionManagerProvider
              .overrideWith((ref) => _FakeConnectionManager()),
        ],
        child: const WoBotApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('设备C'), findsOneWidget);

    // 未连接状态 → 打开菜单 → 移除设备
    await tester.tap(find.byTooltip('设备管理'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('移除设备'), findsOneWidget);
    expect(find.text('忘记设备'), findsNothing);
    // 关闭菜单
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));

    // 连接设备C → 应跳转到机器人主页（对齐 web-debug：连接后进入功能主页）
    await tester.tap(find.text('设备C'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    // 已进入机器人主页（含快捷控制入口）
    expect(find.text('快捷控制'), findsOneWidget);

    AppToast.dismiss();
  });
}
