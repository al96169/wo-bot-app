import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/theme/app_colors.dart';
import 'widgets/quick_action_bar.dart';

/// 遥控页面 — 匹配 web-debug RemoteView.vue
///
/// 横屏: 双摇杆 (左=平移+偏航, 右=云台)
/// 竖屏: 单摇杆 + D-Pad
class RemoteControlPage extends ConsumerStatefulWidget {
  const RemoteControlPage({super.key});

  @override
  ConsumerState<RemoteControlPage> createState() => _RemoteControlPageState();
}

class _RemoteControlPageState extends ConsumerState<RemoteControlPage> {
  // 共享运动状态 — 匹配 web-debug motionState
  final ValueNotifier<MotionState> _motion = ValueNotifier(const MotionState());
  Timer? _motionTimer;

  // 摇杆状态
  final ValueNotifier<JoystickValue> _moveStick = ValueNotifier(
    const JoystickValue(),
  );
  final ValueNotifier<JoystickValue> _yawStick = ValueNotifier(
    const JoystickValue(),
  );
  final ValueNotifier<JoystickValue> _gimbalStick = ValueNotifier(
    const JoystickValue(),
  );

  @override
  void initState() {
    super.initState();
    // 50ms 运动发送循环 — 匹配 web-debug
    _motionTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _sendMergedMotion(),
    );
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    _moveStick.dispose();
    _yawStick.dispose();
    _gimbalStick.dispose();
    _motion.dispose();
    super.dispose();
  }

  /// 合并发送运动指令 — 匹配 web-debug sendMergedMotion
  void _sendMergedMotion() {
    final m = _motion.value;
    final hasMotion = m.vx != 0 || m.vy != 0 || m.vz != 0;
    if (!hasMotion) return;

    final manager = ref.read(connectionManagerProvider.notifier);
    manager.sendMotion(m.vx, m.vy, m.vz);
  }

  /// 从摇杆值计算速度 — 匹配 web-debug speedFromStick
  double _speedFromStick(JoystickValue stick, String axis) {
    const deadzone = 0.03;
    const knobR = 22.0;
    const cx = 70.0, cy = 70.0;

    double raw;
    if (axis == 'y') {
      raw = -((stick.y - cy) / (cy - knobR));
    } else {
      raw = (stick.x - cx) / (cx - knobR);
    }

    if (raw.abs() < deadzone) return 0;
    return raw.sign * (raw.abs() * 0.7); // raw^0.7 近似
  }

  /// 从云台摇杆计算速度 — 匹配 web-debug gimbalSpeedFromState (sqrt 曲线)
  ({double pan, double tilt}) _gimbalSpeedFromStick(JoystickValue stick) {
    const deadzone = 0.05;
    const knobR = 22.0;
    const cx = 70.0, cy = 70.0;

    double rawPan = (stick.x - cx) / (cx - knobR);
    double rawTilt = -((stick.y - cy) / (cy - knobR));

    double pan = rawPan.abs() < deadzone ? 0 : rawPan.sign * sqrt(rawPan.abs());
    double tilt = rawTilt.abs() < deadzone
        ? 0
        : rawTilt.sign * sqrt(rawTilt.abs());

    return (pan: pan, tilt: tilt);
  }

  void _onMoveStickChanged(JoystickValue val) {
    final vx = _speedFromStick(val, 'y');
    final vy = -_speedFromStick(val, 'x'); // 麦轮 vy 正 = 左移
    _motion.value = _motion.value.copyWith(vx: vx, vy: vy);

    if (vx == 0 && vy == 0 && _motion.value.vz == 0) {
      final manager = ref.read(connectionManagerProvider.notifier);
      manager.sendMotionStop();
    }
  }

  void _onYawStickChanged(JoystickValue val) {
    final vz = -_speedFromStick(val, 'x') * 5.0; // Rosmaster v_z 范围 [-5, 5]
    _motion.value = _motion.value.copyWith(vz: vz);

    if (vz == 0 && _motion.value.vx == 0 && _motion.value.vy == 0) {
      final manager = ref.read(connectionManagerProvider.notifier);
      manager.sendMotionStop();
    }
  }

  void _onGimbalStickChanged(JoystickValue val, bool isStart, bool isEnd) {
    final manager = ref.read(connectionManagerProvider.notifier);
    if (isStart) {
      final speed = _gimbalSpeedFromStick(val);
      manager.sendGimbalMoveBegin(speed.pan, speed.tilt);
    } else if (isEnd) {
      manager.sendGimbalMoveEnd();
    } else {
      final speed = _gimbalSpeedFromStick(val);
      manager.sendGimbalMoveUpdate(speed.pan, speed.tilt);
    }
  }

  void _emergencyStop() {
    final manager = ref.read(connectionManagerProvider.notifier);
    manager.sendEmergencyStop();
    _motion.value = const MotionState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 停止运动
            final manager = ref.read(connectionManagerProvider.notifier);
            manager.sendMotionStop();
            Navigator.of(context).pop();
          },
        ),
        title: const Text('遥控'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle, color: AppColors.error),
            onPressed: _emergencyStop,
            tooltip: '急停',
          ),
        ],
      ),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            if (orientation == Orientation.landscape) {
              return _buildLandscape();
            }
            return _buildPortrait();
          },
        ),
      ),
    );
  }

  /// 横屏: 双摇杆布局
  Widget _buildLandscape() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              // 左: 平移 + 偏航
              Expanded(
                child: Row(
                  children: [
                    // 平移摇杆
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          JoystickWidget(
                            label: '平移',
                            onChanged: (val) {
                              _moveStick.value = val;
                              _onMoveStickChanged(val);
                            },
                          ),
                        ],
                      ),
                    ),
                    // 偏航摇杆
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          JoystickWidget(
                            label: '偏航',
                            horizontalOnly: true,
                            onChanged: (val) {
                              _yawStick.value = val;
                              _onYawStickChanged(val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 右: 云台摇杆
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    JoystickWidget(
                      label: '云台',
                      color: Colors.teal,
                      onChanged: (val) {
                        _gimbalStick.value = val;
                        _onGimbalStickChanged(val, false, false);
                      },
                      onStart: (val) => _onGimbalStickChanged(val, true, false),
                      onEnd: (val) => _onGimbalStickChanged(val, false, true),
                    ),
                    const SizedBox(height: 8),
                    // 云台居中按钮
                    ElevatedButton.icon(
                      onPressed: () {
                        ref
                            .read(connectionManagerProvider.notifier)
                            .sendGimbalCenter();
                      },
                      icon: const Icon(Icons.center_focus_strong, size: 16),
                      label: const Text('居中', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const QuickActionBar(),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 竖屏: D-Pad + 快捷栏
  Widget _buildPortrait() {
    return Column(
      children: [
        const Spacer(),
        // D-Pad
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DPadButton(
                icon: Icons.keyboard_arrow_up,
                onPress: () => _motion.value = _motion.value.copyWith(vx: 0.6),
                onRelease: () => _motion.value = _motion.value.copyWith(vx: 0),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DPadButton(
                    icon: Icons.keyboard_arrow_left,
                    onPress: () =>
                        _motion.value = _motion.value.copyWith(vy: 0.6),
                    onRelease: () =>
                        _motion.value = _motion.value.copyWith(vy: 0),
                  ),
                  const SizedBox(width: 8),
                  _DPadButton(
                    icon: Icons.stop,
                    color: AppColors.error,
                    onPress: _emergencyStop,
                    onRelease: () {},
                  ),
                  const SizedBox(width: 8),
                  _DPadButton(
                    icon: Icons.keyboard_arrow_right,
                    onPress: () =>
                        _motion.value = _motion.value.copyWith(vy: -0.6),
                    onRelease: () =>
                        _motion.value = _motion.value.copyWith(vy: 0),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _DPadButton(
                icon: Icons.keyboard_arrow_down,
                onPress: () => _motion.value = _motion.value.copyWith(vx: -0.6),
                onRelease: () => _motion.value = _motion.value.copyWith(vx: 0),
              ),
              const SizedBox(height: 16),
              // 偏航控制
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DPadButton(
                    icon: Icons.rotate_left,
                    size: 56,
                    onPress: () =>
                        _motion.value = _motion.value.copyWith(vz: 2.5),
                    onRelease: () =>
                        _motion.value = _motion.value.copyWith(vz: 0),
                  ),
                  const SizedBox(width: 24),
                  _DPadButton(
                    icon: Icons.center_focus_strong,
                    size: 56,
                    color: Colors.teal,
                    onPress: () {
                      ref
                          .read(connectionManagerProvider.notifier)
                          .sendGimbalCenter();
                    },
                    onRelease: () {},
                  ),
                  const SizedBox(width: 24),
                  _DPadButton(
                    icon: Icons.rotate_right,
                    size: 56,
                    onPress: () =>
                        _motion.value = _motion.value.copyWith(vz: -2.5),
                    onRelease: () =>
                        _motion.value = _motion.value.copyWith(vz: 0),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        const QuickActionBar(),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// 运动状态 — 匹配 web-debug motionState
class MotionState {
  final double vx; // 前后 (上为正)
  final double vy; // 左右平移 (左为正)
  final double vz; // 偏航旋转 (左转为正)

  const MotionState({this.vx = 0, this.vy = 0, this.vz = 0});

  MotionState copyWith({double? vx, double? vy, double? vz}) {
    return MotionState(vx: vx ?? this.vx, vy: vy ?? this.vy, vz: vz ?? this.vz);
  }
}

/// 摇杆值 (Canvas 坐标)
class JoystickValue {
  final double x;
  final double y;
  final bool dragging;

  const JoystickValue({this.x = 70, this.y = 70, this.dragging = false});
}

/// Canvas 摇杆组件 — 匹配 web-debug 摇杆实现
class JoystickWidget extends StatefulWidget {
  final String label;
  final Color color;
  final bool horizontalOnly;
  final void Function(JoystickValue val)? onChanged;
  final void Function(JoystickValue val)? onStart;
  final void Function(JoystickValue val)? onEnd;

  const JoystickWidget({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.horizontalOnly = false,
    this.onChanged,
    this.onStart,
    this.onEnd,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  static const double _size = 140;
  static const double _cx = 70;
  static const double _cy = 70;
  static const double _knobR = 22;
  static const double _maxDist = 55 - _knobR; // 最大移动距离

  double _knobX = _cx;
  double _knobY = _cy;

  void _updateFromDetails(Offset localPosition) {
    double dx = localPosition.dx - _cx;
    double dy = localPosition.dy - _cy;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist > _maxDist + _knobR) {
      final angle = atan2(dy, dx);
      dx = cos(angle) * (_maxDist + _knobR);
      dy = sin(angle) * (_maxDist + _knobR);
    }

    setState(() {
      _knobX = _cx + dx;
      _knobY = widget.horizontalOnly ? _cy : _cy + dy;
    });

    widget.onChanged?.call(JoystickValue(x: _knobX, y: _knobY, dragging: true));
  }

  void _reset() {
    setState(() {
      _knobX = _cx;
      _knobY = _cy;
    });
    widget.onEnd?.call(const JoystickValue());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _size,
          height: _size,
          child: GestureDetector(
            onPanStart: (details) {
              widget.onStart?.call(
                JoystickValue(x: _knobX, y: _knobY, dragging: true),
              );
              _updateFromDetails(details.localPosition);
            },
            onPanUpdate: (details) => _updateFromDetails(details.localPosition),
            onPanEnd: (_) => _reset(),
            onPanCancel: _reset,
            child: CustomPaint(
              painter: _JoystickPainter(
                knobX: _knobX,
                knobY: _knobY,
                color: widget.color,
                horizontalOnly: widget.horizontalOnly,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final double knobX;
  final double knobY;
  final Color color;
  final bool horizontalOnly;

  _JoystickPainter({
    required this.knobX,
    required this.knobY,
    required this.color,
    this.horizontalOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 70.0, cy = 70.0;
    const knobR = 22.0;
    const outerR = 55.0;

    // 外圈
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(cx, cy), outerR, outerPaint);

    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(const Offset(cx, cy), outerR, borderPaint);

    // 十字线
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    canvas.drawLine(
      const Offset(cx - outerR, cy),
      const Offset(cx + outerR, cy),
      linePaint,
    );
    if (!horizontalOnly) {
      canvas.drawLine(
        const Offset(cx, cy - outerR),
        const Offset(cx, cy + outerR),
        linePaint,
      );
    }

    // 旋钮
    final knobPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(knobX, knobY), knobR, knobPaint);

    // 旋钮内圈
    final innerPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(knobX, knobY), knobR * 0.5, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      knobX != oldDelegate.knobX || knobY != oldDelegate.knobY;
}

/// D-Pad 按钮
class _DPadButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPress;
  final VoidCallback onRelease;

  const _DPadButton({
    required this.icon,
    required this.onPress,
    required this.onRelease,
    this.color = AppColors.primary,
    this.size = 72,
  });

  @override
  State<_DPadButton> createState() => _DPadButtonState();
}

class _DPadButtonState extends State<_DPadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        widget.onPress();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onRelease();
      },
      onTapCancel: () {
        setState(() => _pressed = false);
        widget.onRelease();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed
              ? widget.color.withValues(alpha: 0.3)
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressed ? widget.color : AppColors.divider,
            width: _pressed ? 2 : 1,
          ),
        ),
        child: Icon(widget.icon, color: widget.color, size: widget.size * 0.5),
      ),
    );
  }
}
