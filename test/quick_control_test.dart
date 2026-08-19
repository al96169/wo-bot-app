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
  final List<Map<String, dynamic>> musicCommands = [];

  @override
  void sendDeviceControl(String action, bool enabled) {
    commands.add({'action': action, 'enabled': enabled});
  }

  @override
  void sendMusicVolume(int volume) {
    musicCommands.add({
      'type': 'music_volume',
      'data': {'volume': volume},
    });
  }
}

void main() {
  testWidgets('音量条可拖动，松手后发送 music_volume', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectionManagerProvider.overrideWith((ref) => recorder)],
        child: const MaterialApp(home: QuickControlPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 找到 Slider
    expect(find.byType(Slider), findsOneWidget);

    // 拖动滑块到右侧（音量增大）
    final sliderRect = tester.getRect(find.byType(Slider));
    final startX = sliderRect.left + 10;
    final endX = sliderRect.right - 10;
    await tester.dragFrom(
      Offset(startX, sliderRect.center.dy),
      Offset(endX - startX, 0),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // 拖动过程中已更新本地音量显示
    expect(find.textContaining('%'), findsNothing); // 当前显示纯数字

    // 松手后 300ms 防抖 → 发送 music_volume
    await tester.pump(const Duration(milliseconds: 400));
    expect(recorder.musicCommands, isNotEmpty, reason: '松手后应发送音量命令');
    final cmd = recorder.musicCommands.last;
    expect(cmd['type'], 'music_volume');
    expect(cmd['data']['volume'], inInclusiveRange(1, 100));

    // 清理
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('寻找设备二态切换：点击开始 → 再点停止', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final recorder = _RecorderConnectionManager();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectionManagerProvider.overrideWith((ref) => recorder)],
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
      recorder.commands.any(
        (c) => c['action'] == 'find_device' && c['enabled'] == true,
      ),
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
      recorder.commands.any(
        (c) => c['action'] == 'find_device' && c['enabled'] == false,
      ),
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
        overrides: [connectionManagerProvider.overrideWith((ref) => recorder)],
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
