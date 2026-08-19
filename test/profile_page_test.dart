// 个人页 Widget 测试 — 登录态展示云端设备卡片、未登录态展示登录入口
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/app.dart';
import 'package:wo_bot/core/network/account_service.dart';
import 'package:wo_bot/features/profile/presentation/profile_page.dart';

void main() {
  setUp(() {
    // 重置 AccountService 单例，避免测试间残留登录态
    AccountService.instance.resetForTest();
  });

  tearDown(() {
    // 取消自动刷新 Timer，避免测试结束时仍有挂起计时器
    AccountService.instance.resetForTest();
  });

  testWidgets('未登录时显示登录入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfilePage())),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('登录'), findsOneWidget);
    expect(find.text('Wo-Bot 官网'), findsOneWidget);
    expect(find.text('Wo-Bot 个人中心'), findsOneWidget);
  });

  testWidgets('已登录时显示云端设备卡片与设备数量', (tester) async {
    SharedPreferences.setMockInitialValues({
      'wobot_access_token': 't',
      'wobot_refresh_token': 'r',
      'wobot_token_expires_at': DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfilePage())),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // 登录态卡片
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('设备数量'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    // 测试环境 HTTP 被屏蔽 → 云端设备为空 → 展示空态文案
    expect(find.textContaining('暂无云端设备'), findsOneWidget);

    // 取消 init() 安排的自动刷新 Timer，避免挂起计时器报错
    AccountService.instance.resetForTest();
  });

  testWidgets('App 四 Tab 导航包含个人页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: WoBotApp()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('设备'), findsOneWidget);
    expect(find.text('自动化'), findsOneWidget);
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('个人'), findsOneWidget);

    // 切到个人页
    await tester.tap(find.text('个人'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('登录'), findsOneWidget);
  });
}
