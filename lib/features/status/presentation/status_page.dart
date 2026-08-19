import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/theme/app_colors.dart';

/// 状态页 — 匹配 web-debug StatusView.vue
///
/// 4 个区域:
/// 1. 运行状态卡片 (电池/WiFi/CPU/内存/磁盘)
/// 2. 设备详情列表
/// 3. 环境信息 (温度/湿度/燃气/光照)
/// 4. 子系统状态
class StatusPage extends ConsumerWidget {
  const StatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionManagerProvider);
    ref.watch(robotDataProvider);
    final data = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);

    if (connState != ConnState.connected) {
      return Scaffold(
        appBar: AppBar(title: const Text('状态')),
        body: const Center(child: Text('未连接到机器人')),
      );
    }

    final system = data.system;

    return Scaffold(
      appBar: AppBar(
        title: const Text('状态'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: manager.sendGetStatus,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 运行状态卡片
          _StatusCard(
            title: '运行状态',
            icon: Icons.dashboard,
            children: [
              _StatusGrid(
                children: [
                  _MetricTile(
                    icon: Icons.battery_charging_full,
                    label: '电池电量',
                    value: '${system.batteryLevel.toStringAsFixed(0)}%',
                    color: _batteryColor(system.batteryLevel),
                    subtitle: system.batteryCharging ? '充电中' : '使用中',
                  ),
                  _MetricTile(
                    icon: Icons.wifi,
                    label: 'WiFi',
                    value: system.wifiSSID ?? '未知',
                    color: _wifiColor(system.wifiSignal),
                    subtitle: _wifiSignalText(system.wifiSignal),
                  ),
                  _MetricTile(
                    icon: Icons.memory,
                    label: 'CPU',
                    value: '${system.cpuUsage.toStringAsFixed(1)}%',
                    color: _usageColor(system.cpuUsage),
                    subtitle: system.cpuTemp != null
                        ? '${system.cpuTemp!.toStringAsFixed(0)}°C'
                        : null,
                  ),
                  _MetricTile(
                    icon: Icons.storage,
                    label: '内存',
                    value: '${system.memoryUsage.toStringAsFixed(1)}%',
                    color: _usageColor(system.memoryUsage),
                  ),
                  _MetricTile(
                    icon: Icons.sd_storage,
                    label: '磁盘',
                    value: '${system.diskUsage.toStringAsFixed(1)}%',
                    color: _usageColor(system.diskUsage),
                  ),
                  _MetricTile(
                    icon: Icons.timer,
                    label: '运行时间',
                    value: _uptimeText(system.uptime),
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. 设备详情
          if (manager.robotInfo != null) ...[
            _StatusCard(
              title: '设备详情',
              icon: Icons.info,
              children: _buildDeviceDetails(manager.robotInfo!),
            ),
            const SizedBox(height: 12),
          ],

          // 3. 环境信息
          _StatusCard(
            title: '环境信息',
            icon: Icons.thermostat,
            children: [
              _StatusGrid(
                children: [
                  _MetricTile(
                    icon: Icons.thermostat,
                    label: '温度',
                    value: system.cpuTemp != null
                        ? '${system.cpuTemp!.toStringAsFixed(1)}°C'
                        : '--',
                    color: AppColors.primary,
                  ),
                  const _MetricTile(
                    icon: Icons.water_drop,
                    label: '湿度',
                    value: '--',
                    color: Colors.blue,
                  ),
                  const _MetricTile(
                    icon: Icons.gas_meter,
                    label: '燃气',
                    value: '--',
                    color: Colors.green,
                  ),
                  const _MetricTile(
                    icon: Icons.light_mode,
                    label: '光照',
                    value: '--',
                    color: Colors.amber,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4. 子系统状态
          if (data.modules.isNotEmpty || data.services.isNotEmpty) ...[
            _StatusCard(
              title: '子系统状态',
              icon: Icons.extension,
              children: _buildSubsystems(data),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  List<Widget> _buildDeviceDetails(Map<String, dynamic> info) {
    final fields = <String, String>{};
    if (info['robot_id'] != null) {
      fields['机器人 ID'] = info['robot_id'].toString();
    }
    if (info['name'] != null) fields['名称'] = info['name'].toString();
    if (info['model'] != null) fields['型号'] = info['model'].toString();
    if (info['version'] != null) fields['版本'] = info['version'].toString();
    if (info['serialNumber'] != null) {
      fields['序列号'] = info['serialNumber'].toString();
    }
    if (info['firmwareVersion'] != null) {
      fields['固件版本'] = info['firmwareVersion'].toString();
    }
    if (info['sdkVersion'] != null) {
      fields['SDK 版本'] = info['sdkVersion'].toString();
    }
    if (info['os'] != null) fields['操作系统'] = info['os'].toString();
    if (info['hostname'] != null) fields['主机名'] = info['hostname'].toString();

    return fields.entries
        .map((e) => _DetailRow(label: e.key, value: e.value))
        .toList();
  }

  List<Widget> _buildSubsystems(RobotDataStore data) {
    final items = <Widget>[];
    for (final m in data.modules) {
      items.add(
        _SubsystemTile(
          name: m.name,
          status: m.status,
          version: m.version,
          enabled: m.enabled,
        ),
      );
    }
    for (final s in data.services) {
      items.add(
        _SubsystemTile(
          name: s.name,
          status: s.status,
          version: '',
          enabled: s.status == 'running',
        ),
      );
    }
    return items;
  }

  Color _batteryColor(double level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return AppColors.error;
  }

  Color _wifiColor(int signal) {
    if (signal >= -50) return Colors.green;
    if (signal >= -65) return Colors.orange;
    return AppColors.error;
  }

  String _wifiSignalText(int signal) {
    if (signal >= -50) return '极好';
    if (signal >= -65) return '良好';
    if (signal >= -75) return '一般';
    return '较弱';
  }

  Color _usageColor(double usage) {
    if (usage > 90) return AppColors.error;
    if (usage > 70) return Colors.orange;
    return Colors.green;
  }

  String _uptimeText(int uptime) {
    final h = uptime ~/ 3600;
    final m = (uptime % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${uptime}s';
  }
}

/// 状态卡片容器
class _StatusCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _StatusCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 指标网格
class _StatusGrid extends StatelessWidget {
  final List<Widget> children;
  const _StatusGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: children
          .map(
            (c) => SizedBox(
              width: (MediaQuery.of(context).size.width - 64) / 2,
              child: c,
            ),
          )
          .toList(),
    );
  }
}

/// 单个指标块
class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Icon(
            Icons.copy,
            size: 14,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

class _SubsystemTile extends StatelessWidget {
  final String name;
  final String status;
  final String version;
  final bool enabled;

  const _SubsystemTile({
    required this.name,
    required this.status,
    required this.version,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = status == 'running' || status == 'online' || enabled;
    return ListTile(
      dense: true,
      leading: Icon(
        isOnline ? Icons.check_circle : Icons.error_outline,
        color: isOnline ? Colors.green : AppColors.error,
        size: 20,
      ),
      title: Text(name, style: const TextStyle(fontSize: 13)),
      subtitle: version.isNotEmpty
          ? Text(
              'v$version',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            )
          : null,
      trailing: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          color: isOnline ? Colors.green : AppColors.error,
        ),
      ),
    );
  }
}
