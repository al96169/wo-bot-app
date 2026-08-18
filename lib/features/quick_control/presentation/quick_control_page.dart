import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 快捷控制页 — 匹配 Pixso 5:2220
///
/// 音量进度条 + 6 个快捷操作按钮（3×2 网格）：
/// 寻找设备 / 手电 / 去充电 / 手动控制 / 省电模式 / 静音
class QuickControlPage extends ConsumerStatefulWidget {
  const QuickControlPage({super.key});
  @override
  ConsumerState<QuickControlPage> createState() => _QuickControlPageState();
}

class _QuickControlPageState extends ConsumerState<QuickControlPage> {
  bool _flashlight = false;
  bool _eco = false;
  bool _mute = false;

  // 寻找设备：二态 + 30s 倒计时（对齐 web-debug handleFind）
  static const int _findDuration = 30;
  bool _findActive = false;
  int _findRemaining = _findDuration;
  Timer? _findTimer;

  @override
  void dispose() {
    _findTimer?.cancel();
    super.dispose();
  }

  void _toggle(String action, bool value) {
    ref.read(connectionManagerProvider.notifier).sendDeviceControl(action, value);
    AppToast.show(value ? '已开启' : '已关闭', type: AppToastType.info);
  }

  /// 寻找设备 — 二态切换（再次点击取消），对齐 web-debug handleFind
  void _handleFind() {
    final manager = ref.read(connectionManagerProvider.notifier);
    if (_findActive) {
      // 寻找中 → 手动停止
      setState(() {
        _findActive = false;
        _findRemaining = _findDuration;
      });
      _findTimer?.cancel();
      _findTimer = null;
      manager.sendDeviceControl('find_device', false);
      AppToast.show('已停止寻找设备', type: AppToastType.info);
    } else {
      // 空闲 → 开始寻找
      setState(() {
        _findActive = true;
        _findRemaining = _findDuration;
      });
      manager.sendDeviceControl('find_device', true);
      AppToast.show('正在寻找设备...', type: AppToastType.info);
      // 30s 倒计时（服务端到时自动停止，前端仅复位 UI）
      _findTimer?.cancel();
      _findTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _findRemaining--);
        if (_findRemaining <= 0) {
          _findTimer?.cancel();
          _findTimer = null;
          setState(() {
            _findActive = false;
            _findRemaining = _findDuration;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final data = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    final volume = data.music.volume;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            FeatureStatusBar(title: '快捷操作'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                child: Column(
                  children: [
                    // 音量卡 (Pixso 5:2540, 398×117)
                    _VolumeCard(
                      volume: volume,
                      onChanged: (v) {
                        manager.sendMusicVolume(v);
                        data.music.volume = v;
                        data.notify();
                      },
                    ),
                    const SizedBox(height: 10),
                    // 快捷按钮卡 (Pixso 5:2223, 398×237)
                    _QuickGrid(
                      flashlight: _flashlight,
                      eco: _eco,
                      mute: _mute,
                      findActive: _findActive,
                      findRemaining: _findRemaining,
                      onFlashlight: (v) {
                        setState(() => _flashlight = v);
                        _toggle('flashlight', v);
                      },
                      onEco: (v) {
                        setState(() => _eco = v);
                        _toggle('eco', v);
                      },
                      onMute: (v) {
                        setState(() => _mute = v);
                        _toggle('mute', v);
                      },
                      onCharge: () {
                        manager.sendDeviceControl('charge', true);
                        AppToast.show('已发送充电指令', type: AppToastType.info);
                      },
                      onFind: _handleFind,
                      onRemote: () {
                        AppToast.show('手动控制请前往遥控页', type: AppToastType.info);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 音量卡 — 匹配 Pixso 5:2540（白底圆角15 + 灰色圆角30 进度底 + 白色圆角30 进度条）
class _VolumeCard extends StatelessWidget {
  final int volume;
  final ValueChanged<int> onChanged;
  const _VolumeCard({required this.volume, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 117,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '音量',
            style: TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
          ),
          const Spacer(),
          // 进度条: 灰底圆角30 + 白内条 (Pixso 5:2544/5:2546)
          Container(
            height: 60,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF9E9E9E),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              children: [
                Container(
                  width: (56 / 100) * volume, // 比例占位
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(27),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 快捷按钮网格 — 匹配 Pixso 5:2223 (3×2, 每格 99.5×110)
class _QuickGrid extends StatelessWidget {
  final bool flashlight, eco, mute;
  final bool findActive;
  final int findRemaining;
  final ValueChanged<bool> onFlashlight, onEco, onMute;
  final VoidCallback onCharge, onFind, onRemote;

  const _QuickGrid({
    required this.flashlight,
    required this.eco,
    required this.mute,
    required this.findActive,
    required this.findRemaining,
    required this.onFlashlight,
    required this.onEco,
    required this.onMute,
    required this.onCharge,
    required this.onFind,
    required this.onRemote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 0,
        crossAxisSpacing: 0,
        childAspectRatio: 99.5 / 110,
        children: [
          // 寻找设备：二态 + 倒计时标签（对齐 web-debug）
          _QuickButton(
            icon: Icons.wifi_tethering,
            label: findActive ? '停止 ${findRemaining}s' : '寻找设备',
            active: findActive,
            onTap: onFind,
          ),
          _QuickButton(icon: Icons.lightbulb_outline, label: '手电', active: flashlight, onTap: () => onFlashlight(!flashlight)),
          _QuickButton(icon: Icons.power_settings_new, label: '去充电', onTap: onCharge),
          _QuickButton(icon: Icons.videogame_asset_outlined, label: '手动控制', onTap: onRemote),
          _QuickButton(icon: Icons.battery_charging_full, label: '省电模式', active: eco, onTap: () => onEco(!eco)),
          _QuickButton(icon: mute ? Icons.volume_off : Icons.volume_up, label: '静音', active: mute, onTap: () => onMute(!mute)),
        ],
      ),
    );
  }
}

/// 快捷按钮 — 匹配 Pixso 5:2434 (99.5×110, 图标50×50 + 标签14sp)
class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _QuickButton({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF0256FF) : const Color(0xFF232222);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 69.5,
            height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? const Color(0x1A0256FF) : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, size: 50, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF232222),
            ),
          ),
        ],
      ),
    );
  }
}
