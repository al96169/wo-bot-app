import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/utils/app_toast.dart';
import 'features/device_list/presentation/device_list_page.dart';
import 'features/profile/presentation/profile_page.dart';
import 'features/messages/presentation/messages_page.dart';
import 'features/robot_info/presentation/robot_info_page.dart';

/// wo-bot App — 4-Tab 底部导航严格匹配 Pixso 设计
/// 顶栏74 + 内容772 + 底部导航80 = 926
class WoBotApp extends ConsumerStatefulWidget {
  const WoBotApp({super.key});
  @override
  ConsumerState<WoBotApp> createState() => _WoBotAppState();
}

class _WoBotAppState extends ConsumerState<WoBotApp> {
  int _tab = 0;

  static const _tabs = <_TabInfo>[
    _TabInfo(Icons.precision_manufacturing, '设备'),
    _TabInfo(Icons.account_tree, '自动化'),
    _TabInfo(Icons.palette, '发现'),
    _TabInfo(Icons.person, '个人'),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wo-bot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: const Color(0xFFF9F9F9)),
      home: Builder(
        builder: (context) {
          // 注册全局 Toast Overlay 上下文（home 内层，位于 Navigator Overlay 之下）
          AppToast.register(context);
          return Stack(
            children: [
              IndexedStack(
                index: _tab,
                children: [
                  const DeviceListPage(),
                  _PlaceholderPage('自动化', '敬请期待'),
                  _PlaceholderPage('发现', '敬请期待'),
                  const ProfilePage(),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomNav(
                  currentTab: _tab,
                  onTab: (i) => setState(() => _tab = i),
                ),
              ),
            ],
          );
        },
      ),
      routes: {
        '/robot-info': (context) => const RobotInfoPage(),
        '/messages': (context) => const MessagesPage(),
        '/messages-create': (context) => Scaffold(
          appBar: AppBar(title: const Text('写消息')),
          body: const Center(child: Text('功能开发中')),
        ),
      },
    );
  }
}

/// 占位页面 — 匹配 Pixso (自动化/发现)
class _PlaceholderPage extends StatelessWidget {
  final String title, subtitle;
  const _PlaceholderPage(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 74),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.construction,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF3D3D3D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

/// 底部导航 80px
class _BottomNav extends StatelessWidget {
  final int currentTab;
  final void Function(int) onTab;
  const _BottomNav({required this.currentTab, required this.onTab});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8E8), width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_WoBotAppState._tabs.length, (i) {
            return _NavItem(
              icon: _WoBotAppState._tabs[i].icon,
              label: _WoBotAppState._tabs[i].label,
              active: i == currentTab,
              onTap: () => onTab(i),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Pixso 1:4191 — 选中态 #0256FF，未选中 #3D3D3D，文字 12sp
    final color = active ? const Color(0xFF0256FF) : const Color(0xFF3D3D3D);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1,
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo(this.icon, this.label);
}
