/// Widget 测试 — 设备列表页 + 添加设备页跳转流程 + 绑定流程
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_bot/app.dart';
import 'package:wo_bot/core/network/bind_service.dart';

void main() {
  testWidgets('设备列表页渲染', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: WoBotApp()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('wo-bot'), findsOneWidget);
    expect(find.byKey(const Key('add_device_button')), findsOneWidget);
    expect(find.byKey(const Key('refresh_devices_button')), findsOneWidget);
  });

  testWidgets('加号跳转设备发现页，再跳转手动添加页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: WoBotApp()));
    await tester.pump(const Duration(milliseconds: 500));
    // 点击右上角 + → 设备发现界面 (Pixso 1:3365)
    await tester.tap(find.byKey(const Key('add_device_button')));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('添加设备'), findsOneWidget);
    expect(find.text('手动添加'), findsOneWidget);
    // 点击底部"手动添加" → 手动添加设备界面 (Pixso 1:3544)
    await tester.tap(find.text('手动添加'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('手动添加设备'), findsOneWidget);
    expect(find.text('机器人名称'), findsOneWidget);
    expect(find.text('机器人IP'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
  });

  testWidgets('手动添加页输入 IP', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: WoBotApp()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('add_device_button')));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('添加设备'), findsOneWidget);
    await tester.tap(find.text('手动添加'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    // 输入名称和 IP
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '我的小蜗');
    await tester.enterText(fields.at(1), '192.168.1.47');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('我的小蜗'), findsOneWidget);
    expect(find.text('192.168.1.47'), findsOneWidget);
  });

  testWidgets('BindService 状态机', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final bind = BindService.instance;
    await bind.init();
    expect(bind.isInitialized, true);
    expect(bind.clientId, isNotEmpty);
    expect(bind.isBound, false);

    // 模拟 auth_required
    final steps = <BindStep>[];
    bind.onStepChanged = (s) => steps.add(s);
    bind.handleAuthRequired({
      'methods': ['display', 'tts', 'gimbal'],
    });
    expect(bind.methods.length, 4); // 3 + share_code
    expect(steps.last, BindStep.select);

    // 选择 display 方式
    bind.selectMethod(BindMethod.display);
    expect(steps.last, BindStep.display);
    expect(bind.requestToken, isNotEmpty);

    // 选择 gimbal
    bind.selectMethod(BindMethod.gimbal);
    expect(steps.last, BindStep.gimbal);

    // 选择 share_code (不需要 requestToken)
    bind.selectMethod(BindMethod.shareCode);
    expect(steps.last, BindStep.shareCode);

    // reset
    bind.resetToSelect();
    expect(steps.last, BindStep.select);
  });
}
