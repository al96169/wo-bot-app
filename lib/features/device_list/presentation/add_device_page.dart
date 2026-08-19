import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/connection_manager.dart';
import '../../../core/network/device_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_device.dart';
import 'device_list_provider.dart';
import 'manual_add_page.dart';

/// 添加设备界面 (Pixso 1:3365) — 设备发现页
/// 结构：顶栏(返回+标题) → mDNS 发现设备列表 → 底部"手动添加"按钮
class AddDevicePage extends ConsumerStatefulWidget {
  const AddDevicePage({super.key});

  @override
  ConsumerState<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends ConsumerState<AddDevicePage> {
  @override
  void initState() {
    super.initState();
    // 进入页面即开始扫描
    Future.microtask(() => ref.read(deviceListProvider.notifier).startScan());
  }

  Future<void> _saveAndConnect(RobotDevice device) async {
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
  }

  void _openManualAdd() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ManualAddPage()));
  }

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(deviceListProvider);
    final discovered = discovery.valueOrNull ?? const <RobotDevice>[];
    final store = ref.watch(deviceStoreProvider);
    final savedEndpoints = store.devices
        .map((d) => '${d.ip}:${d.port}')
        .toSet();
    final newDevices = discovered
        .where((d) => !savedEndpoints.contains('${d.ip}:${d.port}'))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            // ---- 顶栏 74px (Pixso 1:3594) ----
            SizedBox(
              height: 74,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 15,
                ),
                child: Row(
                  children: [
                    // 返回按钮 44×44 无背景 (Pixso 1:3595/1:3211)
                    _BackButton(onTap: () => Navigator.of(context).pop()),
                    const SizedBox(width: 6),
                    // 标题 "添加设备" bold 19.6 (Pixso 1:3598)
                    const Text(
                      '添加设备',
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
            // ---- 发现设备列表 (Pixso 1:3370) ----
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(deviceListProvider.notifier).startScan(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 20),
                  children: [
                    // "持续搜索本地设备 ..." (Pixso 1:3490)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Center(
                        child: Text(
                          discovery.isLoading
                              ? '持续搜索本地设备 ...'
                              : '发现 ${newDevices.length} 个新设备',
                          style: const TextStyle(
                            fontSize: 15.6,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ),
                    if (discovery.isLoading)
                      const _DiscoverCardPlaceholder()
                    else if (newDevices.isEmpty)
                      const _EmptyDiscovery()
                    else
                      ...newDevices.map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DiscoverCard(
                            device: device,
                            onTap: () => _saveAndConnect(device),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // ---- 底部按钮区 (Pixso 1:3494) ----
            SizedBox(
              height: 105,
              child: Center(
                child: _PillButton(
                  label: '手动添加',
                  filled: false,
                  onTap: _openManualAdd,
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

/// 发现设备卡片 — 复用 Pixso Component_1_2980 卡片样式
class _DiscoverCard extends StatelessWidget {
  final RobotDevice device;
  final VoidCallback onTap;
  const _DiscoverCard({required this.device, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFEEEEEE), width: .5),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: 设备名 (Pixso 1:2855, 15.6 bold)
              Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.6,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF000000),
                ),
              ),
              const SizedBox(height: 10),
              // Row 2: 基础状态 — 信号强度 | 电量 | 延迟 (Pixso 1:2907)
              _StatusRow(device: device),
              const SizedBox(height: 10),
              // Row 3: IP 和端口 (Pixso 1:2950, 11.6sp 注释文本)
              Text(
                '${device.ip}:${device.port}',
                style: const TextStyle(
                  fontSize: 11.6,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 基础状态行 — 信号强度 | 电量 | 延迟 (Pixso 1:2907 / 1:2866 / 1:2909)
class _StatusRow extends StatelessWidget {
  final RobotDevice device;
  const _StatusRow({required this.device});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11.6, color: Color(0xFF6750A4));
    const sep = TextStyle(fontSize: 11.6, color: Color(0xFF000000));
    final signal = device.signalDbm != null
        ? '信号强度 ${device.signalDbm}'
        : '信号强度 --';
    final battery = device.batteryLevel != null
        ? '电量 ${device.batteryLevel}%'
        : '电量 --';
    final latency = device.latencyMs > 0 ? '延迟 ${device.latencyMs}' : '延迟 --';
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: signal),
          const TextSpan(text: ' | ', style: sep),
          TextSpan(text: battery),
          const TextSpan(text: ' ▎', style: sep),
          TextSpan(text: latency),
        ],
      ),
    );
  }
}

/// 发现中占位卡
class _DiscoverCardPlaceholder extends StatelessWidget {
  const _DiscoverCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: .5),
      ),
      child: const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

/// 未发现新设备
class _EmptyDiscovery extends StatelessWidget {
  const _EmptyDiscovery();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: .5),
      ),
      child: const Column(
        children: [
          Icon(Icons.radar, size: 34, color: Color(0xFFB6A7D8)),
          SizedBox(height: 10),
          Text(
            '未发现新设备',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 5),
          Text(
            '请确认手机和机器人处于同一局域网，下拉可重新扫描',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}

/// 胶囊按钮 (Pixso 1:3627) — filled=true 蓝底白字，false 白底紫字
class _PillButton extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _PillButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? const Color(0xFF0256FF) : Colors.white,
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
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: filled ? null : Border.all(color: const Color(0xFFE5E5E5)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15.6,
              color: filled ? Colors.white : const Color(0xFF6750A4),
            ),
          ),
        ),
      ),
    );
  }
}
