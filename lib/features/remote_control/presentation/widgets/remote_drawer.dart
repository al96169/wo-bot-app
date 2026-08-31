import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/connection_manager.dart';
import '../../../../core/utils/app_toast.dart';
import '../../../logs/presentation/logs_page.dart';
import '../../../messages/presentation/messages_page.dart';
import '../../../process/presentation/command_log_page.dart';
import '../../../ssh_terminal/presentation/ssh_terminal_page.dart';
import '../../../status/presentation/robot_status_page.dart';

/// 遥控页左侧抽屉 — 页面切换（SSH/日志/消息/状态）+ 底部退出
class RemoteDrawer extends ConsumerWidget {
  const RemoteDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(connectionManagerProvider.notifier);
    final hasSsh = manager.remoteFeatures.contains('exec');

    return Drawer(
      backgroundColor: const Color(0xFF1C1C1E),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 标题
            const Text(
              'wo-bot 遥控',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 24),
            // 页面切换
            _DrawerItem(
              icon: Icons.terminal,
              label: 'SSH',
              enabled: hasSsh,
              onTap: () {
                Navigator.of(context).pop();
                if (hasSsh) {
                  SshTerminalPage.open(context);
                } else {
                  AppToast.show('设备不支持 SSH');
                }
              },
            ),
            _DrawerItem(
              icon: Icons.receipt_long,
              label: '日志',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LogsPage()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.terminal,
              label: '命令日志',
              onTap: () {
                Navigator.of(context).pop();
                CommandLogPage.open(context);
              },
            ),
            _DrawerItem(
              icon: Icons.mail_outline,
              label: '消息',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MessagesPage()),
                );
              },
            ),
            _DrawerItem(
              icon: Icons.monitor_heart,
              label: '状态',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const RobotStatusPage()),
                );
              },
            ),
            const Spacer(),
            const Divider(color: Color(0xFF3A3A3C), height: 1),
            // 退出
            _DrawerItem(
              icon: Icons.logout,
              label: '退出遥控',
              color: const Color(0xFFFF453A),
              onTap: () {
                // 停止运动并退出
                ref.read(connectionManagerProvider.notifier).sendMotionStop();
                Navigator.of(context).pop(); // 关抽屉
                Navigator.of(context).pop(); // 退出遥控页
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool enabled;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.color = Colors.white,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: enabled ? color : const Color(0xFF555557),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: enabled ? Colors.white : const Color(0xFF555557),
        ),
      ),
      onTap: enabled ? onTap : null,
    );
  }
}
