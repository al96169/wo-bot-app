import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';

/// 功能页状态栏 — 匹配 Pixso 状态栏组件 (5:1137, 428×76)
///
/// 结构：返回按钮(44) + 标题区(机器人名 + 页面名) + (可选)右侧图标 + 连接状态胶囊
/// 机器人名称与连接状态由 ConnectionManager 驱动，自动显示：
/// - 已连接：主标题为机器人名，副标题为页面名，右侧绿色"已连接"胶囊
/// - 未连接：主标题为页面名，右侧灰色"未连接"胶囊
class FeatureStatusBar extends ConsumerWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const FeatureStatusBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(connectionManagerProvider);
    final manager = ref.read(connectionManagerProvider.notifier);
    final info = manager.robotInfo;
    final robotName = (info != null && info['name'] != null)
        ? '${info['name']}'
        : manager.currentDevice?.name;
    final showSubtitle =
        robotName != null && robotName.isNotEmpty && robotName != title;

    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            // 返回按钮 44×44 无背景 (Pixso 1:3211)
            Tooltip(
              message: '返回',
              child: InkWell(
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: Color(0xFF6750A4),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 标题区：机器人名(bold 19.6) + 页面名(11.6 灰) (Pixso 1:4593)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    robotName ?? title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19.6,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1C1E),
                    ),
                  ),
                  if (showSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.6,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 右侧操作区
            if (actions != null) ...actions!,
            // 连接状态指示（真实连接状态）
            const _ConnectionStatus(),
          ],
        ),
      ),
    );
  }
}

/// 连接状态胶囊 — 圆点 + 状态文案，对齐 Pixso 连接状态组件 (5:1125)
/// 已连接=绿 / 连接中·认证中=橙 / 连接失败=红 / 未连接=灰
class _ConnectionStatus extends ConsumerWidget {
  const _ConnectionStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionManagerProvider);
    final (color, label) = switch (conn) {
      ConnState.connected => (const Color(0xFF34C759), '已连接'),
      ConnState.binding => (const Color(0xFFFF9500), '认证中'),
      ConnState.connecting => (const Color(0xFFFF9500), '连接中'),
      ConnState.error => (const Color(0xFFFF3B30), '连接失败'),
      ConnState.disconnected => (const Color(0xFFC7C7CC), '未连接'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11.6, color: Color(0xFF1C1C1E)),
          ),
        ],
      ),
    );
  }
}
