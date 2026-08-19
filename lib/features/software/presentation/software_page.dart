import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 软件管理页 — 匹配 Pixso 5:4810
///
/// 操作条(搜索/已安装筛选/安装任务) + 软件卡片列表(82px)
/// 数据源: software_list / software_available 消息 + sendSoftwareAction
class SoftwarePage extends ConsumerStatefulWidget {
  const SoftwarePage({super.key});
  @override
  ConsumerState<SoftwarePage> createState() => _SoftwarePageState();
}

class _SoftwarePageState extends ConsumerState<SoftwarePage> {
  String _keyword = '';
  bool _onlyInstalled = false;
  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    final m = ref.read(connectionManagerProvider.notifier);
    m.sendGetSoftwareList();
    m.sendGetSoftwareAvailable();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  void _install(Software s) {
    ref.read(connectionManagerProvider.notifier).sendSoftwareInstall(s.name);
    AppToast.show('正在安装 ${s.displayName}...', type: AppToastType.info);
  }

  void _uninstall(Software s) {
    ref.read(connectionManagerProvider.notifier).sendSoftwareUninstall(s.name);
    AppToast.show('正在卸载 ${s.displayName}...', type: AppToastType.info);
  }

  void _upgrade(Software s) {
    ref.read(connectionManagerProvider.notifier).sendSoftwareUpgrade(s.name);
    AppToast.show('正在升级 ${s.displayName}...', type: AppToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final installed = store.softwareInstalled;
    final available = store.softwareAvailable;

    // 合并: 已安装 + 可安装
    var list = <Software>[...installed];
    for (final a in available) {
      if (!list.any((s) => s.name == a.name)) list.add(a);
    }
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      list = list.where((s) => s.name.toLowerCase().contains(kw) || s.displayName.toLowerCase().contains(kw)).toList();
    }
    if (_onlyInstalled) {
      list = list.where((s) => s.installed).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '软件管理'),
            _buildActionBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final m = ref.read(connectionManagerProvider.notifier);
                  m.sendGetSoftwareList();
                  m.sendGetSoftwareAvailable();
                },
                child: list.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(40),
                        children: const [
                          Icon(Icons.apps, size: 40, color: Color(0xFFC7C7CC)),
                          SizedBox(height: 12),
                          Text(
                            '暂无软件\n下拉刷新重试',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
                        itemCount: list.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _SoftwareCard(
                            software: list[i],
                            onInstall: () => _install(list[i]),
                            onUninstall: () => _uninstall(list[i]),
                            onUpgrade: () => _upgrade(list[i]),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            // 搜索输入框
            Expanded(
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 16, color: Color(0xFF8E8E93)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchC,
                        onChanged: (v) => setState(() => _keyword = v),
                        decoration: const InputDecoration(
                          hintText: '搜索软件',
                          hintStyle: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 已安装筛选
            _FilterChip(
              label: _onlyInstalled ? '已安装 ✓' : '已安装',
              onTap: () => setState(() => _onlyInstalled = !_onlyInstalled),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF3D3D3D))),
      ),
    );
  }
}

/// 软件卡片 — 匹配 Pixso 5:4948 (398×82)
class _SoftwareCard extends StatelessWidget {
  final Software software;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  final VoidCallback onUpgrade;

  const _SoftwareCard({
    required this.software,
    required this.onInstall,
    required this.onUninstall,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final installed = software.installed;
    final upgradable = software.upgradable ?? false;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Row(
        children: [
          // 图标 66×66 (Pixso 5:4926)
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F0FA),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              software.icon ?? (software.name.isNotEmpty ? software.name[0].toUpperCase() : '?'),
              style: const TextStyle(fontSize: 24, color: Color(0xFF6750A4)),
            ),
          ),
          const SizedBox(width: 12),
          // 名称 + 描述 + 版本
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  software.displayName,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E)),
                ),
                const SizedBox(height: 2),
                Text(
                  installed ? '当前版本 ${software.version ?? "--"}' : '未安装',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 2),
                Text(
                  software.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF898989)),
                ),
              ],
            ),
          ),
          // 操作按钮
          if (!installed)
            _ActionBtn(label: '安装', onTap: onInstall)
          else if (upgradable)
            _ActionBtn(label: '升级', onTap: onUpgrade)
          else
            _ActionBtn(label: '卸载', onTap: onUninstall),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF0256FF), width: 1),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF0256FF))),
      ),
    );
  }
}
