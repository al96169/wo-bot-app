import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/connection_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/app_toast.dart';

/// 快速操作状态 — 匹配 web-debug appStore.toggleStates
class QuickActionState extends StateNotifier<QuickActionData> {
  QuickActionState() : super(const QuickActionData());

  void toggleFlashlight(bool v) {
    state = state.copyWith(flashlight: v);
  }

  void toggleMute(bool v) {
    state = state.copyWith(mute: v);
  }

  void toggleEco(bool v) {
    state = state.copyWith(eco: v);
  }

  void setVolume(int v) {
    state = state.copyWith(volume: v);
  }
}

class QuickActionData {
  final bool flashlight;
  final bool mute;
  final bool eco;
  final int volume;

  const QuickActionData({
    this.flashlight = false,
    this.mute = false,
    this.eco = false,
    this.volume = 75,
  });

  QuickActionData copyWith({
    bool? flashlight,
    bool? mute,
    bool? eco,
    int? volume,
  }) {
    return QuickActionData(
      flashlight: flashlight ?? this.flashlight,
      mute: mute ?? this.mute,
      eco: eco ?? this.eco,
      volume: volume ?? this.volume,
    );
  }
}

final quickActionProvider =
    StateNotifierProvider<QuickActionState, QuickActionData>(
      (ref) => QuickActionState(),
    );

/// 快捷操作栏 — 匹配 web-debug QuickActionsView.vue
///
/// 6 个操作: 寻找设备、手电、去充电、静音、省电模式、急停
class QuickActionBar extends ConsumerStatefulWidget {
  const QuickActionBar({super.key});

  @override
  ConsumerState<QuickActionBar> createState() => _QuickActionBarState();
}

class _QuickActionBarState extends ConsumerState<QuickActionBar> {
  Timer? _findDeviceTimer;
  int _findCountdown = 0;
  Timer? _volumeDebounce;

  @override
  void dispose() {
    _findDeviceTimer?.cancel();
    _volumeDebounce?.cancel();
    super.dispose();
  }

  void _toggleFindDevice() {
    final manager = ref.read(connectionManagerProvider.notifier);
    if (_findCountdown > 0) {
      // 停止寻找
      _findDeviceTimer?.cancel();
      setState(() => _findCountdown = 0);
      manager.sendDeviceControl('find_device', false);
    } else {
      // 开始寻找
      setState(() => _findCountdown = 30);
      manager.sendDeviceControl('find_device', true);
      _findDeviceTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _findCountdown--);
        if (_findCountdown <= 0) {
          t.cancel();
          manager.sendDeviceControl('find_device', false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final qaState = ref.watch(quickActionProvider);
    final manager = ref.read(connectionManagerProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          // 寻找设备
          _ActionButton(
            icon: Icons.my_location,
            label: _findCountdown > 0 ? '寻找(${_findCountdown}s)' : '寻找设备',
            active: _findCountdown > 0,
            activeColor: AppColors.primary,
            onTap: _toggleFindDevice,
          ),
          // 手电
          _ActionButton(
            icon: Icons.flashlight_on,
            label: '手电',
            active: qaState.flashlight,
            activeColor: Colors.amber,
            onTap: () {
              final next = !qaState.flashlight;
              ref.read(quickActionProvider.notifier).toggleFlashlight(next);
              manager.sendDeviceControl('flashlight', next);
            },
          ),
          // 去充电
          _ActionButton(
            icon: Icons.battery_charging_full,
            label: '去充电',
            active: false,
            activeColor: Colors.green,
            onTap: () {
              manager.sendDeviceControl('charge', true);
              AppToast.show('已发送充电指令');
            },
          ),
          // 静音
          _ActionButton(
            icon: qaState.mute ? Icons.volume_off : Icons.volume_up,
            label: qaState.mute ? '已静音' : '静音',
            active: qaState.mute,
            activeColor: Colors.orange,
            onTap: () {
              final next = !qaState.mute;
              ref.read(quickActionProvider.notifier).toggleMute(next);
              manager.sendDeviceControl('mute', next);
            },
          ),
          // 省电模式
          _ActionButton(
            icon: Icons.eco,
            label: qaState.eco ? '省电中' : '省电模式',
            active: qaState.eco,
            activeColor: Colors.teal,
            onTap: () {
              final next = !qaState.eco;
              ref.read(quickActionProvider.notifier).toggleEco(next);
              manager.sendDeviceControl('eco', next);
            },
          ),
          // 急停
          _ActionButton(
            icon: Icons.emergency,
            label: '急停',
            active: false,
            activeColor: AppColors.error,
            onTap: () {
              manager.sendEmergencyStop();
              AppToast.show('⚠️ 急停已触发', type: AppToastType.error);
            },
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : AppColors.textSecondary;
    return Material(
      color: active ? activeColor.withValues(alpha: 0.15) : AppColors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 10, color: color),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
