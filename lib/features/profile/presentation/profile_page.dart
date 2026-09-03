import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/account_service.dart';
import '../../../core/network/device_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../cloud_apps/presentation/cloud_apps_page.dart';

/// 个人页面 — 匹配 Pixso 1:4187 (已登录) / 1:4438 (未登录)
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});
  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  AccountService get _account => AccountService.instance;

  /// 云端设备列表（登录后加载）
  List<CloudDevice> _cloudDevices = const [];
  bool _loadingCloud = false;

  /// 用外部浏览器打开链接
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      AppToast.show('无法打开链接: $url', type: AppToastType.error);
    }
  }

  /// 加载云端设备列表
  Future<void> _loadCloudDevices() async {
    if (!_account.isAuthenticated) {
      if (mounted && _cloudDevices.isNotEmpty) {
        setState(() => _cloudDevices = const []);
      }
      return;
    }
    if (_loadingCloud) return;
    setState(() => _loadingCloud = true);
    final devices = await _account.fetchCloudDevices();
    if (mounted) {
      setState(() {
        _cloudDevices = devices;
        _loadingCloud = false;
      });
      // 同步到 DeviceStore，供设备页复用
      ref.read(deviceStoreProvider.notifier).setCloudDevices(devices);
    }
  }

  /// 解绑云端设备
  Future<void> _unbindCloudDevice(CloudDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text(
          '确定解绑“${device.robotName ?? device.robotId}”吗？解绑后将无法远程控制该设备。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _account.unbindDevice(device.robotId);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _cloudDevices = _cloudDevices
            .where((d) => d.robotId != device.robotId)
            .toList();
      });
      ref.read(deviceStoreProvider.notifier).setCloudDevices(_cloudDevices);
      AppToast.show('已解绑设备', type: AppToastType.success);
    } else {
      AppToast.show('解绑失败，请稍后重试', type: AppToastType.error);
    }
  }

  @override
  void initState() {
    super.initState();
    _account.onAuthStateChanged = _onAuthChanged;
    _account.init().then((_) {
      if (mounted) setState(() {});
      _loadCloudDevices();
    });
  }

  @override
  void dispose() {
    _account.onAuthStateChanged = null;
    super.dispose();
  }

  /// 授权回调完成后刷新登录状态
  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {});
    _loadCloudDevices();
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _account.isAuthenticated;
    final user = _account.user;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏 74px — Pixso 个人页无顶栏内容，仅占位
            const SizedBox(height: 74),
            // 内容区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: isLoggedIn ? _buildLoggedIn(user) : _buildNotLoggedIn(),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  /// 已登录状态 (Pixso 1:4187)
  Widget _buildLoggedIn(UserInfo? user) {
    return Column(
      children: [
        // Card 1: 昵称 + 设备数量 (108px)
        _ProfileCard(
          children: [
            _ProfileRow(label: '昵称', value: user?.name ?? user?.email ?? '--'),
            const SizedBox(height: 10),
            _ProfileRow(label: '设备数量', value: '${_cloudDevices.length}'),
          ],
        ),
        const SizedBox(height: 10),
        // Card 2: 云端设备 (登录后展示设备列表 + 解绑)
        _buildCloudDevicesCard(),
        const SizedBox(height: 10),
        // Card 2.5: 授权应用管理（CloudAppsPage 入口 — 对齐 web-debug 用户菜单）
        _ProfileCard(
          children: [
            _MenuRow(
              label: '授权应用',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CloudAppsPage(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Card 3: 消息 (59px)
        _ProfileCard(
          children: [
            _MenuRow(
              label: '消息',
              onTap: () => Navigator.of(context).pushNamed('/messages'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Card 4: Wo-Bot 官网 + Wo-Bot 个人中心 (108px)
        _ProfileCard(
          children: [
            _LinkRow(
              label: 'Wo-Bot 官网',
              url: 'https://wo-bot.com',
              onTap: () => _openUrl('https://wo-bot.com'),
            ),
            const SizedBox(height: 10),
            _LinkRow(
              label: 'Wo-Bot 个人中心',
              url: 'https://user.wo-bot.com',
              onTap: () => _openUrl('https://user.wo-bot.com'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Card 5: 退出登录 (59px)
        _ProfileCard(
          children: [
            _MenuRow(
              label: '退出登录',
              color: const Color(0xFF6750A4),
              onTap: () async {
                await _account.logout();
                if (mounted) {
                  setState(() => _cloudDevices = const []);
                  ref.read(deviceStoreProvider.notifier).clearCloudDevices();
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 云端设备卡片 — 设备列表 + 解绑操作
  Widget _buildCloudDevicesCard() {
    return _ProfileCard(
      children: [
        if (_loadingCloud)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_cloudDevices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                '暂无云端设备\n登录后可将本地设备绑定到云端，实现远程控制',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
            ),
          )
        else
          ..._cloudDevices.map(
            (device) => _CloudDeviceRow(
              device: device,
              onUnbind: () => _unbindCloudDevice(device),
            ),
          ),
      ],
    );
  }

  /// 未登录状态 (Pixso 1:4438)
  Widget _buildNotLoggedIn() {
    return Column(
      children: [
        // Card 1: Wo-Bot 官网 + Wo-Bot 个人中心 (108px)
        _ProfileCard(
          children: [
            _LinkRow(
              label: 'Wo-Bot 官网',
              url: 'https://wo-bot.com',
              onTap: () => _openUrl('https://wo-bot.com'),
            ),
            const SizedBox(height: 10),
            _LinkRow(
              label: 'Wo-Bot 个人中心',
              url: 'https://user.wo-bot.com',
              onTap: () => _openUrl('https://user.wo-bot.com'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Card 2: 登录 (59px) — 触发用户中心授权流程
        _ProfileCard(
          children: [
            _MenuRow(
              label: '登录',
              color: const Color(0xFF6750A4),
              onTap: _startLogin,
            ),
          ],
        ),
      ],
    );
  }

  /// 登录 — 打开用户中心授权页（PKCE 授权码流程）
  Future<void> _startLogin() async {
    final opened = await _account.launchLogin();
    if (!opened && mounted) {
      AppToast.show('无法打开授权页面，请稍后重试', type: AppToastType.error);
    }
  }
}

/// 个人页卡片容器 — 白底圆角，内边距 10px
class _ProfileCard extends StatelessWidget {
  final List<Widget> children;
  const _ProfileCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(children: children),
    );
  }
}

/// 个人信息行 — label (左) + value (右)
class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  const _ProfileRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E)),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}

/// 菜单行 — label (左) + 箭头 (右)
class _MenuRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _MenuRow({
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF1C1C1E),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 14, color: color)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}

/// 链接行 — label + "点击跳转" 提示，点击用外部浏览器打开
class _LinkRow extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onTap;
  const _LinkRow({required this.label, required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, color: Color(0xFF6750A4)),
            ),
            const Spacer(),
            const Text(
              '点击跳转',
              style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC7C7CC)),
          ],
        ),
      ),
    );
  }
}

/// 云端设备行 — 设备名 + 状态 + 解绑按钮
class _CloudDeviceRow extends StatelessWidget {
  final CloudDevice device;
  final VoidCallback onUnbind;
  const _CloudDeviceRow({required this.device, required this.onUnbind});

  @override
  Widget build(BuildContext context) {
    final online = device.status == 'online';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F0FA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              size: 20,
              color: online ? const Color(0xFF6750A4) : const Color(0xFFB6A7D8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.robotName ?? device.robotId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  online ? '在线' : '离线',
                  style: TextStyle(
                    fontSize: 12,
                    color: online
                        ? const Color(0xFF34C759)
                        : const Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onUnbind,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8E8E93),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('解绑', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
