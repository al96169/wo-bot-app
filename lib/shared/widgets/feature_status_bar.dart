import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/robot_data_store.dart';
import '../models/robot_data.dart';

/// 功能页状态栏 — 匹配 Pixso 状态栏组件 (5:1137, 428×76)
///
/// 结构：返回按钮(44) + 标题 + (可选)右侧图标
/// 连接状态下展示：Wifi / 蜂窝 / 电量（由 RobotDataStore 驱动）
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
    // 读取系统状态（电量/WiFi）
    ref.watch(robotDataProvider);
    final data = ref.read(robotDataProvider.notifier);
    final system = data.system;

    return SizedBox(
      height: 76,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
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
            // 标题 bold 19.6 (Pixso 1:4593)
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 19.6,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1C1E),
                ),
              ),
            ),
            // 右侧操作区
            if (actions != null) ...actions!,
            // 连接状态指示（已连接时显示）
            _ConnectionStatus(system: system),
          ],
        ),
      ),
    );
  }
}

/// 连接状态胶囊 — 绿色圆点 + "已连接"，对齐 Pixso 连接状态组件 (5:1125)
class _ConnectionStatus extends StatelessWidget {
  final SystemStatusData system;
  const _ConnectionStatus({required this.system});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x1A34C759), // 绿色 10% 透明
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF34C759),
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            '已连接',
            style: TextStyle(fontSize: 11.6, color: Color(0xFF1C1C1E)),
          ),
        ],
      ),
    );
  }
}
