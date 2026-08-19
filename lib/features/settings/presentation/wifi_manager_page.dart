import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// WiFi 管理器页面 — 扫描局域网热点 + 连接（对齐 web-debug WiFiManager）
///
/// 数据源: sendWifiScan → wifi_scan_result → RobotDataStore.wifiNetworks
class WifiManagerPage extends ConsumerStatefulWidget {
  const WifiManagerPage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const WifiManagerPage()),
    );
  }

  @override
  ConsumerState<WifiManagerPage> createState() => _WifiManagerPageState();
}

class _WifiManagerPageState extends ConsumerState<WifiManagerPage> {
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

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: 'WiFi 管理'),
            // 顶部：当前连接状态 + 扫描按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 6, 15, 10),
              child: Row(
                children: [
                  Expanded(
                    child: currentSsid.isNotEmpty
                        ? Row(
                            children: [
                              const Icon(Icons.wifi, size: 16, color: Color(0xFF34C759)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '已连接：$currentSsid',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF34C759)),
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            '扫描附近的 WiFi 热点',
                            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                          ),
                  ),
                  TextButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(_scanning ? '扫描中' : '重新扫描'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0256FF),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFE8E8E8)),
            // 热点列表
            Expanded(
              child: networks.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off, size: 40, color: Color(0xFFC7C7CC)),
                          SizedBox(height: 10),
                          Text('未发现 WiFi 热点', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
                      itemCount: networks.length,
                      itemBuilder: (context, i) {
                        final net = networks[i];
                        final ssid = net['ssid'] as String? ?? '未知';
                        final signal = net['signal'] as num? ?? 0;
                        final isCurrent = ssid == currentSsid;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: isCurrent ? const Color(0xFF34C759) : const Color(0xFFEEEEEE),
                              width: isCurrent ? 1 : 0.5,
                            ),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
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
                                ? const Icon(Icons.check_circle, size: 18, color: Color(0xFF34C759))
                                : TextButton(onPressed: () => _connect(ssid), child: const Text('连接')),
                            onTap: isCurrent ? null : () => _connect(ssid),
                          ),
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
