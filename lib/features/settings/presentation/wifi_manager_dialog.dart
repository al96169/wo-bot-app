import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';

/// WiFi 管理器弹窗 — 扫描局域网热点 + 连接（对齐 web-debug WiFiManager）
///
/// 数据源: sendWifiScan → wifi_scan_result → RobotDataStore.wifiNetworks
class WifiManagerDialog extends ConsumerStatefulWidget {
  const WifiManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const WifiManagerDialog(),
    );
  }

  @override
  ConsumerState<WifiManagerDialog> createState() => _WifiManagerDialogState();
}

class _WifiManagerDialogState extends ConsumerState<WifiManagerDialog> {
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    setState(() => _scanning = true);
    ref.read(connectionManagerProvider.notifier).sendWifiScan();
    // 扫描结果由 wifi_scan_result 消息更新，短暂延迟后结束扫描状态
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  void _connect(String ssid) {
    // 打开密码输入
    final pwdC = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('连接 $ssid'),
        content: TextField(
          controller: pwdC,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'WiFi 密码'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              ref.read(connectionManagerProvider.notifier).sendWifiConnect(ssid, pwdC.text);
              Navigator.pop(ctx);
              AppToast.show('正在连接 $ssid...', type: AppToastType.info);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final networks = store.wifiNetworks;
    final currentSsid = store.wifiCurrentSSID;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('WiFi 管理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (currentSsid.isNotEmpty)
                    Text('已连接：$currentSsid', style: const TextStyle(fontSize: 12, color: Color(0xFF34C759))),
                  IconButton(
                    onPressed: _scanning ? null : _scan,
                    tooltip: '重新扫描',
                    icon: _scanning
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            if (networks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.wifi_off, size: 32, color: Color(0xFFC7C7CC)),
                    SizedBox(height: 8),
                    Text('未发现 WiFi 热点', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: networks.length,
                  itemBuilder: (context, i) {
                    final net = networks[i];
                    final ssid = net['ssid'] as String? ?? '未知';
                    final signal = net['signal'] as num? ?? 0;
                    final isCurrent = ssid == currentSsid;
                    return ListTile(
                      leading: Icon(
                        signal >= -60 ? Icons.wifi : Icons.wifi_2_bar,
                        color: isCurrent ? const Color(0xFF34C759) : const Color(0xFF3D3D3D),
                      ),
                      title: Text(ssid, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        isCurrent ? '已连接' : '${signal}dBm',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                      ),
                      trailing: isCurrent
                          ? null
                          : TextButton(onPressed: () => _connect(ssid), child: const Text('连接')),
                      onTap: isCurrent ? null : () => _connect(ssid),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
