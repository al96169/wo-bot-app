import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connection_manager.dart';
import '../../../core/network/device_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_device.dart';

/// 手动添加设备界面 (Pixso 1:3544)
/// 结构：顶栏(返回+标题) → 表单(机器人名称+机器人IP) → 底部"添加"按钮
class ManualAddPage extends ConsumerStatefulWidget {
  const ManualAddPage({super.key});

  @override
  ConsumerState<ManualAddPage> createState() => _ManualAddPageState();
}

class _ManualAddPageState extends ConsumerState<ManualAddPage> {
  final _nameC = TextEditingController();
  final _ipC = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _nameC.dispose();
    _ipC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    final name = _nameC.text.trim();
    final ip = _ipC.text.trim();
    final device = RobotDevice(
      id: 'manual_$ip',
      name: name.isNotEmpty ? name : '手动设备',
      ip: ip,
      port: 8765,
      serviceName: 'manual',
    );
    setState(() => _submitting = true);
    await ref.read(deviceStoreProvider.notifier).addDevice(device);
    if (!mounted) return;
    AppToast.show('已保存 ${device.name}', type: AppToastType.success);
    await ref.read(deviceStoreProvider.notifier).setCurrentDevice(device);
    try {
      await ref
          .read(connectionManagerProvider.notifier)
          .connectToDevice(device);
    } catch (error) {
      if (!mounted) return;
      AppToast.show('连接失败：$error', type: AppToastType.error);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            // ---- 顶栏 74px (Pixso 1:3604) ----
            SizedBox(
              height: 74,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 15,
                ),
                child: Row(
                  children: [
                    // 返回按钮 44×44 无背景 (Pixso 1:3605/1:3211)
                    _BackButton(onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 6),
                    // 标题 "手动添加设备" bold 19.6 (Pixso 1:3607)
                    const Text(
                      '手动添加设备',
                      style: TextStyle(
                        fontSize: 19.6,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ---- 表单区 (Pixso 1:3545) ----
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 机器人名称 (Pixso 1:3615)
                      const Padding(
                        padding: EdgeInsets.only(left: 10, top: 15, bottom: 10),
                        child: Text(
                          '机器人名称',
                          style: TextStyle(
                            fontSize: 15.6,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                      _FormField(
                        controller: _nameC,
                        hint: '请输入',
                        validator: (_) => null,
                      ),
                      const SizedBox(height: 10),
                      // 机器人IP (Pixso 1:3623)
                      const Padding(
                        padding: EdgeInsets.only(left: 10, top: 15, bottom: 10),
                        child: Text(
                          '机器人IP',
                          style: TextStyle(
                            fontSize: 15.6,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                      _FormField(
                        controller: _ipC,
                        hint: '192.168.1.100',
                        validator: (value) {
                          final input = value?.trim() ?? '';
                          final ipv4 = RegExp(
                            r'^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$',
                          );
                          if (input.isEmpty) return '请输入 IP 地址';
                          if (!ipv4.hasMatch(input) && input != 'localhost') {
                            return '请输入有效的 IPv4 地址';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // ---- 底部按钮区 (Pixso 1:3550) ----
            SizedBox(
              height: 105,
              child: Center(
                child: _PillButton(
                  label: '添加',
                  onTap: _submitting ? null : _submit,
                  submitting: _submitting,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 返回按钮 — 44×44 无背景紫色 "<" (Pixso 1:3211)
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '返回',
      child: InkWell(
        onTap: onTap,
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
    );
  }
}

/// 表单输入框 (Pixso 1:3614) — 白底、边框 #D8D8D8、圆角15、高38
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;
  const _FormField({
    required this.controller,
    required this.hint,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      style: const TextStyle(fontSize: 15.6, color: Color(0xFF1C1C1E)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 15.6, color: Color(0xFF8E8E93)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFD8D8D8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF6750A4), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFB00020)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFB00020), width: 1.5),
        ),
      ),
    );
  }
}

/// 蓝色胶囊按钮 (Pixso 1:3628) — 蓝底 #0256FF 白字、圆角21、阴影
class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool submitting;
  const _PillButton({
    required this.label,
    required this.onTap,
    this.submitting = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0256FF),
      borderRadius: BorderRadius.circular(21),
      elevation: 2,
      shadowColor: const Color(0x40000000),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          width: 124,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(21)),
          child: submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(fontSize: 15.6, color: Colors.white),
                ),
        ),
      ),
    );
  }
}
