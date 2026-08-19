// 日志页测试 — 数据展示 + 空状态 + 导出按钮存在
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/core/utils/app_toast.dart';
import 'package:wo_bot/features/logs/presentation/logs_page.dart';

class _FakeConnectionManager extends ConnectionManager {
  @override
  void requestLogs({
    String mode = 'tail',
    int limit = 200,
    int? sinceLine,
    int? beforeLine,
    String? level,
  }) {
    // 不实际发送（测试环境无 WS），数据由预置 store 提供
  }
}

void main() {
  testWidgets('日志页显示日志列表与导出按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    store.updateLogs({
      'mode': 'tail',
      'logs': [
        {
          'line_no': 101,
          'timestamp': '2026-08-19 10:00:00',
          'level': 'info',
          'source': 'system',
          'message': '启动完成',
        },
        {
          'line_no': 102,
          'timestamp': '2026-08-19 10:00:01',
          'level': 'warning',
          'source': 'camera',
          'message': '温度偏高',
        },
      ],
      'has_more': false,
    }, mode: 'tail');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          robotDataProvider.overrideWith((ref) => store),
          connectionManagerProvider.overrideWith(
            (ref) => _FakeConnectionManager(),
          ),
        ],
        child: const MaterialApp(home: LogsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('日志'), findsOneWidget);
    expect(find.text('启动完成'), findsOneWidget);
    expect(find.text('温度偏高'), findsOneWidget);
    expect(find.text('导出'), findsOneWidget);

    // 点击导出 → 复制到剪贴板（不崩溃）
    await tester.tap(find.text('导出'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);

    AppToast.dismiss();
  });

  testWidgets('日志页空状态提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          robotDataProvider.overrideWith((ref) => store),
          connectionManagerProvider.overrideWith(
            (ref) => _FakeConnectionManager(),
          ),
        ],
        child: const MaterialApp(home: LogsPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 空状态：图标 + 提示文本（"暂无日志"）
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.textContaining('暂无日志'), findsOneWidget);

    AppToast.dismiss();
  });
}
