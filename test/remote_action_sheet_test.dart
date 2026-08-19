// 遥控功能弹窗测试 — 拍照/录像/画质/图库/云台归位按钮渲染与回调
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wo_bot/features/remote_control/presentation/widgets/camera_action_sheet.dart';

void main() {
  testWidgets('功能弹窗渲染全部操作与画质选项', (tester) async {
    var captured = 0;
    var toggled = 0;
    String? qualityChanged;
    var gallery = 0;
    var centered = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraActionSheet(
            isRecording: false,
            recordTime: '00:00',
            quality: 'auto',
            onCapture: () => captured++,
            onRecordToggle: () => toggled++,
            onQualityChange: (m) => qualityChanged = m,
            onGallery: () => gallery++,
            onGimbalCenter: () => centered++,
          ),
        ),
      ),
    );

    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('录像'), findsOneWidget);
    expect(find.text('图库'), findsOneWidget);
    expect(find.text('云台归位'), findsOneWidget);
    expect(find.text('自动'), findsOneWidget);
    expect(find.text('高画质'), findsOneWidget);

    // 点击拍照
    await tester.tap(find.text('拍照'));
    expect(captured, 1);

    // 切换画质
    await tester.tap(find.text('高画质'));
    expect(qualityChanged, 'high');

    // 图库
    await tester.tap(find.text('图库'));
    expect(gallery, 1);

    // 云台归位
    await tester.tap(find.text('云台归位'));
    expect(centered, 1);

    // 录像
    await tester.tap(find.text('录像'));
    expect(toggled, 1);
  });

  testWidgets('录制中显示 REC 状态与停止按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraActionSheet(
            isRecording: true,
            recordTime: '01:23',
            quality: 'high',
            onCapture: () {},
            onRecordToggle: () {},
            onQualityChange: (_) {},
            onGallery: () {},
            onGimbalCenter: () {},
          ),
        ),
      ),
    );

    expect(find.text('停止录像'), findsOneWidget);
    expect(find.textContaining('REC 01:23'), findsOneWidget);
    expect(find.text('录像'), findsNothing);
  });
}
