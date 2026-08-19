/// 认证流程集成测试 — 模拟完整绑定交互
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_bot/core/network/bind_service.dart';
import 'package:wo_bot/features/device_list/presentation/bind_view.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final bind = BindService.instance;
    bind.onStepChanged = null;
    bind.onError = null;
    bind.onBound = null;
    bind.onMethodsReady = null;
    await bind.init();
    bind.resetToSelect();
  });

  testWidgets('完整认证流程: auth_required → 选择方式 → bind_success → 跳转', (
    tester,
  ) async {
    final bind = BindService.instance;

    // 2. 模拟 auth_required 触发（通过 BindService 直接调）
    final steps = <BindStep>[];
    bind.onStepChanged = steps.add;

    bind.handleAuthRequired({
      'methods': ['display', 'tts', 'gimbal'],
    });
    await tester.pump(const Duration(milliseconds: 100));

    // 验证: 方法列表正确
    expect(bind.methods.length, 4); // 3 + share_code
    expect(
      bind.methods.map((m) => m.label).toList(),
      containsAll(['屏幕显示', '语音播报', '云台动作', '输入绑定码']),
    );
    expect(steps.last, BindStep.select);

    // 3. 选择 display 方式
    bind.selectMethod(BindMethod.display);
    expect(steps.last, BindStep.display);
    expect(bind.requestToken, isNotEmpty);

    // 4. 获取 bind_request 消息
    final req = bind.getBindRequest(BindMethod.display);
    expect(req['type'], 'bind_request');
    expect(req['method'], 'display');
    expect(req['requestToken'], bind.requestToken);
    expect(req['clientId'], bind.clientId);

    // 5. 模拟 bind_request_ack — 服务器签发新 requestToken（关键：必须覆盖本地 token）
    final localToken = bind.requestToken;
    const serverToken = 'server-issued-token-123456';
    bind.handleBindRequestAck({'requestToken': serverToken});
    expect(steps.last, BindStep.display); // 不改变 step
    expect(
      bind.requestToken,
      serverToken,
      reason: '必须使用服务器签发的 requestToken，否则 bind_verify 无法匹配',
    );
    expect(bind.requestToken, isNot(localToken));

    // 6. 获取 bind_verify — 应携带服务器签发的 token
    final verify = bind.getBindVerify('123456');
    expect(verify['type'], 'bind_verify');
    expect(verify['randomCode'], '123456');
    expect(
      verify['requestToken'],
      serverToken,
      reason: 'bind_verify 必须使用服务器签发的 requestToken',
    );

    // 7. 模拟 bind_success
    await bind.handleBindSuccess(
      {'robotId': 'robot-001', 'clientToken': 'token-abc'},
      '192.168.1.47',
      8765,
    );
    expect(steps.last, BindStep.success);
    expect(bind.isBound, true);
    expect(bind.activeCredential?.clientToken, 'token-abc');

    // 8. 验证状态机各步骤覆盖了
    expect(steps, [BindStep.select, BindStep.display, BindStep.success]);
  });

  testWidgets('云台认证流程', (tester) async {
    final bind = BindService.instance;
    final steps = <BindStep>[];
    bind.onStepChanged = steps.add;

    bind.handleAuthRequired({
      'methods': ['gimbal'],
    });
    expect(bind.methods.length, 2); // gimbal + share_code

    bind.selectMethod(BindMethod.gimbal);
    expect(steps.last, BindStep.gimbal);

    // 模拟输入方向
    bind.gimbalInputs.clear();
    bind.gimbalInputs.addAll(['up', 'right', 'down', 'left']);
    final gimbalVerify = bind.getBindGimbalVerify();
    expect(gimbalVerify['sequence'], ['up', 'right', 'down', 'left']);
  });

  testWidgets('分享码认证流程', (tester) async {
    final bind = BindService.instance;
    final steps = <BindStep>[];
    bind.onStepChanged = steps.add;

    bind.handleAuthRequired({
      'methods': ['display'],
    });
    bind.selectMethod(BindMethod.shareCode);
    expect(steps.last, BindStep.shareCode);
    // shareCode 不需要 requestToken
    expect(bind.requestToken, isEmpty);

    final msg = bind.getBindShareCode('ABC123');
    expect(msg['type'], 'bind_share_use');
    expect(msg['shareCode'], 'ABC123');
  });

  testWidgets('绑定失败 + 重试', (tester) async {
    final bind = BindService.instance;
    final steps = <BindStep>[];
    bind.onStepChanged = steps.add;

    bind.handleAuthRequired({
      'methods': ['tts'],
    });
    bind.selectMethod(BindMethod.tts);

    // 模拟失败
    bind.handleBindFailed({'error': '验证码错误', 'attempts': 1});
    expect(steps.last, BindStep.failed);
    expect(bind.errorMessage, '验证码错误');

    // 重试
    bind.resetToSelect();
    expect(steps.last, BindStep.select);

    bind.selectMethod(BindMethod.tts);
    expect(steps.last, BindStep.tts);
  });

  testWidgets('BindView 组件渲染', (tester) async {
    final bind = BindService.instance;
    bind.handleAuthRequired({
      'methods': ['display', 'tts', 'gimbal'],
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BindView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 验证方式选择页面
    expect(find.text('选择认证方式'), findsOneWidget);
    expect(find.text('屏幕显示'), findsOneWidget);
    expect(find.text('语音播报'), findsOneWidget);
    expect(find.text('云台动作'), findsOneWidget);
    expect(find.text('输入绑定码'), findsOneWidget);
  });

  testWidgets('BindView 切换到数字输入', (tester) async {
    final bind = BindService.instance;
    bind.handleAuthRequired({
      'methods': ['display'],
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BindView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 点击 "屏幕显示"
    await tester.tap(find.text('屏幕显示'));
    await tester.pump(const Duration(milliseconds: 100));

    // 应切换到数字输入界面
    expect(find.text('屏幕显示配对数字'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(bind.step, BindStep.display);
  });

  testWidgets('选择 display 方式后确认按钮可用（不转圈）', (tester) async {
    final bind = BindService.instance;
    bind.handleAuthRequired({
      'methods': ['display'],
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: BindView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 点击 "屏幕显示"
    await tester.tap(find.text('屏幕显示'));
    await tester.pump(const Duration(milliseconds: 100));

    // 核心断言：选择方式后 isSubmitting 必须为 false（web-debug 一致），
    // 确认按钮可点击，不能出现转圈（否则用户永远无法输入验证码）
    expect(
      bind.isSubmitting,
      false,
      reason: '选择方式后 isSubmitting 应为 false，确认按钮应可用',
    );
    final confirmBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '确认'),
    );
    expect(confirmBtn.onPressed, isNotNull, reason: '确认按钮应可点击，不能禁用转圈');
    // 不应出现 CircularProgressIndicator
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 输入验证码后仍可正常提交
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('确认'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(bind.step, BindStep.verifying);
    expect(bind.isSubmitting, true, reason: '提交验证码后进入 verifying');
  });

  testWidgets('凭证持久化', (tester) async {
    final bind = BindService.instance;
    await bind.handleBindSuccess(
      {'robotId': 'r1', 'clientToken': 'tok1'},
      '10.0.0.1',
      8765,
    );

    expect(bind.activeCredential?.robotId, 'r1');
    expect(bind.activeCredential?.clientToken, 'tok1');

    final cred = bind.getCredentialFor('10.0.0.1', 8765);
    expect(cred?.clientToken, 'tok1');
    expect(bind.getCredentialFor('other.ip', 8765), isNull);
  });
}
