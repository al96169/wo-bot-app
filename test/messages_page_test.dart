// 消息页测试 — 真实消息数据（service_message 推送）+ 搜索 + 详情 + 标记未读
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/core/utils/app_toast.dart';
import 'package:wo_bot/features/messages/presentation/messages_page.dart';
import 'package:wo_bot/shared/models/robot_data.dart';

class _FakeConnectionManager extends ConnectionManager {
  @override
  void requestLogs({
    String mode = 'tail',
    int limit = 200,
    int? sinceLine,
    int? beforeLine,
    String? level,
  }) {}
}

Widget _wrap(RobotDataStore store, {ConnectionManager? manager}) =>
    ProviderScope(
      overrides: [
        robotDataProvider.overrideWith((ref) => store),
        connectionManagerProvider.overrideWith(
          (ref) => manager ?? _FakeConnectionManager(),
        ),
      ],
      child: const MaterialApp(home: MessagesPage()),
    );

RobotMessage _msg({
  required String id,
  required String subject,
  String body = '',
  String summary = '',
  String source = 'service_manager',
  bool read = false,
  String severity = 'info',
  DateTime? time,
}) => RobotMessage(
  id: id,
  subject: subject,
  time: time ?? DateTime(2026, 8, 19, 10, 30),
  summary: summary,
  body: body,
  read: read,
  source: source,
  severity: severity,
);

void main() {
  testWidgets('消息列表显示机器人推送的消息与空状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    store.addMessage(
      _msg(id: 'm1', subject: '设备固件更新通知', body: '固件已更新至 v2.1.0'),
    );
    store.addMessage(
      _msg(id: 'm2', subject: '低电量提醒', body: '电量低于 20%', read: true),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('设备固件更新通知'), findsOneWidget);
    expect(find.text('低电量提醒'), findsOneWidget);
    expect(find.text('暂无消息'), findsNothing);
  });

  testWidgets('无消息时显示空状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_wrap(RobotDataStore()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('暂无消息'), findsOneWidget);
  });

  testWidgets('搜索按主题/内容过滤', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    store.addMessage(_msg(id: 'm1', subject: '设备固件更新通知', body: '固件已更新'));
    store.addMessage(_msg(id: 'm2', subject: '低电量提醒', body: '电量低于 20%'));

    await tester.pumpWidget(_wrap(store));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField), '电量');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('低电量提醒'), findsOneWidget);
    expect(find.text('设备固件更新通知'), findsNothing);
  });

  testWidgets('点击消息 → 详情显示正文，标记未读生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    store.addMessage(
      _msg(
        id: 'm1',
        subject: '设备固件更新通知',
        body: '固件已更新至 v2.1.0，新增云台自动校准功能',
        source: 'ota',
      ),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('设备固件更新通知'));
    await tester.pump(const Duration(milliseconds: 400));

    // 详情弹层显示正文与来源
    expect(find.textContaining('固件已更新至 v2.1.0'), findsOneWidget);
    expect(find.textContaining('ota'), findsOneWidget);
    // 点击后自动标记已读
    expect(store.messages.first.read, isTrue);

    // 标记未读
    await tester.ensureVisible(find.text('标记未读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记未读'));
    await tester.pumpAndSettle();
    expect(store.messages.first.read, isFalse);

    AppToast.dismiss();
  });
}
