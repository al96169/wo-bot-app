import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/account_service.dart';
import '../../../core/network/bind_service.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/device_store.dart';
import '../../../core/network/share_link_service.dart';
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

  /// 已跳转主页标记：防止云端重连触发二次 push 覆盖遥控页
  bool _navigatedToHome = false;

  @override
  void initState() {
    super.initState();
    BindService.instance.onMethodsReady = (_) => _showBindPage();
    // 连接成功收到 robot_info 后，回写 DeviceStore 的设备 robotId
    // （对齐 web-debug updateCurrentDeviceId：后端 robot_id 为准，保证本地/云端去重）
    // 注意：dispose 时不允许再 ref.read（Riverpod element 已 disposed），
    // 因此这里缓存 ConnectionManager 引用，dispose 直接操作它。
    final cm = ref.read(connectionManagerProvider.notifier);
    _cm = cm;
    cm.onRobotIdKnown = (rid) {
      ref.read(deviceStoreProvider.notifier).updateDeviceRobotId(rid);
    };
    // 分享链接深链处理（wobot://connect?robotIp=&robotPort=&shareCode=）
    ShareLinkService.instance.onShareLink = _handleShareLink;
    // 冷启动被拉起时可能有待处理分享（getInitialLink 已触发 submit）
    final pendingShare = ShareLinkService.instance.take();
    if (pendingShare != null) {
      Future.microtask(() => _connectFromShareLink(pendingShare));
    }
  }

  /// 缓存的 ConnectionManager 引用（dispose 时使用，避免 ref 访问）
  ConnectionManager? _cm;

  @override
  void dispose() {
    BindService.instance.onMethodsReady = null;
    _cm?.onRobotIdKnown = null;
    if (ShareLinkService.instance.onShareLink == _handleShareLink) {
      ShareLinkService.instance.onShareLink = null;
    }
    super.dispose();
  }

  /// 分享链接回调（深链到达时触发）
  void _handleShareLink(ShareLinkData data) {
    if (!mounted) return;
    Future.microtask(() => _connectFromShareLink(data));
  }

  /// 分享链接自动连接（对齐 web-debug App.vue 分享逻辑）
  Future<void> _connectFromShareLink(ShareLinkData data) async {
    // 1. 找已有设备（robotId 或 ip:port 匹配）
    final store = ref.read(deviceStoreProvider);
    RobotDevice? existing;
    for (final d in store.devices) {
      if ((data.robotId != null &&
              data.robotId!.isNotEmpty &&
              (d.id == data.robotId || d.robotId == data.robotId)) ||
          (d.ip == data.robotIp && d.port == data.robotPort)) {
        existing = d;
        break;
      }
    }

    RobotDevice target;
    if (existing != null) {
      target = existing;
      // 已绑定当前用户？看 binding 凭证是否存在（此处简化：直接带分享码连）
    } else {
      // 2. 新设备：创建记录
      target = RobotDevice(
        id: 'share-${DateTime.now().millisecondsSinceEpoch}',
        name: '机器人 ${data.robotIp}',
        ip: data.robotIp,
        port: data.robotPort,
        serviceName: '',
      );
      await ref.read(deviceStoreProvider.notifier).addDevice(target);
    }

    // 3. 设置分享码并连接（连接时 WS 携带 shareCode 完成自动绑定）
    final cm = ref.read(connectionManagerProvider.notifier);
    cm.pendingShareCode = data.shareCode;
    AppToast.show('正在通过分享码连接 ${data.robotIp}...');
    _navigatedToHome = false;
    try {
      await ref.read(deviceStoreProvider.notifier).setCurrentDevice(target);
      await cm.connectToDevice(target);
    } catch (e) {
      if (!mounted) return;
      AppToast.show('连接失败: ${data.robotIp}', type: AppToastType.error);
    }
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
    final sameDevice =
        current != null &&
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
          content: Text('确定要断开当前连接并切换到 ${device.name} 吗？'),
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
      AppToast.show('已连接该设备');
      // 已连接的设备 → 直接进入设备主页
      if (mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const RobotHomePage()));
      }
      return;
    }
    if (conn == ConnState.connecting) {
      AppToast.show('正在连接中...');
      return;
    }
    // 同一设备其他状态 → 重新连接
    await _connectDirectly(device);
  }

  /// 直接连接设备（无确认）— 对齐 web-debug connectDirectly
  Future<void> _connectDirectly(RobotDevice device) async {
    // 主动直连：允许本次连接成功跳转主页
    _navigatedToHome = false;
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
    AppToast.show('连接已断开');
  }

  /// 右上角加号 → 跳转设备发现界面 (Pixso 1:3365)
  void _openAddPage() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const AddDevicePage()));
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

  /// 合并列表点击：有 ip:port → 本地连接；无（纯云端设备）→ 云端连接
  /// （对齐 web-debug handleMergedDeviceClick）
  Future<void> _onDeviceTap(RobotDevice device) async {
    if (device.ip.isNotEmpty && device.port > 0) {
      await _connect(device);
    } else {
      final cloud = ref
          .read(deviceStoreProvider.notifier)
          .findCloudDevice(device.id);
      if (cloud != null) {
        await _connectCloud(cloud);
      } else {
        AppToast.show('云端设备信息缺失', type: AppToastType.error);
      }
    }
  }

  /// 点击云端设备 → 信令远控（批次 6）
  Future<void> _connectCloud(CloudDevice cloud) async {
    final account = AccountService.instance;
    // 确保已加载 token（重启后可能未走个人页 init）
    await account.init();
    if (!account.isAuthenticated) {
      AppToast.show('请先登录', type: AppToastType.error);
      return;
    }
    AppToast.show('正在通过云端连接 ${cloud.robotName ?? cloud.robotId}...');
    // 主动发起连接：本次成功必须跳转（重置防重入标记）
    _navigatedToHome = false;
    final ok = await ref
        .read(connectionManagerProvider.notifier)
        .connectViaSignal(cloud.robotId);
    if (!mounted) return;
    if (!ok) {
      AppToast.show('云端连接失败', type: AppToastType.error);
      return;
    }
    // 主动连接成功：直接跳转主页（不依赖 listener，避免防重入标记导致不跳）
    _navigatedToHome = true;
    if (ref.read(connectionManagerProvider) == ConnState.connected) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const RobotHomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(deviceStoreProvider);
    final connection = ref.watch(connectionManagerProvider);
    // 合并列表：本地已保存设备 + 云端绑定设备（对齐 web-debug mergedDevices）
    final merged = ref.read(deviceStoreProvider.notifier).mergedDevices;

    // 连接成功后跳转机器人主页（对齐 web-debug：连接后进入功能主页）
    // 防重入：云端信令心跳超时→重连会让 state 经历 connected→disconnected→connected，
    // 若不加标记会二次 push RobotHomePage 覆盖当前遥控页（"画面出现就退出"根因之一）。
    ref.listen<ConnState>(connectionManagerProvider, (prev, next) {
      if (prev != ConnState.connected &&
          next == ConnState.connected &&
          mounted &&
          !_navigatedToHome) {
        _navigatedToHome = true;
        // 延迟跳转，避免绑定流程中的 connected 误触发
        Future.delayed(const Duration(milliseconds: 400), () {
          if (!context.mounted) return;
          if (ref.read(connectionManagerProvider) == ConnState.connected) {
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
                    // 合并列表标题 — 对齐 web-debug「设备列表」分区
                    _SectionTitle(title: '我的设备', count: merged.length),
                    if (merged.isEmpty)
                      _EmptySaved(onAdd: _openAddPage)
                    else
                      ...merged.map(
                        (device) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DeviceCard(
                            device: device,
                            connected:
                                store.currentDevice?.id == device.id &&
                                connection == ConnState.connected,
                            cloudOnline:
                                ref
                                    .read(deviceStoreProvider.notifier)
                                    .findCloudDevice(device.id)
                                    ?.status ==
                                'online',
                            locallyDiscovered: store.discovered.any(
                              (d) =>
                                  d.id == device.id ||
                                  (device.ip.isNotEmpty &&
                                      d.ip == device.ip &&
                                      d.port == device.port),
                            ),
                            onTap: () => _onDeviceTap(device),
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

  const _Header({required this.onRefresh, required this.onAdd});

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

  /// 云端设备在线状态（纯云端设备专用，本地设备忽略）
  final bool cloudOnline;

  /// 局域网 mDNS 发现列表是否包含该设备（本地在线判定，对齐 web-debug）
  final bool locallyDiscovered;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final VoidCallback? onForget;
  final VoidCallback? onDisconnect;

  const _DeviceCard({
    required this.device,
    required this.connected,
    required this.onTap,
    this.cloudOnline = false,
    this.locallyDiscovered = false,
    this.onRemove,
    this.onForget,
    this.onDisconnect,
  });

  /// 纯云端设备（无本地地址，来自 mergedDevices 的云端绑定设备）
  bool get _isCloudOnly => device.ip.isEmpty || device.port == 0;

  /// 本地在线判定（对齐 web-debug getOnlineStatusTag）：
  /// mDNS 发现列表中有此设备，或设备有有效 ip:port（已保存设备可能 mDNS 未发现但仍可达）
  bool get _isLocalOnline =>
      locallyDiscovered || (device.ip.isNotEmpty && device.port > 0);

  @override
  Widget build(BuildContext context) {
    // Pixso Component_1_2980 (408×139)：名称 → 基础状态行 → IP → 状态胶囊行
    // 云端设备（无 ip:port）复用同一卡片：名称 → robotId → 云端标识 → 状态胶囊
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
                  // 本地设备保留管理菜单；纯云端设备对齐 web-debug 侧边栏（无菜单）
                  if (!_isCloudOnly)
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
              // Row 2: 基础状态 — 本地设备显示信号/电量/延迟，云端设备显示 robotId
              _isCloudOnly
                  ? Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.6,
                        color: Color(0xFF6750A4),
                      ),
                    )
                  : _StatusRow(device: device),
              const SizedBox(height: 10),
              // Row 3: IP 行 — 云端设备显示「云端设备」标识 (对齐 web-debug 侧边栏)
              Text(
                _isCloudOnly ? '☁️ 云端设备' : '${device.ip}:${device.port}',
                style: const TextStyle(
                  fontSize: 11.6,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 10),
              // Row 4: 状态胶囊 (Pixso 1:2962, 灰底圆角胶囊)
              // 优先级对齐 web-debug getDeviceTags：
              // 已绑定 > 已保存 > 在线状态（本地在线 > 云端在线 > 离线）> 已连接
              Wrap(
                spacing: 10,
                runSpacing: 6,
                children: [
                  if (_isCloudOnly || device.bound) const _Tag('已绑定'),
                  if (!_isCloudOnly) const _Tag('已保存'),
                  // 在线状态（对齐 web-debug getOnlineStatusTag）
                  if (_isCloudOnly)
                    _Tag(cloudOnline ? '云端在线' : '离线')
                  else if (_isLocalOnline)
                    const _Tag('本地在线')
                  else if (cloudOnline)
                    const _Tag('云端在线')
                  else
                    const _Tag('离线'),
                  // 已连接 — web-debug 中与在线状态并存（独立追加）
                  if (connected) const _Tag('已连接'),
                  if (!_isCloudOnly) ...device.capabilityLabels.map(_Tag.new),
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
