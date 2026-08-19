import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

/// 虚拟摇杆组件
///
/// 使用 GestureDetector 实现自定义双轴摇杆
class JoystickWidget extends StatefulWidget {
  /// 摇杆值变化回调 (x, y) 范围 [-1, 1]
  final ValueChanged<Offset> onChanged;

  /// 松手回调
  final VoidCallback? onEnd;

  /// 背景圆半径
  final double baseRadius;

  /// 摇杆拇指半径
  final double knobRadius;

  /// 背景颜色
  final Color? backgroundColor;

  /// 拇指颜色
  final Color? knobColor;

  const JoystickWidget({
    super.key,
    required this.onChanged,
    this.onEnd,
    this.baseRadius = 80,
    this.knobRadius = 35,
    this.backgroundColor,
    this.knobColor,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _updateOffset(Offset localPosition) {
    final center = Offset(widget.baseRadius, widget.baseRadius);
    final delta = localPosition - center;

    // 计算距离和方向
    final distance = delta.distance;

    // 边界限制：不能拖出背景圆
    final maxDistance = widget.baseRadius - widget.knobRadius - 4;
    final clampedDelta = distance > maxDistance
        ? Offset(
            delta.dx / distance * maxDistance,
            delta.dy / distance * maxDistance,
          )
        : delta;

    // 归一化到 [-1, 1]
    var nx = clampedDelta.dx / maxDistance;
    var ny = -clampedDelta.dy / maxDistance; // 反转 y 轴

    // 死区处理
    if (nx.abs() < AppConstants.joystickDeadZone) nx = 0;
    if (ny.abs() < AppConstants.joystickDeadZone) ny = 0;

    // 边界裁剪
    nx = nx.clamp(-1.0, 1.0);
    ny = ny.clamp(-1.0, 1.0);

    setState(() {
      _offset = clampedDelta;
    });

    widget.onChanged(Offset(nx, ny));
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final localPos = (context.findRenderObject() as RenderBox).globalToLocal(
      details.globalPosition,
    );
    _updateOffset(localPos);
  }

  void _onPanStart(DragStartDetails details) {
    final localPos = (context.findRenderObject() as RenderBox).globalToLocal(
      details.globalPosition,
    );
    _updateOffset(localPos);
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _offset = Offset.zero;
    });
    widget.onChanged(Offset.zero);
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.backgroundColor ?? AppColors.card.withValues(alpha: 0.8);
    final knobColor = widget.knobColor ?? AppColors.primary;

    return SizedBox(
      width: widget.baseRadius * 2,
      height: widget.baseRadius * 2,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          size: Size(widget.baseRadius * 2, widget.baseRadius * 2),
          painter: _JoystickPainter(
            offset: _offset,
            baseRadius: widget.baseRadius,
            knobRadius: widget.knobRadius,
            baseColor: baseColor,
            knobColor: knobColor,
            deadZone:
                AppConstants.joystickDeadZone *
                (widget.baseRadius - widget.knobRadius),
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset offset;
  final double baseRadius;
  final double knobRadius;
  final Color baseColor;
  final Color knobColor;
  final double deadZone;

  _JoystickPainter({
    required this.offset,
    required this.baseRadius,
    required this.knobRadius,
    required this.baseColor,
    required this.knobColor,
    required this.deadZone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(baseRadius, baseRadius);

    // 背景圆
    final basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius, basePaint);

    // 背景圆边框
    final borderPaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, baseRadius, borderPaint);

    // 十字线
    final linePaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx - baseRadius + 10, center.dy),
      Offset(center.dx + baseRadius - 10, center.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - baseRadius + 10),
      Offset(center.dx, center.dy + baseRadius - 10),
      linePaint,
    );

    // 死区圆（虚线示意）
    if (deadZone > 0) {
      final dzPaint = Paint()
        ..color = AppColors.divider.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, deadZone, dzPaint);
    }

    // 摇杆拇指
    final knobPos = center + offset;
    final knobPaint = Paint()
      ..color = knobColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobPos, knobRadius, knobPaint);

    // 拇指高光
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(knobPos.dx - knobRadius * 0.25, knobPos.dy - knobRadius * 0.25),
      knobRadius * 0.4,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      oldDelegate.offset != offset;
}
