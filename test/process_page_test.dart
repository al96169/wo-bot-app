// 进程页测试 — 服务列表渲染 + 空状态（数据源 service_status / status.services）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/core/utils/app_toast.dart';
import 'package:wo_bot/features/process/presentation/process_page.dart';

class _FakeConnectionManager extends ConnectionManager {
  @override
  void sendGetServiceStatus() {
    // 不实际发送（测试环境无 WS），数据由预置 store 提供
  }

  @override
  void sendServiceControl(String serviceId, String action) {
    // 记录调用，不发送
    lastControl = (serviceId, action);
  }

  (String, String)? lastControl;
}

Widget _wrap(RobotDataStore store) => ProviderScope(
  overrides: [
    robotDataProvider.overrideWith((ref) => store),
    connectionManagerProvider.overrideWith((ref) => _FakeConnectionManager()),
  ],
  child: const MaterialApp(home: ProcessPage()),
);

void main() {
  testWidgets('进程页显示运行中的服务与停止/重启按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    // 真机 service_status 格式
    store.setServices([
      {
        'service_id': 'main',
        'name': 'wo-bot-control',
        'status': 'running',
        'pid': 1234,
        'uptime': 3600,
      },
      {'service_id': 'camera', 'name': 'camera_service', 'status': 'stopped'},
    ]);

    await tester.pumpWidget(_wrap(store));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('wo-bot-control'), findsOneWidget);
    expect(find.text('camera_service'), findsOneWidget);
    // 运行中：停止 + 重启；已停止：启动 + 重启
    expect(find.text('停止'), findsOneWidget);
    expect(find.text('启动'), findsOneWidget);
    expect(find.text('重启'), findsNWidgets(2));

    AppToast.dismiss();
  });

  testWidgets('进程页无服务时显示空状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(RobotDataStore()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('暂无服务数据'), findsOneWidget);

    AppToast.dismiss();
  });
}
