import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../shared/models/robot_data.dart';
import '../../../core/theme/app_colors.dart';

/// 机器人信息页面 — 连接后的主页面
///
/// 展示: 电池、系统资源、网络、设备信息
/// 导航: 遥控、状态、快速操作
class RobotInfoPage extends ConsumerWidget {
  const RobotInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionManagerProvider);
    ref.watch(robotDataProvider);
    final data = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);

    final system = data.system;

    return Scaffold(
      appBar: AppBar(
        title: const Text('机器人信息'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 连接状态指示
          Container(
            margin: const EdgeInsets.only(right: 16),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connState == ConnState.connected ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  connState == ConnState.connected ? '已连接' : connState == ConnState.binding ? '认证中' : '连接中',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      body: connState == ConnState.connected
          ? _buildContent(context, system, manager.robotInfo, ref)
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    connState == ConnState.binding ? '等待绑定认证...' : '正在连接...',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: connState == ConnState.connected
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/remote-control'),
                        icon: const Icon(Icons.gamepad),
                        label: const Text('遥控'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/status'),
                        icon: const Icon(Icons.dashboard),
                        label: const Text('状态'),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildContent(BuildContext context, SystemStatusData system, Map<String, dynamic>? robotInfo, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 电池卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: _batteryColor(system.batteryLevel).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    system.batteryCharging ? Icons.battery_charging_full : Icons.battery_full,
                    size: 40, color: _batteryColor(system.batteryLevel),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('电池', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text('${system.batteryLevel.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: _batteryColor(system.batteryLevel), fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(system.batteryCharging ? '充电中 ⚡' : '使用中',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: system.batteryCharging ? _batteryColor(system.batteryLevel) : AppColors.textSecondary)),
                  ],
                )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 系统资源卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('系统资源', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                _ResourceBar(label: 'CPU', value: system.cpuUsage, color: _usageColor(system.cpuUsage)),
                const SizedBox(height: 12),
                _ResourceBar(label: '内存', value: system.memoryUsage, color: _usageColor(system.memoryUsage)),
                const SizedBox(height: 12),
                _ResourceBar(label: '磁盘', value: system.diskUsage, color: _usageColor(system.diskUsage)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 网络卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('网络', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                if (system.wifiSSID != null)
                  Row(children: [
                    Icon(Icons.wifi, size: 20, color: _wifiColor(system.wifiSignal)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(system.wifiSSID!, style: Theme.of(context).textTheme.bodyLarge)),
                    Text(_wifiSignalText(system.wifiSignal), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _wifiColor(system.wifiSignal))),
                  ]),
                const SizedBox(height: 8),
                if (system.ip != null)
                  Row(children: [
                    const Icon(Icons.language, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    Text('IP: ${system.ip}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 设备信息卡片
        if (robotInfo != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('设备信息', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  if (robotInfo['robot_id'] != null)
                    _InfoRow(label: '机器人 ID', value: '${robotInfo['robot_id']}'),
                  if (robotInfo['model'] != null) ...[
                    const SizedBox(height: 8),
                    _InfoRow(label: '型号', value: '${robotInfo['model']}'),
                  ],
                  if (robotInfo['version'] != null) ...[
                    const SizedBox(height: 8),
                    _InfoRow(label: '版本', value: '${robotInfo['version']}'),
                  ],
                  if (system.hostname != null) ...[
                    const SizedBox(height: 8),
                    _InfoRow(label: '主机名', value: system.hostname!),
                  ],
                  const SizedBox(height: 8),
                  _InfoRow(label: '运行时间', value: _uptimeText(system.uptime)),
                ],
              ),
            ),
          ),

        const SizedBox(height: 80),
      ],
    );
  }

  Color _batteryColor(double level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return AppColors.error;
  }

  Color _usageColor(double usage) {
    if (usage > 90) return AppColors.error;
    if (usage > 70) return Colors.orange;
    return Colors.green;
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

  String _uptimeText(int uptime) {
    final h = uptime ~/ 3600;
    final m = (uptime % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m';
    return '${uptime}s';
  }
}

class _ResourceBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ResourceBar({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(width: 40, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      const SizedBox(width: 12),
      Expanded(child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: value / 100.0,
          backgroundColor: AppColors.divider,
          valueColor: AlwaysStoppedAnimation(color),
          minHeight: 8,
        ),
      )),
      const SizedBox(width: 12),
      SizedBox(width: 50, child: Text('${value.toStringAsFixed(1)}%',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
        textAlign: TextAlign.right)),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
      const Spacer(),
      Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}
