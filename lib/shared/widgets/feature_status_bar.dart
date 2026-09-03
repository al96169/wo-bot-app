import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/theme/theme_controller.dart';
import '../models/robot_data.dart';

/// 功能页状态栏 — 匹配 Pixso 状态栏组件 (5:1137, 428×76)
///
/// 结构：返回按钮(44) + 标题区(机器人名 + 页面名) + 主题按钮 + 右侧操作区 + 状态胶囊
/// - 机器人名称与连接状态由 ConnectionManager 驱动
/// - Wifi / 蜂窝 / 电量图标由 RobotDataStore 驱动（对齐 Pixso 5:1137 容器 35）
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

    // 系统状态（电量/WiFi — 对齐 Pixso 5:1137）
    ref.watch(robotDataProvider);
    final system = ref.read(robotDataProvider.notifier).system;

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
            // 主题循环按钮（对齐 web-debug AppHeader toggleTheme）
            const _ThemeToggleButton(),
            // 右侧操作区
            if (actions != null) ...actions!,
            const SizedBox(width: 8),
            // 右侧：Wifi/蜂窝/电量 + 连接状态胶囊（Pixso 5:1137 容器 35）
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DeviceStatusIcons(system: system),
                const SizedBox(height: 4),
                const _ConnectionStatus(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 主题循环按钮 — 点击 auto→light→dark 循环（对齐 web-debug AppHeader toggleTheme）
class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(themeControllerProvider.notifier);
    final mode = controller.mode;
    final icon = switch (mode) {
      AppThemeMode.light => Icons.light_mode_outlined,
      AppThemeMode.dark => Icons.dark_mode_outlined,
      AppThemeMode.auto => Icons.brightness_auto_outlined,
    };
    return Tooltip(
      message: '主题: ${mode.label}（点击切换）',
      child: InkWell(
        onTap: () => controller.cycle(),
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 40,
          height: 44,
          child: Icon(icon, size: 20, color: const Color(0xFF6750A4)),
        ),
      ),
    );
  }
}

/// 设备状态图标组 — Wifi / 蜂窝 / 电量，对齐 Pixso 5:1137 容器 2 (5:1124)
/// - Wifi：有 SSID/信号时高亮，否则灰显
/// - 蜂窝：真机为 WiFi 机器人暂无数据源，灰显占位（保留设计位置）
/// - 电量：电池图标 + 百分比（充电时显示充电图标）
class _DeviceStatusIcons extends StatelessWidget {
  final SystemStatusData system;
  const _DeviceStatusIcons({required this.system});

  @override
  Widget build(BuildContext context) {
    final hasWifi =
        (system.wifiSSID?.isNotEmpty ?? false) || system.wifiSignal > 0;
    final wifiColor = hasWifi
        ? const Color(0xFF232222)
        : const Color(0x33232222);
    const cellularColor = Color(0x33232222); // 无蜂窝数据源，灰显占位
    final level = system.batteryLevel;
    // 真机无电池数据时 status=unknown/not_present，回退 level 100 → 不显示电量
    final hasBattery = level > 0 &&
        system.batteryStatus != 'unknown' &&
        system.batteryStatus != 'not_present';
    final batteryIcon = system.batteryCharging
        ? Icons.battery_charging_full
        : _batteryIcon(level);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi, size: 14, color: wifiColor),
        const SizedBox(width: 6),
        const Icon(Icons.signal_cellular_alt, size: 14, color: cellularColor),
        const SizedBox(width: 6),
        Icon(batteryIcon, size: 14, color: const Color(0xFF232222)),
        const SizedBox(width: 3),
        Text(
          hasBattery ? '${level.round()}%' : '--',
          style: const TextStyle(fontSize: 11.6, color: Color(0xFF3D3D3D)),
        ),
      ],
    );
  }

  /// 电量分段图标（对齐系统电池图标惯例）
  IconData _batteryIcon(double level) {
    if (level >= 90) return Icons.battery_full;
    if (level >= 80) return Icons.battery_6_bar;
    if (level >= 65) return Icons.battery_5_bar;
    if (level >= 50) return Icons.battery_4_bar;
    if (level >= 35) return Icons.battery_3_bar;
    if (level >= 20) return Icons.battery_2_bar;
    if (level >= 10) return Icons.battery_1_bar;
    return Icons.battery_0_bar;
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
