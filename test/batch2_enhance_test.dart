// 批次 2 完善项测试：
// 1. 软件安装任务（software_progress/ack → 任务状态流转）
// 2. 状态页环境信息解析（environment/estimated_minutes）
// 3. 软件页三 tab 渲染
// 4. 日志页自动刷新开关 + 清空
// 5. 快捷操作页急停按钮
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/core/utils/app_toast.dart';
import 'package:wo_bot/features/quick_control/presentation/quick_control_page.dart';
import 'package:wo_bot/features/software/presentation/software_page.dart';
import 'package:wo_bot/shared/models/robot_data.dart';

/// 记录发送的软件命令
class _RecorderConnectionManager extends ConnectionManager {
  final List<String> softwareCommands = [];
  final List<Map<String, dynamic>> emergencyCommands = [];

  @override
  void sendSoftwareInstall(String package) {
    softwareCommands.add('install:$package');
  }

  @override
  void sendSoftwareUninstall(String package) {
    softwareCommands.add('uninstall:$package');
  }

  @override
  void sendSoftwareUpgrade(String package) {
    softwareCommands.add('upgrade:$package');
  }

  @override
  void sendEmergencyStop() {
    emergencyCommands.add({'action': 'emergency_stop'});
  }
}

void main() {
  test('SystemStatusData 解析 environment 与电池预计可用', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': {'level': 87, 'status': 'discharging', 'estimated_minutes': 120},
      'system': {'cpu_percent': 12.5, 'uptime': 3600},
      'network': {'ssid': 'MyHome', 'signal_strength': -52},
      'environment': {
        'temperature': 26.4,
        'humidity': 58.2,
        'gas': 0.03,
        'light': 320,
      },
    });

    expect(s.batteryLevel, 87);
    expect(s.batteryEstimatedMinutes, 120);
    expect(s.envTemperature, 26.4);
    expect(s.envHumidity, 58.2);
    expect(s.envGas, 0.03);
    expect(s.envLight, 320);
  });

  test('Store 软件任务：progress/ack 状态流转', () {
    final store = RobotDataStore();
    store.addSoftwareTask(
      SoftwareTask(
        id: 't1',
        package: 'hello',
        action: 'install',
        startedAt: DateTime.now(),
      ),
    );
    expect(store.softwareTasks.single.isRunning, isTrue);

    // progress 更新
    store.updateSoftwareTask(
      'hello',
      progress: 50,
      stage: 'downloading',
      output: 'fetch 50%',
    );
    final t = store.softwareTasks.single;
    expect(t.progress, 50);
    expect(t.stage, 'downloading');
    expect(t.output, 'fetch 50%');

    // ack 收官
    store.updateSoftwareTask(
      'hello',
      status: 'success',
      toVersion: '1.0.0',
    );
    expect(store.softwareTasks.single.status, 'success');
    expect(store.softwareTasks.single.toVersion, '1.0.0');
    expect(store.softwareTasks.single.completedAt, isNotNull);
  });

  test('Store 软件任务：按包名+action 精确匹配，失败态不再被更新', () {
    final store = RobotDataStore();
    store.addSoftwareTask(
      SoftwareTask(
        id: 'a',
        package: 'pkg',
        action: 'install',
        startedAt: DateTime.now(),
      ),
    );
    store.addSoftwareTask(
      SoftwareTask(
        id: 'b',
        package: 'pkg',
        action: 'upgrade',
        startedAt: DateTime.now(),
      ),
    );
    // 只更新 upgrade 任务（匹配最近的 running + action）
    store.updateSoftwareTask('pkg', action: 'upgrade', progress: 80);
    expect(store.softwareTasks[0].action, 'upgrade');
    expect(store.softwareTasks[0].progress, 80);
    expect(store.softwareTasks[1].progress, 0);

    // install 任务完成
    store.updateSoftwareTask('pkg', action: 'install', status: 'success');
    expect(store.softwareTasks[1].status, 'success');
    // 已完成任务不再被进度更新命中
    store.updateSoftwareTask('pkg', action: 'install', progress: 99);
    expect(store.softwareTasks[1].progress, 0);
  });

  testWidgets('软件页三 tab：已安装/可安装/安装任务', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();
    final store = RobotDataStore();
    store.setSoftwareInstalled([
      {
        'name': 'hello',
        'display_name': 'Hello',
        'status': 'installed',
        'version': '1.0.0',
      },
    ]);
    store.setSoftwareAvailable([
      {'name': 'world', 'display_name': 'World'},
    ]);
    store.addSoftwareTask(
      SoftwareTask(
        id: 't1',
        package: 'hello',
        action: 'upgrade',
        progress: 40,
        stage: 'installing',
        startedAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWith((ref) => recorder),
          robotDataProvider.overrideWith((ref) => store),
        ],
        child: const MaterialApp(home: SoftwarePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 默认已安装 tab（tab 按钮 + 筛选 chip 各一个）
    expect(find.text('已安装'), findsNWidgets(2));
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('1.0.0'), findsNothing); // 版本显示为 "当前版本 1.0.0"

    // 切到可安装
    await tester.tap(find.text('可安装'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('World'), findsOneWidget);
    expect(find.text('Hello'), findsNothing);

    // 切到安装任务（badge=1，进行中任务显示进度）
    await tester.tap(find.text('安装任务'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('40%'), findsOneWidget);
    expect(find.text('installing'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);

    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('软件页安装操作：本地建任务 + 发送命令 + 切任务 tab', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();
    final store = RobotDataStore();
    store.setSoftwareAvailable([
      {'name': 'world', 'display_name': 'World'},
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWith((ref) => recorder),
          robotDataProvider.overrideWith((ref) => store),
        ],
        child: const MaterialApp(home: SoftwarePage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 切到可安装
    await tester.tap(find.text('可安装'));
    await tester.pump(const Duration(milliseconds: 200));

    // 点安装
    await tester.tap(find.text('安装'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(recorder.softwareCommands, contains('install:world'));
    // 自动切到任务 tab，本地任务已创建
    expect(find.text('进行中'), findsOneWidget);

    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('快捷操作页显示急停按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectionManagerProvider.overrideWith((ref) => recorder)],
        child: const MaterialApp(home: QuickControlPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('急停'), findsOneWidget);

    // 点击急停 → 确认弹窗 → 确认 → 发送 emergency_stop
    // （页面可滚动，先确保按钮可见）
    await tester.ensureVisible(find.text('急停'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('急停'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('确定要紧急停止机器人吗？所有运动将立即停止。'), findsOneWidget);

    // 弹窗标题"急停" + 确认按钮"急停" + 网格按钮 → 点确认按钮
    await tester.tap(find.widgetWithText(FilledButton, '急停'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(recorder.emergencyCommands, isNotEmpty);
    expect(recorder.emergencyCommands.last['action'], 'emergency_stop');

    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
