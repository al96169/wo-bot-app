// 快捷控制页测试 — 寻找设备二态切换 + 倒计时 + 手动停止
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/utils/app_toast.dart';
import 'package:wo_bot/features/quick_control/presentation/quick_control_page.dart';

/// 记录发送的 device_control 命令
class _RecorderConnectionManager extends ConnectionManager {
  final List<Map<String, dynamic>> commands = [];

  @override
  void sendDeviceControl(String action, bool enabled) {
    commands.add({'action': action, 'enabled': enabled});
  }
}

void main() {
  testWidgets('寻找设备二态切换：点击开始 → 再点停止', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWith((ref) => recorder),
        ],
        child: const MaterialApp(home: QuickControlPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 初始：显示"寻找设备"，未锁定
    expect(find.text('寻找设备'), findsOneWidget);

    // 点击 → 开始寻找，发送 find_device=true
    await tester.tap(find.text('寻找设备'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      recorder.commands.any((c) => c['action'] == 'find_device' && c['enabled'] == true),
      isTrue,
      reason: '应发送 find_device=true',
    );
    // 按钮变为停止状态 + 倒计时
    expect(find.textContaining('停止'), findsOneWidget);
    expect(find.textContaining('30s'), findsOneWidget);

    // 倒计时 5 秒
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('25s'), findsOneWidget);

    // 再次点击 → 停止，发送 find_device=false
    await tester.tap(find.textContaining('停止'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      recorder.commands.any((c) => c['action'] == 'find_device' && c['enabled'] == false),
      isTrue,
      reason: '应发送 find_device=false',
    );
    expect(find.text('寻找设备'), findsOneWidget);
    expect(find.textContaining('停止'), findsNothing);

    // 清理 AppToast timer 与页面
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('寻找设备 30 秒倒计时结束自动复位', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWith((ref) => recorder),
        ],
        child: const MaterialApp(home: QuickControlPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('寻找设备'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('停止'), findsOneWidget);

    // 快进 31 秒 → 自动复位
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('寻找设备'), findsOneWidget);
    expect(find.textContaining('停止'), findsNothing);

    // 清理 AppToast timer 与页面
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
