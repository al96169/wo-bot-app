import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/network/webrtc_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_toast.dart';
import 'widgets/camera_action_sheet.dart';
import 'widgets/camera_view.dart';
import 'widgets/remote_drawer.dart';
import 'widgets/voice_button.dart';

/// 遥控页面 — 匹配 web-debug RemoteView.vue + 需求：横屏双摄像头/双摇杆
///
/// 横屏主界面: 顶部状态条 + 左右双摄像头 + 4 摇杆(平移/偏航/主摄云台/副摄云台)
///           + 功能弹窗(拍照/录像/画质/图库/云台归位) + 底部对讲 + 左侧抽屉
/// 竖屏: 单摇杆 + D-Pad（降级）
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
  final ValueNotifier<JoystickValue> _gimbalStick2 = ValueNotifier(
    const JoystickValue(),
  );

  // WebRTC 状态
  WebRtcState _webrtcState = WebRtcState.idle;
  MediaStream? _stream0; // 左主摄
  MediaStream? _stream1; // 右副摄
  bool _cameraLeftOn = false;
  bool _cameraRightOn = false;

  @override
  void initState() {
    super.initState();
    // 50ms 运动发送循环 — 匹配 web-debug
    _motionTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _sendMergedMotion(),
    );
    // 延迟建立 WebRTC（等连接与信令通道稳定）
    Future.delayed(const Duration(milliseconds: 500), _initWebRtc);
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    _moveStick.dispose();
    _yawStick.dispose();
    _gimbalStick.dispose();
    _gimbalStick2.dispose();
    _motion.dispose();
    // 停止运动并断开 WebRTC
    try {
      ref.read(connectionManagerProvider.notifier).sendMotionStop();
      ref.read(connectionManagerProvider.notifier).webrtc.close();
    } catch (_) {}
    super.dispose();
  }

  /// 建立 WebRTC（视频 + DataChannel）并自动开启双摄像头
  void _initWebRtc() {
    if (!mounted) return;
    final manager = ref.read(connectionManagerProvider.notifier);
    manager.webrtc
      ..onStateChanged = (s) {
        if (mounted) setState(() => _webrtcState = s);
      }
      ..onVideoStream = (stream, idx) {
        if (!mounted) return;
        setState(() {
          if (idx == 0) {
            _stream0 = stream;
          } else {
            _stream1 = stream;
          }
        });
      };
    manager.startWebRtc();
    // 自动开启左右摄像头
    manager.sendCamera('start', 0);
    manager.sendCamera('start', 1);
    setState(() {
      _cameraLeftOn = true;
      _cameraRightOn = true;
    });
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
  double _speedFromStick(JoystickValue stick, String axis, {double size = 140}) {
    const deadzone = 0.03;
    final cx = size / 2;
    final cy = size / 2;
    final knobR = size * 22 / 140;

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
  ({double pan, double tilt}) _gimbalSpeedFromStick(
    JoystickValue stick, {
    double size = 140,
  }) {
    const deadzone = 0.05;
    final cx = size / 2;
    final cy = size / 2;
    final knobR = size * 22 / 140;

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

  /// 平移摇杆松开：清零 vx/vy，全部归零则停止（对齐 web-debug onEnd）
  void _onMoveStickEnd() {
    final m = _motion.value;
    _motion.value = m.copyWith(vx: 0, vy: 0);
    if (_motion.value.vz == 0) {
      ref.read(connectionManagerProvider.notifier).sendMotionStop();
    }
  }

  /// 偏航摇杆松开：清零 vz，全部归零则停止
  void _onYawStickEnd() {
    final m = _motion.value;
    _motion.value = m.copyWith(vz: 0);
    if (_motion.value.vx == 0 && _motion.value.vy == 0) {
      ref.read(connectionManagerProvider.notifier).sendMotionStop();
    }
  }

  void _onGimbalStickChanged(JoystickValue val, bool isStart, bool isEnd, {double size = 140}) {
    final manager = ref.read(connectionManagerProvider.notifier);
    if (isStart) {
      final speed = _gimbalSpeedFromStick(val, size: size);
      manager.sendGimbalMoveBegin(speed.pan, speed.tilt);
    } else if (isEnd) {
      manager.sendGimbalMoveEnd();
    } else {
      final speed = _gimbalSpeedFromStick(val, size: size);
      manager.sendGimbalMoveUpdate(speed.pan, speed.tilt);
    }
  }

  void _emergencyStop() {
    final manager = ref.read(connectionManagerProvider.notifier);
    manager.sendEmergencyStop();
    _motion.value = const MotionState();
  }

  // ---- 摄像头功能 ----

  /// 拍照（画质默认 high，对齐 web-debug robotConfig.camera.capture_quality 兜底）
  void _capture() {
    ref.read(connectionManagerProvider.notifier).sendCameraCapture();
    AppToast.show('正在拍照...');
  }

  /// 录像切换（主摄）
  void _recordToggle() {
    final store = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    if (store.isRecording) {
      manager.sendCameraRecordStop();
      AppToast.show('停止录像');
    } else {
      final camId = store.cameras.isNotEmpty ? store.cameras.first.cameraId : 0;
      manager.sendCameraRecordStart(camId);
      AppToast.show('开始录像');
    }
  }

  /// 画质切换
  void _qualityChange(String mode) {
    ref.read(connectionManagerProvider.notifier).sendStreamQuality(mode);
    AppToast.show('画质切换中');
  }

  /// 打开功能弹窗（拍照/录像/画质/图库/云台归位）
  void _openActionSheet() {
    final store = ref.read(robotDataProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (ctx) => CameraActionSheet(
        isRecording: store.isRecording,
        recordTime: _fmtRecordTime(store.recordingElapsedS),
        quality: store.streamQuality,
        onCapture: () {
          Navigator.of(ctx).pop();
          _capture();
        },
        onRecordToggle: () {
          Navigator.of(ctx).pop();
          _recordToggle();
        },
        onQualityChange: (mode) {
          Navigator.of(ctx).pop();
          _qualityChange(mode);
        },
        onGallery: () {
          Navigator.of(ctx).pop();
          AppToast.show('图库即将上线（批次 4）');
        },
        onGimbalCenter: () {
          Navigator.of(ctx).pop();
          ref.read(connectionManagerProvider.notifier).sendGimbalCenter();
          AppToast.show('云台已归位');
        },
      ),
    );
  }

  static String _fmtRecordTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      drawer: const RemoteDrawer(),
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

  /// 横屏主界面：顶部状态条 + 双摄像头 + 4 摇杆 + 功能按钮 + 底部对讲
  Widget _buildLandscape() {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    final robotName = (manager.robotInfo?['name'] as String?) ??
        manager.currentDevice?.name ??
        '遥控';

    return Column(
      children: [
        // 顶部状态条：抽屉按钮 + 设备名 + WebRTC 状态 + 电量/WiFi
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(
            children: [
              Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 20),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                  tooltip: '菜单',
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  robotName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              _WebRtcBadge(state: _webrtcState),
              const SizedBox(width: 10),
              // 电量 + WiFi
              if (store.system.batteryLevel > 0) ...[
                Icon(
                  store.system.batteryCharging
                      ? Icons.battery_charging_full
                      : Icons.battery_full,
                  size: 14,
                  color: Colors.white,
                ),
                Text(
                  ' ${store.system.batteryLevel.round()}%',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
                const SizedBox(width: 8),
              ],
              Icon(
                (store.system.wifiSSID?.isNotEmpty ?? false)
                    ? Icons.wifi
                    : Icons.wifi_off,
                size: 14,
                color: Colors.white,
              ),
            ],
          ),
        ),
        // 双摄像头（左主摄 / 右副摄）
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: CameraView(
                    stream: _stream0,
                    label: '主摄',
                    enabled: _cameraLeftOn,
                    recording: store.isRecording,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CameraView(
                    stream: _stream1,
                    label: '副摄',
                    enabled: _cameraRightOn,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 4 摇杆：左主(平移) + 左小(主摄云台) | 右主(偏航) + 右小(副摄云台)
        Expanded(
          flex: 4,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    JoystickWidget(
                      label: '平移',
                      onChanged: (val) {
                        _moveStick.value = val;
                        _onMoveStickChanged(val);
                      },
                      onEnd: (_) => _onMoveStickEnd(),
                    ),
                    JoystickWidget(
                      label: '主摄云台',
                      size: 90,
                      color: Colors.teal,
                      onChanged: (val) {
                        _gimbalStick.value = val;
                        _onGimbalStickChanged(val, false, false, size: 90);
                      },
                      onStart: (val) =>
                          _onGimbalStickChanged(val, true, false, size: 90),
                      onEnd: (val) =>
                          _onGimbalStickChanged(val, false, true, size: 90),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    JoystickWidget(
                      label: '偏航',
                      horizontalOnly: true,
                      onChanged: (val) {
                        _yawStick.value = val;
                        _onYawStickChanged(val);
                      },
                      onEnd: (_) => _onYawStickEnd(),
                    ),
                    JoystickWidget(
                      label: '副摄云台',
                      size: 90,
                      onChanged: (val) {
                        _gimbalStick2.value = val;
                        _onGimbalStickChanged(val, false, false, size: 90);
                      },
                      onStart: (val) =>
                          _onGimbalStickChanged(val, true, false, size: 90),
                      onEnd: (val) =>
                          _onGimbalStickChanged(val, false, true, size: 90),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 功能按钮（弹窗）+ 对讲
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
                onPressed: _openActionSheet,
                tooltip: '摄像头功能',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C2E),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.stop_circle, color: Color(0xFFFF453A)),
                onPressed: _emergencyStop,
                tooltip: '急停',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF2C2C2E),
                ),
              ),
              const Spacer(),
              const VoiceButton(),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  /// 竖屏: D-Pad + 快捷栏（降级布局）
  Widget _buildPortrait() {
    return Column(
      children: [
        // 顶部：返回 + 功能按钮 + 急停
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                onPressed: () {
                  ref.read(connectionManagerProvider.notifier).sendMotionStop();
                  Navigator.of(context).pop();
                },
                tooltip: '返回',
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined, color: Colors.white, size: 20),
                onPressed: _openActionSheet,
                tooltip: '摄像头功能',
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.stop_circle, color: Color(0xFFFF453A), size: 20),
                onPressed: _emergencyStop,
                tooltip: '急停',
              ),
            ],
          ),
        ),
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
                    onPress: () => _motion.value = _motion.value.copyWith(vy: 0.6),
                    onRelease: () => _motion.value = _motion.value.copyWith(vy: 0),
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
                    onPress: () => _motion.value = _motion.value.copyWith(vy: -0.6),
                    onRelease: () => _motion.value = _motion.value.copyWith(vy: 0),
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
                    onPress: () => _motion.value = _motion.value.copyWith(vz: 2.5),
                    onRelease: () => _motion.value = _motion.value.copyWith(vz: 0),
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
                    onPress: () => _motion.value = _motion.value.copyWith(vz: -2.5),
                    onRelease: () => _motion.value = _motion.value.copyWith(vz: 0),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        const VoiceButton(),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// WebRTC 状态胶囊
class _WebRtcBadge extends StatelessWidget {
  final WebRtcState state;
  const _WebRtcBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      WebRtcState.connected => (const Color(0xFF34C759), '视频'),
      WebRtcState.connecting => (const Color(0xFFFF9500), '连接中'),
      WebRtcState.failed => (const Color(0xFFFF453A), '失败'),
      WebRtcState.disconnected => (const Color(0xFF8E8E93), '断开'),
      WebRtcState.idle => (const Color(0xFF8E8E93), '未连接'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
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
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ],
      ),
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
  final double size;
  final void Function(JoystickValue val)? onChanged;
  final void Function(JoystickValue val)? onStart;
  final void Function(JoystickValue val)? onEnd;

  const JoystickWidget({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.horizontalOnly = false,
    this.size = 140,
    this.onChanged,
    this.onStart,
    this.onEnd,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  late final double _cx = widget.size / 2;
  late final double _cy = widget.size / 2;
  late final double _knobR = widget.size * 22 / 140;
  late final double _maxDist = widget.size * 55 / 140 - _knobR; // 最大移动距离

  late double _knobX = _cx;
  late double _knobY = _cy;

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
    widget.onEnd?.call(JoystickValue(x: _cx, y: _cy));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
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
                size: widget.size,
                color: widget.color,
                horizontalOnly: widget.horizontalOnly,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final double knobX;
  final double knobY;
  final double size;
  final Color color;
  final bool horizontalOnly;

  _JoystickPainter({
    required this.knobX,
    required this.knobY,
    required this.size,
    required this.color,
    this.horizontalOnly = false,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final cx = size / 2, cy = size / 2;
    final knobR = size * 22 / 140;
    final outerR = size * 55 / 140;

    // 外圈
    final outerPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), outerR, outerPaint);

    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(cx, cy), outerR, borderPaint);

    // 十字线
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(cx - outerR, cy),
      Offset(cx + outerR, cy),
      linePaint,
    );
    if (!horizontalOnly) {
      canvas.drawLine(
        Offset(cx, cy - outerR),
        Offset(cx, cy + outerR),
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
      knobX != oldDelegate.knobX ||
      knobY != oldDelegate.knobY ||
      size != oldDelegate.size;
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
