// 批次 2 测试 — 机器人主页导航 + 快捷控制页 + 状态页渲染
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/features/robot_home/presentation/robot_home_page.dart';
import 'package:wo_bot/features/status/presentation/robot_status_page.dart';

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: child));

void main() {
  testWidgets('机器人主页渲染功能导航', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(const RobotHomePage()));
    await tester.pump(const Duration(milliseconds: 300));

    // 标题
    expect(find.text('机器人主页'), findsOneWidget);
    // 无连接时：无 feature 限制的入口全部显示（对齐 web-debug：连接后才显示带 feature 的项）
    expect(find.text('快捷控制'), findsOneWidget);
    expect(find.text('日志'), findsOneWidget);
    expect(find.text('消息'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('进程'), findsOneWidget);
    // 带 feature 的入口（遥控/SSH/软件管理）未连接时不显示
    expect(find.text('遥控'), findsNothing);
    expect(find.text('SSH'), findsNothing);
    expect(find.text('软件管理'), findsNothing);
  });

  testWidgets('状态页渲染状态卡', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(const RobotStatusPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('状态'), findsOneWidget);
    expect(find.text('设备状态'), findsOneWidget);
    expect(find.text('设备信息'), findsOneWidget);
    expect(find.text('子系统'), findsOneWidget);
  });
}
