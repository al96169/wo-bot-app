import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/device_store.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/widgets/feature_status_bar.dart';
import 'wifi_manager_page.dart';

/// 设置页 — 匹配 Pixso 5:3864
///
/// WIFI管理 / 蓝牙 / 软件版本管理 / 省电模式阈值(stepper) /
/// 自动充电阈值(stepper) / 重启 / 关机 / 删除此机器人 / 解除绑定
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int _ecoThreshold = 30;
  int _chargeThreshold = 30;
  /// 调试模式（持久化，控制 AppLogger.debug 输出）
  bool _debugMode = false;

  static const _keyDebugMode = 'wobot_debug_mode';

  @override
  void initState() {
    super.initState();
    _loadDebugMode();
  }

  Future<void> _loadDebugMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _debugMode = prefs.getBool(_keyDebugMode) ?? false;
    });
  }

  Future<void> _toggleDebugMode(bool v) async {
    setState(() => _debugMode = v);
    AppLogger.setDebugMode(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDebugMode, v);
    AppToast.show(v ? '调试模式已开启' : '调试模式已关闭');
  }

  void _sendSystemAction(String action, String name) {
    ref.read(connectionManagerProvider.notifier).sendSystemAction(action);
    AppToast.show('已发送$name指令');
  }

  void _setPowerPolicy(String mode, int threshold) {
    ref.read(connectionManagerProvider.notifier).sendSetPowerPolicy({
      'mode': mode,
      'threshold': threshold,
    });
    AppToast.show('已保存$mode阈值: $threshold%', type: AppToastType.success);
  }

  /// 主题模式选择弹窗（对齐 web-debug SettingsView 下拉）
  Future<void> _pickTheme() async {
    final controller = ref.read(themeControllerProvider.notifier);
    final current = controller.mode;
    final selected = await showDialog<AppThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('主题'),
        children: AppThemeMode.values.map((m) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(context, m),
            child: Row(
              children: [
                Icon(
                  m == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: m == current
                      ? const Color(0xFF6750A4)
                      : const Color(0xFFC7C7CC),
                ),
                const SizedBox(width: 10),
                Text(m.label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (selected != null) {
      await controller.setMode(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '设置'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: const Color(0xFFEEEEEE),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      // WIFI 管理 (Pixso 5:4246)
                      _NavRow(
                        label: 'WIFI管理',
                        value: '添加要连接的wifi热点',
                        onTap: () => WifiManagerPage.open(context),
                      ),
                      _Divider(),
                      // 蓝牙 (Pixso 5:4260)
                      _NavRow(
                        label: '蓝牙',
                        value: '待接入',
                        onTap: () => AppToast.show('蓝牙功能待接入'),
                      ),
                      _Divider(),
                      // 主题（批次 7，对齐 web-debug SettingsView 主题切换）
                      _NavRow(
                        label: '主题',
                        value: ref
                            .watch(themeControllerProvider.notifier)
                            .mode
                            .label,
                        onTap: _pickTheme,
                      ),
                      _Divider(),
                      // 调试模式（对齐 web-debug Debug 模式开关）
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                        ),
                        title: const Text(
                          '调试模式',
                          style: TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
                        ),
                        subtitle: const Text(
                          '开启后在日志输出 DEBUG 级别信息',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                        ),
                        value: _debugMode,
                        activeTrackColor: const Color(0xFF6750A4),
                        onChanged: _toggleDebugMode,
                      ),
                      _Divider(),
                      // 省电模式阈值 (Pixso 5:4254)
                      _StepperRow(
                        label: '省电模式阈值',
                        value: _ecoThreshold,
                        onChanged: (v) => setState(() => _ecoThreshold = v),
                        onSave: () => _setPowerPolicy('eco', _ecoThreshold),
                      ),
                      _Divider(),
                      // 自动充电阈值 (Pixso 5:4251)
                      _StepperRow(
                        label: '自动充电阈值',
                        value: _chargeThreshold,
                        onChanged: (v) => setState(() => _chargeThreshold = v),
                        onSave: () =>
                            _setPowerPolicy('charge', _chargeThreshold),
                      ),
                      _Divider(),
                      // 重启 (Pixso 5:4329)
                      _SystemRow(
                        label: '重启',
                        icon: Icons.restart_alt,
                        onTap: () => _confirmSystemAction(
                          '重启',
                          '确定要重启机器人吗？此操作将断开当前连接。',
                          'reboot',
                        ),
                      ),
                      _Divider(),
                      // 关机 (Pixso 5:4347)
                      _SystemRow(
                        label: '关机',
                        icon: Icons.power_settings_new,
                        onTap: () => _confirmSystemAction(
                          '关机',
                          '确定要关闭机器人吗？',
                          'shutdown',
                        ),
                      ),
                      _Divider(),
                      // 删除此机器人 + 解除绑定 (Pixso 5:4360)
                      _NavRow(
                        label: '删除此机器人',
                        value: '解除绑定',
                        onTap: _confirmUnbind,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSystemAction(
    String name,
    String message,
    String action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok == true) _sendSystemAction(action, name);
  }

  Future<void> _confirmUnbind() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除此机器人'),
        content: const Text('确定要删除此机器人并解除绑定吗？此操作将删除设备的连接记录，并解除与当前客户端的绑定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final manager = ref.read(connectionManagerProvider.notifier);
    final store = ref.read(deviceStoreProvider);
    final current = store.currentDevice;
    // 1. 断开当前连接
    manager.disconnect();
    // 2. 通知机器人端移除本客户端绑定（对齐 web-debug forget：sendBindRemoveAll）
    manager.sendBindRemoveAll();
    // 3. 删除本地保存记录（若已连接过某设备）
    if (current != null) {
      await ref.read(deviceStoreProvider.notifier).removeDevice(current.id);
    }
    if (!mounted) return;
    AppToast.show('已删除此机器人', type: AppToastType.success);
    Navigator.of(context).pop();
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFD8D8D8));
}

/// 导航行 — label + value + 箭头 (Pixso 5:4246, 49px)
class _NavRow extends StatelessWidget {
  final String label, value;
  final VoidCallback onTap;
  const _NavRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 49,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
              ),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(fontSize: 14, color: Color(0xFF898989)),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFC7C7CC),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 系统操作行 — 右侧圆形图标按钮 (Pixso 5:4329, 60px)
class _SystemRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SystemRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
              ),
              const Spacer(),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, size: 18, color: const Color(0xFF0256FF)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 阈值行 — stepper 控件 (Pixso 5:4254, 62px)
class _StepperRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final VoidCallback onSave;
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
            ),
            const Spacer(),
            // stepper (Pixso 5:4309, 124×32)
            Container(
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
              ),
              child: Row(
                children: [
                  _StepBtn(
                    icon: Icons.remove,
                    onTap: () => onChanged((value - 5).clamp(0, 100)),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '$value%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ),
                  _StepBtn(
                    icon: Icons.add,
                    onTap: () => onChanged((value + 5).clamp(0, 100)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onSave, child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(icon, size: 16, color: const Color(0xFF0256FF)),
      ),
    );
  }
}
