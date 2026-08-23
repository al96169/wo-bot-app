import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 状态页 — 匹配 Pixso 5:2869
///
/// 1. 网络/电池状态卡（3 列: 蜂窝/WiFi/电池 + CPU/内存/硬盘）
/// 2. 设备状态列表（电池温度/电量/预计可用/IP/蓝牙/Mac/地理位置/卫星/运行时间）
/// 3. 环境状态（温度/湿度/燃气/光照）
/// 4. 子系统列表（音频/传感器/外设/运动/电源/摄像头/GPS）
class RobotStatusPage extends ConsumerWidget {
  const RobotStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(robotDataProvider);
    final data = ref.read(robotDataProvider.notifier);
    final system = data.system;
    final manager = ref.read(connectionManagerProvider.notifier);
    final robotInfo = manager.robotInfo;
    final model = system.model ?? robotInfo?['model'] as String?;
    final version = system.version ?? robotInfo?['version'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '状态'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 网络/电池状态卡
                    _buildTopStatusCard(system),
                    const SizedBox(height: 10),
                    // 2. 设备状态列表
                    _StatusCard(
                      title: '设备状态',
                      children: [
                        _StatusRow(
                          label: 'CPU温度',
                          value: system.cpuTemp != null
                              ? '${system.cpuTemp!.toStringAsFixed(0)}°C'
                              : '--',
                        ),
                        _StatusRow(
                          label: '电池电量',
                          value: system.batteryLevel > 0
                              ? '${system.batteryLevel.toStringAsFixed(0)}%'
                              : '--',
                        ),
                        _StatusRow(
                          label: '电池状态',
                          value: switch (system.batteryStatus) {
                            'charging' => '充电中',
                            'discharging' => '放电中',
                            'not_present' => '无电池',
                            _ => '未知',
                          },
                        ),
                        _StatusRow(
                          label: '预计可用',
                          value: system.batteryEstimatedMinutes != null
                              ? '约${system.batteryEstimatedMinutes}分钟'
                              : '--',
                        ),
                        _StatusRow(label: 'IP地址', value: system.ip ?? '--'),
                        _StatusRow(
                          label: '主机名',
                          value: system.hostname ?? '--',
                        ),
                        _StatusRow(
                          label: '本次运行',
                          value: _uptime(system.uptime),
                        ),
                        if (system.totalRuntime > 0)
                          _StatusRow(
                            label: '累计运行',
                            value: _uptime(system.totalRuntime),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 3. 设备信息（型号/版本来自 connected 握手 robot_info；系统信息来自 status.device_info）
                    _StatusCard(
                      title: '设备信息',
                      children: [
                        if (model != null)
                          _StatusRow(label: '型号', value: model),
                        if (version != null)
                          _StatusRow(label: '版本', value: version),
                        if (system.os != null)
                          _StatusRow(label: '系统', value: system.os!),
                        if (system.kernel != null)
                          _StatusRow(label: '内核', value: system.kernel!),
                        if (system.cpuModel != null)
                          _StatusRow(label: 'CPU', value: system.cpuModel!),
                        if (system.cpuCount != null)
                          _StatusRow(
                            label: '核心数',
                            value: '${system.cpuCount} 核',
                          ),
                        if (system.mac != null)
                          _StatusRow(label: 'MAC地址', value: system.mac!),
                        if (system.bluetoothMac != null)
                          _StatusRow(
                            label: '蓝牙MAC',
                            value: system.bluetoothMac!,
                          ),
                        _StatusRow(
                          label: 'WiFi',
                          value: system.wifiSSID ?? '--',
                        ),
                        _StatusRow(
                          label: '信号',
                          value: system.wifiSignal != 0
                              ? '${system.wifiSignal}dBm'
                              : '--',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 3. 环境信息（温度/湿度/燃气/光照，对齐 web-debug status.environment）
                    _StatusCard(
                      title: '环境信息',
                      children: [
                        _StatusRow(
                          label: '温度',
                          value: system.envTemperature != null
                              ? '${system.envTemperature!.toStringAsFixed(1)}°C'
                              : '--',
                        ),
                        _StatusRow(
                          label: '湿度',
                          value: system.envHumidity != null
                              ? '${system.envHumidity!.toStringAsFixed(1)}%'
                              : '--',
                        ),
                        _StatusRow(
                          label: '燃气',
                          value: system.envGas != null
                              ? system.envGas!.toStringAsFixed(1)
                              : '--',
                        ),
                        _StatusRow(
                          label: '光照',
                          value: system.envLight != null
                              ? '${system.envLight!.toStringAsFixed(0)} lux'
                              : '--',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 4. 子系统列表
                    _StatusCard(
                      title: '子系统',
                      children: [
                        for (final s in data.services)
                          _StatusRow(
                            label: s.name,
                            value: _serviceStatus(s.status),
                          ),
                      ],
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

  Widget _buildTopStatusCard(SystemStatusData system) {
    // 电池：status 非 unknown/not_present 且 level>0 才显示真实值，否则显示 --（真机无电池数据时回退 100/unknown）
    final hasBattery = system.batteryLevel > 0 &&
        system.batteryStatus != 'unknown' &&
        system.batteryStatus != 'not_present';
    final batteryValue = hasBattery
        ? '${system.batteryLevel.toStringAsFixed(0)}%'
        : '--';
    final batterySubtitle = !hasBattery
        ? '无电池数据'
        : system.batteryCharging
        ? '充电中'
        : system.batteryEstimatedMinutes != null
        ? '约${system.batteryEstimatedMinutes}分钟'
        : '使用中';
    final batteryIcon = system.batteryCharging
        ? Icons.battery_charging_full
        : system.batteryLevel <= 20
        ? Icons.battery_alert
        : Icons.battery_full;
    // WiFi
    final wifiValue = system.wifiSSID ?? '未连接';
    final wifiSubtitle = system.wifiSignal != 0
        ? '${system.wifiSignal}dBm'
        : '信号未知';
    // 蜂窝（SystemStatusData 无蜂窝字段，显示 '--' 占位，后续补充）
    const cellularValue = '--';
    const cellularSubtitle = '蜂窝网络';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: _MetricTile(
                  icon: Icons.network_cell,
                  title: '蜂窝',
                  subtitle: cellularSubtitle,
                  value: cellularValue,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: Icons.wifi,
                  title: 'WiFi',
                  subtitle: wifiSubtitle,
                  value: wifiValue,
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: batteryIcon,
                  title: '电池',
                  subtitle: batterySubtitle,
                  value: batteryValue,
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 0.5, color: Color(0xFFD8D8D8)),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  icon: Icons.memory,
                  title: 'CPU',
                  subtitle: '使用率',
                  value: '${system.cpuUsage.toStringAsFixed(0)}%',
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: Icons.storage,
                  title: '内存',
                  subtitle: '使用率',
                  value: '${system.memoryUsage.toStringAsFixed(0)}%',
                ),
              ),
              Expanded(
                child: _MetricTile(
                  icon: Icons.dns_outlined,
                  title: '硬盘',
                  subtitle: '使用率',
                  value: '${system.diskUsage.toStringAsFixed(0)}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _uptime(int seconds) {
    final h = seconds ~/ 3600;
    final d = h ~/ 24;
    if (d > 0) return '$d天${h % 24}小时';
    if (h > 0) return '$h小时';
    return '${seconds ~/ 60}分钟';
  }

  String _serviceStatus(String status) {
    switch (status) {
      case 'running':
        return '运行中';
      case 'starting':
        return '启动中';
      case 'stopped':
        return '已停止';
      case 'failed':
        return '异常';
      default:
        return status;
    }
  }
}

/// 指标块 — 匹配 Pixso 5:3261 (126×80: 图标 + 标题 + 大数值 + 副标题)
class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle, value;
  const _MetricTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF232222)),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(fontSize: 13, color: Color(0xFF232222)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1C1E),
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}

/// 白底圆角卡片容器
class _StatusCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _StatusCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF3D3D3D),
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}

/// 状态行 — label 左 value 右 (Pixso 5:3358, 27px 高)
class _StatusRow extends StatelessWidget {
  final String label, value;
  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
          ),
        ],
      ),
    );
  }
}
