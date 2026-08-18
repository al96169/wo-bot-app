import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/bind_service.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/device_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_device.dart';
import '../../robot_home/presentation/robot_home_page.dart';
import 'add_device_page.dart';
import 'bind_view.dart';
import 'device_list_provider.dart';

/// 第一阶段设备主页：已保存设备与局域网发现结果严格分区。
class DeviceListPage extends ConsumerStatefulWidget {
  const DeviceListPage({super.key});

  @override
  ConsumerState<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends ConsumerState<DeviceListPage> {
  bool _openingBind = false;

  @override
  void initState() {
    super.initState();
    BindService.instance.onMethodsReady = (_) => _showBindPage();
  }

  @override
  void dispose() {
    BindService.instance.onMethodsReady = null;
    super.dispose();
  }

  Future<void> _showBindPage() async {
    if (!mounted || _openingBind) return;
    _openingBind = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFF9F9F9),
          appBar: AppBar(title: const Text('绑定设备')),
          body: BindView(
            onBound: () async {
              final current = ref.read(deviceStoreProvider).currentDevice;
              if (current != null) {
                await ref
                    .read(deviceStoreProvider.notifier)
                    .addDevice(current.copyWith(bound: true));
              }
              if (mounted) Navigator.of(context).pop();
            },
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    _openingBind = false;
  }

  Future<void> _connect(RobotDevice device) async {
    final store = ref.read(deviceStoreProvider);
    final current = store.currentDevice;
    final sameDevice = current != null &&
        (current.id == device.id ||
            (current.ip == device.ip && current.port == device.port));

    // 对齐 web-debug handleSelectDevice：
    // 1. 无当前设备 → 直接连接
    // 2. 不同设备 → 确认切换
    // 3. 同一设备已连接 → Toast
    // 4. 同一设备连接中 → Toast
    // 5. 同一设备其他状态 → 重新连接
    if (current == null) {
      await _connectDirectly(device);
      return;
    }

    if (!sameDevice) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认切换设备'),
          content: Text(
            '确定要断开当前连接并切换到 ${device.name} 吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认切换'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      // 断开当前连接后再连接新设备
      ref.read(connectionManagerProvider.notifier).disconnect();
      await _connectDirectly(device);
      return;
    }

    final conn = ref.read(connectionManagerProvider);
    if (conn == ConnState.connected) {
      AppToast.show('已连接该设备', type: AppToastType.info);
      return;
    }
    if (conn == ConnState.connecting) {
      AppToast.show('正在连接中...', type: AppToastType.info);
      return;
    }
    // 同一设备其他状态 → 重新连接
    await _connectDirectly(device);
  }

  /// 直接连接设备（无确认）— 对齐 web-debug connectDirectly
  Future<void> _connectDirectly(RobotDevice device) async {
    await ref.read(deviceStoreProvider.notifier).setCurrentDevice(device);
    try {
      await ref
          .read(connectionManagerProvider.notifier)
          .connectToDevice(device);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      AppToast.show('连接失败: ${device.name}', type: AppToastType.error);
      // 连接失败弹窗 — 对齐 web-debug ConnectTimeoutDialog（可重试）
      final retry = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ 连接失败'),
          content: Text('无法连接到 ${device.name}，请检查设备是否在线。\n\n$message'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('重新连接'),
            ),
          ],
        ),
      );
      if (retry == true && mounted) {
        await _connectDirectly(device);
      }
    }
  }

  /// 忘记设备 — 移除保存记录并断开连接
  Future<void> _forget(RobotDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忘记设备'),
        content: Text('确定要忘记 ${device.name} 吗？此操作将删除设备的连接记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final store = ref.read(deviceStoreProvider);
      if (store.currentDevice?.id == device.id) {
        ref.read(connectionManagerProvider.notifier).disconnect();
      }
      await ref.read(deviceStoreProvider.notifier).removeDevice(device.id);
      AppToast.show('已忘记 ${device.name}', type: AppToastType.success);
    }
  }

  /// 断开当前连接
  void _disconnect() {
    ref.read(connectionManagerProvider.notifier).disconnect();
    AppToast.show('连接已断开', type: AppToastType.info);
  }

  /// 右上角加号 → 跳转设备发现界面 (Pixso 1:3365)
  void _openAddPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddDevicePage()),
    );
  }

  Future<void> _remove(RobotDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除设备'),
        content: Text('确定从列表中移除“${device.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(deviceStoreProvider.notifier).removeDevice(device.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(deviceStoreProvider);
    final connection = ref.watch(connectionManagerProvider);
    final saved = store.devices;

    // 连接成功后跳转机器人主页（对齐 web-debug：连接后进入功能主页）
    ref.listen<ConnState>(connectionManagerProvider, (prev, next) {
      if (prev != ConnState.connected && next == ConnState.connected && mounted) {
        // 延迟跳转，避免绑定流程中的 connected 误触发
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && ref.read(connectionManagerProvider) == ConnState.connected) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RobotHomePage()),
            );
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onRefresh: () =>
                  ref.read(deviceListProvider.notifier).startScan(),
              onAdd: _openAddPage,
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(deviceListProvider.notifier).startScan(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 4, 10, 104),
                  children: [
                    _SectionTitle(title: '我的设备', count: saved.length),
                    if (saved.isEmpty)
                      _EmptySaved(onAdd: _openAddPage)
                    else
                      ...saved.map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DeviceCard(
                            device: device,
                            connected:
                                store.currentDevice?.id == device.id &&
                                connection == ConnState.connected,
                            onTap: () => _connect(device),
                            onRemove: () => _remove(device),
                            onForget: () => _forget(device),
                            onDisconnect: _disconnect,
                          ),
                        ),
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
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onAdd;

  const _Header({
    required this.onRefresh,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'wo-bot',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
            ),
            _RoundButton(
              key: const Key('refresh_devices_button'),
              tooltip: '刷新设备',
              onTap: onRefresh,
              child: const Icon(Icons.refresh, size: 22),
            ),
            const SizedBox(width: 10),
            _RoundButton(
              key: const Key('add_device_button'),
              tooltip: '添加设备',
              onTap: onAdd,
              child: const Icon(Icons.add, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onTap;
  final Widget child;
  const _RoundButton({
    super.key,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Pixso 1:3203 — 顶栏按钮为无背景纯图标（透明容器 44×44），图标主色紫
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: IconTheme(
            data: const IconThemeData(color: Color(0xFF6750A4)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;
  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 8, 5, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3D3D3D),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final RobotDevice device;
  final bool connected;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onForget;
  final VoidCallback? onDisconnect;

  const _DeviceCard({
    required this.device,
    required this.connected,
    required this.onTap,
    this.onRemove,
    this.onForget,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    // Pixso Component_1_2980 (408×139)：名称 → 基础状态行 → IP → 状态胶囊行
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.6,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000000),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '设备管理',
                    icon: const Icon(
                      Icons.more_horiz,
                      color: Color(0xFF8E8E93),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'disconnect':
                          onDisconnect?.call();
                          break;
                        case 'remove':
                          onRemove?.call();
                          break;
                        case 'forget':
                          onForget?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) {
                      final items = <PopupMenuEntry<String>>[
                        if (connected)
                          const PopupMenuItem(
                            value: 'disconnect',
                            child: Text('断开连接'),
                          ),
                        if (connected)
                          const PopupMenuItem(
                            value: 'forget',
                            child: Text('忘记设备'),
                          )
                        else
                          const PopupMenuItem(
                            value: 'remove',
                            child: Text('移除设备'),
                          ),
                      ];
                      return items;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Row 2: 基础状态 — 信号强度 | 电量 | 延迟 (Pixso 1:2907)
              _StatusRow(device: device),
              const SizedBox(height: 10),
              // Row 3: IP 和端口 (Pixso 1:2950, 11.6sp 注释文本)
              Text(
                '${device.ip}:${device.port}',
                style: const TextStyle(fontSize: 11.6, color: Color(0xFF8E8E93)),
              ),
              const SizedBox(height: 10),
              // Row 4: 状态胶囊 (Pixso 1:2962, 灰底圆角胶囊)
              // 优先级对齐 web-debug：已绑定 > 已保存 > 在线状态 > 已连接
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  if (device.bound) const _Tag('已绑定'),
                  const _Tag('已保存'),
                  if (connected)
                    const _Tag('已连接')
                  else if (device.localAvailable)
                    const _Tag('本地在线')
                  else
                    const _Tag('当前离线'),
                  ...device.capabilityLabels.map(_Tag.new),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 基础状态行 — 信号强度 | 电量 | 延迟 (Pixso 1:2907 / 1:2866 / 1:2909)
/// 文字 11.6sp 主色紫，分隔符 "|" 与 "▎" 为黑色
class _StatusRow extends StatelessWidget {
  final RobotDevice device;
  const _StatusRow({required this.device});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11.6, color: Color(0xFF6750A4));
    const sep = TextStyle(fontSize: 11.6, color: Color(0xFF000000));
    final signal =
        device.signalDbm != null ? '信号强度 ${device.signalDbm}' : '信号强度 --';
    final battery =
        device.batteryLevel != null ? '电量 ${device.batteryLevel}%' : '电量 --';
    final latency =
        device.latencyMs > 0 ? '延迟 ${device.latencyMs}' : '延迟 --';
    return Text.rich(
      TextSpan(style: style, children: [
        TextSpan(text: signal),
        const TextSpan(text: ' | ', style: sep),
        TextSpan(text: battery),
        const TextSpan(text: ' ▎', style: sep),
        TextSpan(text: latency),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  const _Tag(this.label);

  @override
  Widget build(BuildContext context) {
    // Pixso 1:2956 状态胶囊 — 灰底 #E5E5E5、全圆角、紫字 11.6sp
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11.6, color: Color(0xFF6750A4)),
      ),
    );
  }
}

class _EmptySaved extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptySaved({required this.onAdd});

  @override
  Widget build(BuildContext context) => _MessageCard(
    icon: Icons.smart_toy_outlined,
    title: '还没有保存设备',
    subtitle: '点击右上角 + 添加设备，或从局域网发现结果中保存',
    action: TextButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add),
      label: const Text('添加设备'),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: .5),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: const Color(0xFFB6A7D8)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
