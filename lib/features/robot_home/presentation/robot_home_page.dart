import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../shared/widgets/feature_status_bar.dart';

// 批次 2 功能页
import '../../logs/presentation/logs_page.dart';
import '../../messages/presentation/messages_page.dart';
import '../../process/presentation/process_page.dart';
import '../../quick_control/presentation/quick_control_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../software/presentation/software_page.dart';
import '../../status/presentation/robot_status_page.dart';

/// 机器人主页 — 匹配 Pixso 5:1022
///
/// 状态栏(76px) + 白卡内功能导航列表（9 个入口，各 60px）
/// 入口按机器人 features 动态显示（对齐 web-debug 顶栏导航）
class RobotHomePage extends ConsumerWidget {
  const RobotHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(connectionManagerProvider);
    final manager = ref.read(connectionManagerProvider.notifier);
    final features = manager.remoteFeatures;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            // 状态栏 (Pixso 5:1138) — 机器人名 + 页面名 + 连接状态由状态栏自动显示
            FeatureStatusBar(
              title: '机器人主页',
              onBack: () => Navigator.of(context).pop(),
            ),
            // 主内容滚动区 (Pixso 5:1190)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                child: _buildNavList(context, features),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 功能导航列表 — 对齐 Pixso 5:1179（白底圆角卡片）
  Widget _buildNavList(BuildContext context, List<String> features) {
    // 全部功能入口（对齐 web-debug ALL_NAV_ITEMS，按 features 过滤）
    final items = <_NavEntry>[
      _NavEntry(
        '快捷控制',
        Icons.bolt,
        () => _push(context, const QuickControlPage()),
      ),
      const _NavEntry('遥控', Icons.gamepad, null, feature: 'motion'),
      const _NavEntry('SSH', Icons.terminal, null, feature: 'exec'),
      _NavEntry(
        '日志',
        Icons.receipt_long,
        () => _push(context, const LogsPage()),
      ),
      _NavEntry(
        '消息',
        Icons.mail_outline,
        () => _push(context, const MessagesPage()),
      ),
      _NavEntry(
        '状态',
        Icons.monitor_heart,
        () => _push(context, const RobotStatusPage()),
      ),
      _NavEntry(
        '设置',
        Icons.settings_outlined,
        () => _push(context, const SettingsPage()),
      ),
      _NavEntry('进程', Icons.memory, () => _push(context, const ProcessPage())),
      _NavEntry(
        '软件管理',
        Icons.apps,
        () => _push(context, const SoftwarePage()),
        feature: 'exec',
      ),
    ];

    final visible = items.where((e) {
      if (e.feature == null) return true;
      return features.contains(e.feature);
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 0.5,
                thickness: 0.5,
                color: Color(0xFFD8D8D8),
              ),
            _NavRow(entry: visible[i]),
          ],
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _NavEntry {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? feature;
  const _NavEntry(this.label, this.icon, this.onTap, {this.feature});
}

/// 导航行 — 匹配 Pixso 5:1204 (398×60, 分隔线)
class _NavRow extends StatelessWidget {
  final _NavEntry entry;
  const _NavRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              // 图标 30×30 (Pixso 5:1202 容器 52)
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                child: Icon(
                  entry.icon,
                  size: 24,
                  color: const Color(0xFF0256FF),
                ),
              ),
              const SizedBox(width: 12),
              // 名称 14sp (Pixso 1:49)
              Expanded(
                child: Text(
                  entry.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF3D3D3D),
                  ),
                ),
              ),
              // 右侧箭头 (Pixso 1:52 Icon)
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFFC7C7CC),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
