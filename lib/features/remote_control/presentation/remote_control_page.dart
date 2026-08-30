import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/network/webrtc_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import 'widgets/camera_action_sheet.dart';
import 'widgets/camera_view.dart';
import 'widgets/remote_drawer.dart';
import 'widgets/voice_button.dart';
import '../../gallery/presentation/gallery_page.dart';

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
  Timer? _webrtcRetryTimer;

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

  // WebRTC 状态
  WebRtcState _webrtcState = WebRtcState.idle;
  MediaStream? _stream0; // 左主摄
  MediaStream? _stream1; // 右副摄
  bool _cameraLeftOn = false;
  bool _cameraRightOn = false;

  /// 副摄画面实际宽高比（默认 4:3，首帧后按真实分辨率更新 → PiP 无黑边）
  double _subAspect = 4 / 3;

  /// 云台拖动期间 50ms 续发 move_update 的定时器
  Timer? _gimbalUpdateTimer;

  /// 双击小画面交换主/副画面
  bool _camsSwapped = false;

  @override
  void initState() {
    super.initState();
    // 遥控页强制横屏 + 沉浸式全屏（隐藏状态栏/导航栏，任务栏不再遮挡画面）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 50ms 运动发送循环 — 匹配 web-debug
    _motionTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _sendMergedMotion(),
    );
    // 立即建立 WebRTC + 启动摄像头（并行，无等待）
    _initWebRtc();
    // 15s 未连接则自动重试（offer/answer 可能因信令时序丢失）
    _webrtcRetryTimer = Timer(
      const Duration(seconds: 15),
      _retryWebRtcIfNeeded,
    );
  }

  @override
  void dispose() {
    _motionTimer?.cancel();
    _webrtcRetryTimer?.cancel();
    _gimbalUpdateTimer?.cancel();
    _moveStick.dispose();
    _yawStick.dispose();
    _gimbalStick.dispose();
    _motion.dispose();
    // 恢复竖屏（App 其他页面为竖屏设计）+ 恢复系统 UI（状态栏/导航栏）
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 停止运动并断开 WebRTC
    try {
      ref.read(connectionManagerProvider.notifier).sendMotionStop();
      ref.read(connectionManagerProvider.notifier).webrtc.close();
    } catch (_) {}
    super.dispose();
  }

  /// 15s 未连接则重试建立 WebRTC（web-debug 有媒体超时重试，此处对齐）
  void _retryWebRtcIfNeeded() {
    if (!mounted) return;
    final manager = ref.read(connectionManagerProvider.notifier);
    // 云端模式（信令 DC 已通）由 SignalClient 管理，不做局域网重试；
    // signal 存在但未连接（云端连不上）不算云端模式，走局域网重试。
    if (_cloudModeActive(manager)) return;
    final webrtc = manager.webrtc;
    if (webrtc.state != WebRtcState.connected &&
        webrtc.state != WebRtcState.failed) {
      debugPrint('[Remote] WebRTC 15s 未连接，自动重试');
      manager.startWebRtc();
      _webrtcRetryTimer = Timer(
        const Duration(seconds: 15),
        _retryWebRtcIfNeeded,
      );
    }
  }

  /// 云端模式判定：signal 存在且 DC 已通（连接成功才算，失败残留不算）
  bool _cloudModeActive(ConnectionManager manager) =>
      manager.signal != null && manager.signal!.isConnected;

  /// 立即建立 WebRTC（视频 + DataChannel），同时并行启动摄像头（无等待）
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
    // 云端远控：信令 DC 已通 → 视频流由 SignalClient 提供，不再启动局域网 WebRTC
    // 注意：signal 存在但未连接（云端连不上）不是云端模式，走局域网 WebRTC
    if (_cloudModeActive(manager)) {
      debugPrint('[Remote] 云端模式：视频流走信令，跳过局域网 WebRTC');
      // 绑定回调后立即读取已缓存的视频流（视频轨可能在进入遥控页前已到达）
      final cached = manager.signal?.videoStreams;
      if (cached != null && cached.isNotEmpty) {
        setState(() {
          _stream0 = cached[0];
          _stream1 = cached[1];
        });
      }
      _startCamerasImmediate();
      return;
    }
    // 并行：先发 WebRTC offer（信令+ICE 需 1-2s，期间摄像头 pipeline 同步就绪）
    manager.startWebRtc();
    // 直连模式：读取已缓存的视频流（可能连接阶段已到达）
    if (manager.webrtc.videoStream0 != null ||
        manager.webrtc.videoStream1 != null) {
      setState(() {
        _stream0 = manager.webrtc.videoStream0;
        _stream1 = manager.webrtc.videoStream1;
      });
    }
    _startCamerasImmediate();
  }

  /// 是否有真实副摄（排除克隆/共享摄像头，对齐 web-debug cameras.length > 1）
  /// 机器人端单物理摄像头时会克隆出 "(shared)" 逻辑摄像头，不能算真实副摄
  bool _hasRealSecondaryCamera(List<CameraInfo> cameras) {
    if (cameras.length < 2) return false;
    return cameras.any((c) => !c.name.contains('(shared)'));
  }

  /// 立即启动摄像头：列表已到用真实 id，未到先兜底 0/1 稍后补
  void _startCamerasImmediate() {
    final store = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    if (store.cameras.isNotEmpty) {
      debugPrint(
        '[Remote] 启动摄像头: ${store.cameras.map((c) => '${c.cameraId}:${c.name}').toList()}',
      );
      for (final c in store.cameras) {
        manager.sendCamera('start', c.cameraId);
      }
      setState(() {
        _cameraLeftOn = store.cameras.isNotEmpty;
        _cameraRightOn = _hasRealSecondaryCamera(store.cameras);
      });
    } else {
      // 列表未到：兜底启动 0/1，稍后按真实列表补启
      debugPrint('[Remote] 摄像头列表未到，兜底 start 0/1');
      manager.sendCamera('start', 0);
      manager.sendCamera('start', 1);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        final s2 = ref.read(robotDataProvider.notifier);
        if (s2.cameras.isNotEmpty) {
          for (final c in s2.cameras) {
            manager.sendCamera('start', c.cameraId);
          }
          setState(() {
            _cameraLeftOn = s2.cameras.isNotEmpty;
            _cameraRightOn = _hasRealSecondaryCamera(s2.cameras);
          });
        }
      });
    }
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
  double _speedFromStick(
    JoystickValue stick,
    String axis, {
    double size = 140,
  }) {
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
    // 对齐 web-debug: raw^0.7（0.2→0.32, 0.5→0.62, 1.0→1.0），中心更灵敏
    return raw.sign * pow(raw.abs(), 0.7).toDouble();
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

  void _onGimbalStickChanged(
    JoystickValue val,
    bool isStart,
    bool isEnd, {
    double size = 140,
  }) {
    final manager = ref.read(connectionManagerProvider.notifier);
    if (isStart) {
      // 对齐 web-debug：拖动期间 50ms 周期续发 move_update（保持速度 + 喂活服务端看门狗）
      _gimbalUpdateTimer?.cancel();
      _gimbalUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (
        _,
      ) {
        if (!mounted || !_gimbalStick.value.dragging) return;
        final spd = _gimbalSpeedFromStick(_gimbalStick.value, size: size);
        manager.sendGimbalMoveUpdate(spd.pan, spd.tilt);
      });
      final speed = _gimbalSpeedFromStick(val, size: size);
      manager.sendGimbalMoveBegin(speed.pan, speed.tilt);
    } else if (isEnd) {
      _gimbalUpdateTimer?.cancel();
      _gimbalUpdateTimer = null;
      manager.sendGimbalMoveEnd();
    } else {
      final speed = _gimbalSpeedFromStick(val, size: size);
      manager.sendGimbalMoveUpdate(speed.pan, speed.tilt);
    }
  }

  /// 双击小画面 ↔ 与主画面交换位置（互换两路流与开关状态）
  void _swapCameras() {
    setState(() {
      final s = _stream0;
      _stream0 = _stream1;
      _stream1 = s;
      final l = _cameraLeftOn;
      _cameraLeftOn = _cameraRightOn;
      _cameraRightOn = l;
      _camsSwapped = !_camsSwapped;
    });
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
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const GalleryPage()));
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
      // 全屏展示（横屏遥控，不留 SafeArea 边距）
      body: _buildLandscape(),
    );
  }

  /// 横屏主界面：主摄全屏 + 副摄 PiP + 4 摇杆叠加 + 功能弹窗 + 底部对讲
  Widget _buildLandscape() {
    ref.watch(robotDataProvider);
    // 连接状态变化（云端 DC 开/关）触发重建，徽标随之更新
    ref.watch(connectionManagerProvider);
    final store = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    final robotName =
        (manager.robotInfo?['name'] as String?) ??
        manager.currentDevice?.name ??
        '遥控';
    // 云台能力（features 含 gimbal；副摄无云台 → 副摄云台摇杆禁用，对齐 web-debug）
    final gimbalAvailable = manager.remoteFeatures.contains('gimbal');

    // 云端远控（信令 DC 已通）：徽标由信令连接派生；局域网：用 webrtc.state
    final badgeState = _cloudModeActive(manager)
        ? WebRtcState.connected
        : _webrtcState;

    // 画面分配：对齐 web-debug（左画面 = stream0/track0，摄像头开 id0）
    // 真机实测仅 track0(id0) 有 WebRTC 数据，track1(id1) 为空流 → 主画面必须用 track0
    final mainStream = _stream0;
    final subStream = _stream1;

    // 王者荣耀式布局：主摄全屏 + 副摄 PiP 小窗 + 半透明摇杆叠加画面 + 顶部透明浮层
    // 摇杆尺寸按可用空间自适应，避免小屏/高分屏溢出
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // 沉浸式全屏下系统栏隐藏，MediaQuery padding 可能为 0；边缘控件固定留出可点按边距
        const edge = 12.0;
        const statusBarH = 40.0;
        const stickBottom = 76.0; // 底部对讲/按钮区域高度
        const gapBetween = 4.0; // 上下摇杆间距
        const labelH = 16.0; // 标签行高（含间距）
        const subRatio = 0.55; // 云台小摇杆 = 主摇杆 * 0.55
        // 主摇杆：由可用列高反推（小摇杆在上 + 大摇杆在下 + 两行标签），顶部留 8px 防溢出
        final availCol = h - stickBottom - statusBarH - 8.0;
        var mainStick = (availCol - gapBetween - labelH * 2) / (1 + subRatio);
        if (mainStick > 200) mainStick = 200;
        if (mainStick < 80) mainStick = 80;
        if (mainStick > w * 0.24) mainStick = w * 0.24;
        final subStick = mainStick * subRatio;
        // 副摄 PiP 按画面实际比例展示（默认 4:3），无黑边
        final pipW = (w * 0.3).clamp(140, 240).toDouble();
        final pipH = pipW / _subAspect;

        return Stack(
          children: [
            // 主摄全屏
            Positioned.fill(
              child: CameraView(
                stream: mainStream,
                label: _camsSwapped ? '副摄' : '主摄',
                enabled: _cameraLeftOn,
                recording: store.isRecording,
              ),
            ),
            // 副摄 PiP 小窗（右上角，避开顶部浮层；按副摄实际画面比例 + Cover 无黑边）
            // 双击小画面 ↔ 与主画面交换位置
            // 仅当存在真实副摄（非克隆/共享摄像头）时显示，避免单摄时双画面同内容
            if (_cameraRightOn)
              Positioned(
                top: statusBarH + 6,
                right: edge,
                width: pipW,
                height: pipH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _swapCameras,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CameraView(
                          stream: subStream,
                          label: _camsSwapped ? '主摄' : '副摄',
                          enabled: _cameraRightOn,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          onVideoSize: (w, h) {
                            if (w > 0 && h > 0) {
                              final aspect = w / h;
                              if ((aspect - _subAspect).abs() > 0.01) {
                                setState(() => _subAspect = aspect);
                              }
                            }
                          },
                        ),
                      ),
                      // 双击交换提示
                      const Positioned(
                        right: 4,
                        bottom: 4,
                        child: Text(
                          '双击交换',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0x88FFFFFF),
                            shadows: [Shadow(blurRadius: 2)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 顶部透明浮层（覆盖在画面上）：☰ + 设备名 + WebRTC 状态 + 电量/WiFi
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusBarH,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(
                          Icons.menu,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                        tooltip: '菜单',
                      ),
                    ),
                    const SizedBox(width: 2),
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
                    _WebRtcBadge(state: badgeState),
                    const SizedBox(width: 10),
                    if (store.system.batteryLevel > 0 &&
                        store.system.batteryStatus != 'unknown' &&
                        store.system.batteryStatus != 'not_present') ...[
                      Icon(
                        store.system.batteryCharging
                            ? Icons.battery_charging_full
                            : Icons.battery_full,
                        size: 14,
                        color: Colors.white,
                      ),
                      Text(
                        ' ${store.system.batteryLevel.round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                        ),
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
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            // 左摇杆组：主摄云台（小）在上 + 平移（大）在下，叠加画面左下
            Positioned(
              left: edge,
              bottom: stickBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  JoystickWidget(
                    label: '主摄云台',
                    size: subStick,
                    color: Colors.teal,
                    enabled: gimbalAvailable,
                    onChanged: (val) {
                      _gimbalStick.value = val;
                      _onGimbalStickChanged(val, false, false, size: subStick);
                    },
                    onStart: (val) =>
                        _onGimbalStickChanged(val, true, false, size: subStick),
                    onEnd: (val) =>
                        _onGimbalStickChanged(val, false, true, size: subStick),
                  ),
                  const SizedBox(height: 4),
                  JoystickWidget(
                    label: '平移',
                    size: mainStick,
                    onChanged: (val) {
                      _moveStick.value = val;
                      _onMoveStickChanged(val);
                    },
                    onEnd: (_) => _onMoveStickEnd(),
                  ),
                ],
              ),
            ),
            // 右摇杆组：副摄云台（小，禁用）在上 + 偏航（大）在下，叠加画面右下
            Positioned(
              right: edge,
              bottom: stickBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  JoystickWidget(
                    label: '副摄云台',
                    size: subStick,
                    // 副摄无云台（对齐 web-debug 右云台不可用）
                    enabled: false,
                  ),
                  const SizedBox(height: 4),
                  JoystickWidget(
                    label: '偏航',
                    size: mainStick,
                    horizontalOnly: true,
                    onChanged: (val) {
                      _yawStick.value = val;
                      _onYawStickChanged(val);
                    },
                    onEnd: (_) => _onYawStickEnd(),
                  ),
                ],
              ),
            ),
            // 底部浮层：功能按钮（弹窗）+ 急停 + 对讲（底部留安全区，避免被手势条遮挡）
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _FloatingBtn(
                      icon: Icons.photo_camera_outlined,
                      onTap: _openActionSheet,
                      tooltip: '摄像头功能',
                    ),
                    const SizedBox(width: 8),
                    _FloatingBtn(
                      icon: Icons.stop_circle,
                      color: const Color(0xFFFF453A),
                      onTap: _emergencyStop,
                      tooltip: '急停',
                    ),
                    const Spacer(),
                    const VoiceButton(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
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

/// 底部悬浮按钮（半透明黑底）
class _FloatingBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _FloatingBtn({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.tooltip = '',
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: 20),
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(backgroundColor: const Color(0xAA2C2C2E)),
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
  final bool enabled;
  final void Function(JoystickValue val)? onChanged;
  final void Function(JoystickValue val)? onStart;
  final void Function(JoystickValue val)? onEnd;

  const JoystickWidget({
    super.key,
    required this.label,
    this.color = AppColors.primary,
    this.horizontalOnly = false,
    this.size = 140,
    this.enabled = true,
    this.onChanged,
    this.onStart,
    this.onEnd,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  late double _cx = widget.size / 2;
  late double _cy = widget.size / 2;
  late double _knobR = widget.size * 22 / 140;
  late double _maxDist = widget.size * 55 / 140 - _knobR; // 最大移动距离

  late double _knobX = _cx;
  late double _knobY = _cy;

  @override
  void didUpdateWidget(covariant JoystickWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 尺寸变化时更新中心与旋钮，避免偏移
    if (oldWidget.size != widget.size) {
      _cx = widget.size / 2;
      _cy = widget.size / 2;
      _knobR = widget.size * 22 / 140;
      _maxDist = widget.size * 55 / 140 - _knobR;
      _knobX = _cx;
      _knobY = _cy;
    }
  }

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
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.35,
        child: Column(
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
                onPanUpdate: (details) =>
                    _updateFromDetails(details.localPosition),
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
            const SizedBox(height: 2),
            Text(
              widget.enabled ? widget.label : '${widget.label}(不可用)',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
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
