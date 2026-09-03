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
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const WifiManagerPage()));
  }

  @override
  ConsumerState<WifiManagerPage> createState() => _WifiManagerPageState();
}

class _WifiManagerPageState extends ConsumerState<WifiManagerPage> {
  bool _scanning = false;
  bool _showAddForm = false;
  bool _connecting = false;
  final TextEditingController _ssidC = TextEditingController();
  final TextEditingController _pwdC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _ssidC.dispose();
    _pwdC.dispose();
    super.dispose();
  }

  void _scan() {
    setState(() => _scanning = true);
    ref.read(connectionManagerProvider.notifier).sendWifiScan();
    // 扫描结果由 wifi_scan_result 消息更新，短暂延迟后结束扫描状态
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  /// 判断网络是否加密（对齐 web-debug：security 为 "--"/空 视为开放网络免密）
  bool _isSecure(Map<String, dynamic> net) {
    final sec = (net['security'] as String? ?? '--').trim();
    return sec.isNotEmpty && sec != '--';
  }

  void _connect(String ssid, {String? password}) {
    final m = ref.read(connectionManagerProvider.notifier);
    setState(() => _connecting = true);
    m.sendWifiConnect(ssid, password ?? '');
    AppToast.show('正在连接 $ssid...');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _connecting = false);
    });
  }

  /// 点击网络：加密弹密码框，开放网络直接连
  void _onNetworkTap(Map<String, dynamic> net) {
    final ssid = net['ssid'] as String? ?? '';
    if (ssid.isEmpty) return;
    if (_isSecure(net)) {
      _promptPassword(ssid);
    } else {
      _connect(ssid);
    }
  }

  void _promptPassword(String ssid) {
    final pwdC = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('连接 $ssid'),
        content: TextField(
          controller: pwdC,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'WiFi 密码'),
          onSubmitted: (v) {
            Navigator.pop(ctx);
            _connect(ssid, password: v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _connect(ssid, password: pwdC.text);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  /// 断开当前 WiFi
  void _disconnect(String device) {
    final m = ref.read(connectionManagerProvider.notifier);
    m.sendWifiDisconnect(device);
    AppToast.show('正在断开 WiFi...');
  }

  /// 手动添加网络（SSID + 可选密码）
  void _addNetwork() {
    final ssid = _ssidC.text.trim();
    if (ssid.isEmpty) {
      AppToast.show('请输入网络名称', type: AppToastType.error);
      return;
    }
    final password = _pwdC.text.trim();
    _ssidC.clear();
    _pwdC.clear();
    setState(() => _showAddForm = false);
    _connect(ssid, password: password);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final networks = store.wifiNetworks;
    final currentSsid = store.wifiCurrentSSID;
    // 当前连接设备名（wifi_disconnect 需要，robot 端 current_device 字段）
    final currentDevice = store.wifiCurrentDevice;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: 'WiFi 管理'),
            // 顶部：当前连接状态 + 扫描/断开按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 6, 15, 10),
              child: Row(
                children: [
                  Expanded(
                    child: currentSsid.isNotEmpty
                        ? Row(
                            children: [
                              const Icon(
                                Icons.wifi,
                                size: 16,
                                color: Color(0xFF34C759),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '已连接：$currentSsid',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF34C759),
                                  ),
                                ),
                              ),
                              // 断开当前连接（对齐 web-debug）
                              InkWell(
                                onTap: currentDevice.isNotEmpty
                                    ? () => _disconnect(currentDevice)
                                    : null,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '断开',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFFF453A),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            '扫描附近的 WiFi 热点',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                  ),
                  TextButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: _scanning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
            // 手动添加网络入口（对齐 web-debug "+ 添加网络"）
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 6, 15, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showAddForm = !_showAddForm),
                  icon: Icon(
                    _showAddForm ? Icons.close : Icons.add,
                    size: 16,
                  ),
                  label: Text(_showAddForm ? '取消' : '+ 添加网络'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0256FF),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
            // 手动添加表单
            if (_showAddForm) _buildAddForm(),
            const Divider(height: 1, thickness: 0.5, color: Color(0xFFE8E8E8)),
            // 热点列表
            Expanded(
              child: networks.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.wifi_off,
                            size: 40,
                            color: Color(0xFFC7C7CC),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '未发现 WiFi 热点\n可点击上方"添加网络"手动连接',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
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
                        final isOpen = !_isSecure(net);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: isCurrent
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFEEEEEE),
                              width: isCurrent ? 1 : 0.5,
                            ),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            leading: Icon(
                              signal >= -60 ? Icons.wifi : Icons.wifi_2_bar,
                              color: isCurrent
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFF3D3D3D),
                            ),
                            title: Text(
                              ssid,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              isCurrent
                                  ? '已连接'
                                  : (isOpen
                                        ? '开放网络 · ${signal}dBm'
                                        : '${signal}dBm'),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8E8E93),
                              ),
                            ),
                            trailing: isCurrent
                                ? const Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Color(0xFF34C759),
                                  )
                                : TextButton(
                                    onPressed: _connecting
                                        ? null
                                        : () => _onNetworkTap(net),
                                    child: Text(
                                      _connecting ? '连接中' : '连接',
                                    ),
                                  ),
                            onTap: isCurrent
                                ? null
                                : () => _onNetworkTap(net),
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

  /// 手动添加网络表单（SSID + 可选密码）
  Widget _buildAddForm() {
    return Container(
      margin: const EdgeInsets.fromLTRB(15, 4, 15, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
      ),
      child: Column(
        children: [
          TextField(
            controller: _ssidC,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '网络名称 (SSID)',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pwdC,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: '密码（开放网络可留空）',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _addNetwork,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0256FF),
              ),
              child: const Text('添加并连接'),
            ),
          ),
        ],
      ),
    );
  }
}
