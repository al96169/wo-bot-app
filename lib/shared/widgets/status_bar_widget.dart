import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/connection_manager.dart';
import '../../core/theme/app_colors.dart';

/// 顶部状态栏
///
/// 左：连接状态图标（绿/黄/红）
/// 中：设备名
/// 右：电池百分比 + 图标
class AppStatusBar extends ConsumerWidget {
  final VoidCallback? onBatteryTap;

  const AppStatusBar({super.key, this.onBatteryTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionManagerProvider);
    final manager = ref.read(connectionManagerProvider.notifier);
    final status = manager.robotStatus;
    final device = manager.currentDevice;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          // 左：连接状态
          _buildConnectionIndicator(connectionState),
          const SizedBox(width: 12),

          // 中：设备名
          Expanded(
            child: Text(
              device?.name ?? '未连接',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 右：电池
          if (status != null && connectionState == ConnState.connected)
            _buildBatteryIndicator(context, status),
        ],
      ),
    );
  }

  Widget _buildConnectionIndicator(ConnState state) {
    final color = _connectionColor(state);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Color _connectionColor(ConnState state) {
    switch (state) {
      case ConnState.connected: return AppColors.success;
      case ConnState.connecting: return AppColors.warning;
      case ConnState.binding: return AppColors.warning;
      case ConnState.error: return AppColors.error;
      case ConnState.disconnected: return AppColors.textSecondary;
    }
  }

  Widget _buildBatteryIndicator(BuildContext context, dynamic status) {
    return GestureDetector(
      onTap: onBatteryTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.batteryStatusText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.batteryColor(status.batteryLevel),
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 4),
          _BatteryIcon(
            level: status.batteryLevel,
            charging: status.batteryCharging,
          ),
        ],
      ),
    );
  }
}

/// 电池图标自定义绘制
class _BatteryIcon extends StatelessWidget {
  final int level;
  final bool charging;

  const _BatteryIcon({required this.level, required this.charging});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.batteryColor(level);
    return SizedBox(
      width: 28,
      height: 14,
      child: CustomPaint(
        painter: _BatteryPainter(
          level: level / 100.0,
          color: color,
          charging: charging,
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final double level;
  final Color color;
  final bool charging;

  _BatteryPainter({
    required this.level,
    required this.color,
    required this.charging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.6);

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    // 电池外壳
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 1, size.width - 4, size.height - 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(bodyRect, paint);

    // 电池正极头
    final capRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 4, size.height * 0.3, 3.5, size.height * 0.4),
      const Radius.circular(1),
    );
    canvas.drawRRect(capRect, fillPaint);

    // 电量填充
    final fillWidth = (bodyRect.width - 3) * level.clamp(0.0, 1.0);
    if (fillWidth > 0) {
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(1.5, 2.5, fillWidth, bodyRect.height - 5),
        const Radius.circular(1),
      );
      canvas.drawRRect(fillRect, fillPaint);
    }

    // 充电闪电图标
    if (charging) {
      final lightningPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white;
      final path = Path()
        ..moveTo(size.width * 0.45, size.height * 0.15)
        ..lineTo(size.width * 0.3, size.height * 0.55)
        ..lineTo(size.width * 0.42, size.height * 0.55)
        ..lineTo(size.width * 0.34, size.height * 0.9)
        ..lineTo(size.width * 0.55, size.height * 0.4)
        ..lineTo(size.width * 0.43, size.height * 0.4)
        ..close();
      canvas.drawPath(path, lightningPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) =>
      level != oldDelegate.level ||
      color != oldDelegate.color ||
      charging != oldDelegate.charging;
}
