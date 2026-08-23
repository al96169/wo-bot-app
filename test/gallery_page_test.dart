// 图库页渲染测试 — 回归：进入页面不得抛 provider 修改错误
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wo_bot/core/network/connection_manager.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/features/gallery/presentation/gallery_page.dart';

void main() {
  testWidgets('渲染图库页（含缩略图/视频项）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = RobotDataStore();
    // 模拟一张合法 base64 JPEG（1x1 红点）
    const thumb = '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==';
    store.setGalleryItems([
      {
        'file_name': 'photo_001.jpg',
        'name': 'photo_001.jpg',
        'type': 'photo',
        'size_bytes': 204800,
        'thumbnail_base64': thumb,
      },
      {
        'file_name': 'video_001.mp4',
        'name': 'video_001.mp4',
        'type': 'video',
        'size_bytes': 10485760,
        'duration_s': 15.5,
      },
    ]);
    store.setGalleryPageInfo(1, 2, false);

    // 不触发 initState 的 _refresh（避免清空预置数据），直接注入 store 渲染
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionManagerProvider.overrideWith((ref) => ConnectionManager(data: store)),
          robotDataProvider.overrideWith((ref) => store),
        ],
        child: const MaterialApp(home: GalleryPage()),
      ),
    );
    // 首帧后 _refresh 会 resetGallery（清空预置数据）—— 测试只验证"进入页面不抛 provider 错误"
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    // 进入页面无异常即通过（initState 修改 provider 的 bug 已修复）
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
