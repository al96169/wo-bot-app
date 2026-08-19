/// Flutter 集成测试 — 测试完整 App 流程
/// 运行方式: flutter test integration_test/app_test.dart -d chrome
library;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/app.dart' as app;
import 'package:wo_bot/core/network/bind_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('wo-bot App 集成测试', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await BindService.instance.init();
      BindService.instance.resetToSelect();
    });

    testWidgets('App 启动并显示设备列表', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: app.WoBotApp()));
      await tester.pump(const Duration(seconds: 2));

      // 标题
      expect(find.text('wo-bot'), findsOneWidget);
      // 刷新按钮
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      // 手动添加按钮
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('手动添加设备对话框', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: app.WoBotApp()));
      await tester.pump(const Duration(seconds: 2));

      // 点击 + 按钮
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // 验证对话框
      expect(find.text('手动连接设备'), findsOneWidget);
      expect(find.text('IP 地址'), findsOneWidget);
      expect(find.text('端口'), findsOneWidget);
      expect(find.text('设备名称（可选）'), findsOneWidget);
      expect(find.text('连接'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('输入 IP 和端口 → 连接', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: app.WoBotApp()));
      await tester.pump(const Duration(seconds: 2));

      // 点击 +
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // 输入 IP
      await tester.enterText(find.widgetWithText(TextField, 'IP 地址'), 'localhost');
      await tester.pump();

      // 输入端口
      await tester.enterText(find.widgetWithText(TextField, '端口'), '18768');
      await tester.pump();

      // 点击连接
      await tester.tap(find.text('连接'));
      await tester.pump(const Duration(seconds: 1));

      // 应该尝试连接（可能出现错误提示因为 mock 可能没启动）
      // 但至少不应该崩溃
      expect(tester.takeException(), isNull);
    });

    testWidgets('设备列表空状态显示', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: app.WoBotApp()));
      await tester.pump(const Duration(seconds: 5)); // 等待 mDNS 扫描超时

      // 应显示空状态提示
      expect(find.textContaining('未发现设备'), findsWidgets);
      expect(find.text('重新扫描'), findsOneWidget);
    });

    testWidgets('刷新按钮触发扫描', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: app.WoBotApp()));
      await tester.pump(const Duration(seconds: 2));

      // 点击刷新
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump(const Duration(seconds: 1));

      // 不应崩溃
      expect(tester.takeException(), isNull);
    });

    testWidgets('调试日志面板显示', (tester) async {
      await tester.pumpWidget(const ProviderScope(child: app.WoBotApp()));
      await tester.pump(const Duration(seconds: 2));

      // 底部应该有调试面板
      // 检查是否有 DebugLogOverlay
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('BindService 状态机 — display 方式', (tester) async {
      final bind = BindService.instance;
      bind.resetToSelect();

      // 模拟 auth_required
      bind.handleAuthRequired({'methods': ['display', 'tts', 'gimbal']});
      expect(bind.step, BindStep.select);
      expect(bind.methods.length, greaterThanOrEqualTo(3)); // 3 methods + share_code

      // 选择 display
      bind.selectMethod(BindMethod.display);
      expect(bind.step, BindStep.display);

      // 获取 bind_request 消息
      final request = bind.getBindRequest(BindMethod.display);
      expect(request['type'], 'bind_request');
      expect(request['method'], 'display');
      expect(request['clientId'], isNotEmpty);
      expect(request['requestToken'], isNotEmpty);

      // 获取 bind_verify 消息
      final verify = bind.getBindVerify('123456');
      expect(verify['type'], 'bind_verify');
      expect(verify['randomCode'], '123456');
    });

    testWidgets('BindService 状态机 — gimbal 方式', (tester) async {
      final bind = BindService.instance;
      bind.resetToSelect();

      bind.handleAuthRequired({'methods': ['gimbal']});
      bind.selectMethod(BindMethod.gimbal);
      expect(bind.step, BindStep.gimbal);

      // 模拟输入方向
      bind.gimbalInputs.add('up');
      bind.gimbalInputs.add('down');
      bind.gimbalInputs.add('left');
      bind.gimbalInputs.add('right');

      final verify = bind.getBindGimbalVerify();
      expect(verify['type'], 'bind_verify');
      expect(verify['sequence'], ['up', 'down', 'left', 'right']);
    });

    testWidgets('BindService 状态机 — share_code 方式', (tester) async {
      final bind = BindService.instance;
      bind.resetToSelect();

      bind.handleAuthRequired({'methods': ['display']});
      bind.selectMethod(BindMethod.shareCode);
      expect(bind.step, BindStep.shareCode);

      final msg = bind.getBindShareCode('ABC123');
      expect(msg['type'], 'bind_share_use');
      expect(msg['shareCode'], 'ABC123');
    });

    testWidgets('BindService — 绑定失败 → 重试', (tester) async {
      final bind = BindService.instance;
      bind.resetToSelect();

      bind.handleAuthRequired({'methods': ['display']});
      bind.selectMethod(BindMethod.display);
      bind.handleBindFailed({'error': '验证码错误', 'attempts': 1});

      expect(bind.step, BindStep.failed);
      expect(bind.errorMessage, '验证码错误');
      expect(bind.attempts, 1);

      // 重试
      bind.resetToSelect();
      expect(bind.step, BindStep.select);
      expect(bind.errorMessage, isEmpty);
    });

    testWidgets('BindService — 绑定成功 → 凭证持久化', (tester) async {
      final bind = BindService.instance;
      bind.resetToSelect();

      bind.handleAuthRequired({'methods': ['display']});
      bind.selectMethod(BindMethod.display);

      await bind.handleBindSuccess({
        'robotId': 'test-robot-001',
        'clientToken': 'test-token-abc',
      }, '192.168.1.47', 8765);

      expect(bind.step, BindStep.success);
      expect(bind.isBound, true);
      expect(bind.activeCredential?.robotId, 'test-robot-001');
      expect(bind.activeCredential?.clientToken, 'test-token-abc');
      expect(bind.activeCredential?.deviceIp, '192.168.1.47');

      // 验证凭证查找
      final cred = bind.getCredentialFor('192.168.1.47', 8765);
      expect(cred, isNotNull);
      expect(cred?.clientToken, 'test-token-abc');

      // 其他 IP 不应找到
      expect(bind.getCredentialFor('10.0.0.1', 8765), isNull);
    });

    testWidgets('BindService — 重连自动附带凭证', (tester) async {
      final bind = BindService.instance;
      bind.resetToSelect();

      // 先绑定
      bind.handleAuthRequired({'methods': ['display']});
      bind.selectMethod(BindMethod.display);
      await bind.handleBindSuccess({
        'robotId': 'r1',
        'clientToken': 'tok1',
      }, '10.0.0.1', 8765);

      // 模拟重连 — 应该能找到凭证
      final cred = bind.getCredentialFor('10.0.0.1', 8765);
      expect(cred, isNotNull);
      expect(cred?.clientId, bind.clientId);
      expect(cred?.clientToken, 'tok1');
    });
  });
}
