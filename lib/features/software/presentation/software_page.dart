import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 软件管理页 — 匹配 Pixso 5:4810 + web-debug SoftwareView
///
/// 三个 tab：已安装 / 可安装 / 安装任务
/// 操作条(搜索) + 软件卡片列表(82px)
/// 数据源: software_list / software_available 消息 + software_progress/ack（安装任务）
class SoftwarePage extends ConsumerStatefulWidget {
  const SoftwarePage({super.key});
  @override
  ConsumerState<SoftwarePage> createState() => _SoftwarePageState();
}

class _SoftwarePageState extends ConsumerState<SoftwarePage> {
  String _keyword = '';
  bool _onlyInstalled = false;
  final _searchC = TextEditingController();

  /// 当前 tab：installed / available / tasks（对齐 web-debug activeTab）
  String _tab = 'installed';

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

  /// 发起安装/卸载/升级 — 本地立即创建任务并切到任务 tab（对齐 web-debug startTask）
  void _startTask(Software s, String action, {bool confirmCritical = false}) {
    // 关键服务升级需确认（对齐 web-debug）
    if (s.critical && action == 'upgrade' && !confirmCritical) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('升级关键服务'),
          content: Text('${s.displayName} 为关键服务，升级完成后需重新连接。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续升级'),
            ),
          ],
        ),
      ).then((ok) {
        if (ok == true) _startTask(s, action, confirmCritical: true);
      });
      return;
    }

    final store = ref.read(robotDataProvider.notifier);
    store.addSoftwareTask(
      SoftwareTask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        package: s.name,
        action: action,
        startedAt: DateTime.now(),
        fromVersion: action == 'upgrade' || action == 'uninstall'
            ? s.version
            : null,
      ),
    );

    final m = ref.read(connectionManagerProvider.notifier);
    if (action == 'install') {
      m.sendSoftwareInstall(s.name);
      AppToast.show('正在安装 ${s.displayName}...');
    } else if (action == 'uninstall') {
      m.sendSoftwareUninstall(s.name);
      AppToast.show('正在卸载 ${s.displayName}...');
    } else {
      m.sendSoftwareUpgrade(s.name);
      AppToast.show('正在升级 ${s.displayName}...');
    }
    setState(() => _tab = 'tasks');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final installed = store.softwareInstalled;
    final available = store.softwareAvailable;
    final tasks = store.softwareTasks;

    // 合并: 已安装 + 可安装（供搜索/筛选）
    var merged = <Software>[...installed];
    for (final a in available) {
      if (!merged.any((s) => s.name == a.name)) merged.add(a);
    }
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      merged = merged
          .where(
            (s) =>
                s.name.toLowerCase().contains(kw) ||
                s.displayName.toLowerCase().contains(kw),
          )
          .toList();
    }

    // 各 tab 显示对应列表（对齐 web-debug：已安装/可安装分离）
    var list = <Software>[];
    if (_tab == 'available') {
      list = merged.where((s) => !s.installed).toList();
    } else if (_tab == 'installed') {
      list = merged.where((s) => s.installed).toList();
    }
    if (_tab != 'tasks' && _onlyInstalled && _tab == 'installed') {
      list = list.where((s) => s.installed).toList();
    }

    final runningCount = tasks.where((t) => t.isRunning).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '软件管理'),
            // 三 tab（对齐 web-debug software-tabs）
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 6, 15, 6),
              child: Row(
                children: [
                  _TabBtn(
                    label: '已安装',
                    active: _tab == 'installed',
                    onTap: () => setState(() => _tab = 'installed'),
                  ),
                  const SizedBox(width: 8),
                  _TabBtn(
                    label: '可安装',
                    active: _tab == 'available',
                    onTap: () => setState(() => _tab = 'available'),
                  ),
                  const SizedBox(width: 8),
                  _TabBtn(
                    label: '安装任务',
                    active: _tab == 'tasks',
                    badge: runningCount,
                    onTap: () => setState(() => _tab = 'tasks'),
                  ),
                ],
              ),
            ),
            // 操作条（仅列表 tab 显示搜索/筛选）
            if (_tab != 'tasks') _buildActionBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  final m = ref.read(connectionManagerProvider.notifier);
                  m.sendGetSoftwareList();
                  m.sendGetSoftwareAvailable();
                },
                child: switch (_tab) {
                  'available' => _buildSoftwareList(list, showInstalled: false),
                  'tasks' => _buildTaskList(tasks),
                  _ => _buildSoftwareList(list, showInstalled: true),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoftwareList(List<Software> list, {required bool showInstalled}) {
    if (list.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(40),
        children: [
          Icon(
            showInstalled ? Icons.apps : Icons.download_outlined,
            size: 40,
            color: const Color(0xFFC7C7CC),
          ),
          const SizedBox(height: 12),
          Text(
            showInstalled ? '暂无已安装软件' : '暂无可安装软件',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
      itemCount: list.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _SoftwareCard(
          software: list[i],
          showUninstall: showInstalled,
          onInstall: () => _startTask(list[i], 'install'),
          onUninstall: () => _startTask(list[i], 'uninstall'),
          onUpgrade: () => _startTask(list[i], 'upgrade'),
        ),
      ),
    );
  }

  /// 安装任务列表 — 对齐 web-debug 安装任务 tab（进度条 + 阶段 + 输出 + 状态）
  Widget _buildTaskList(List<SoftwareTask> tasks) {
    // 倒序：最新任务在上
    final sorted = [...tasks.reversed];
    if (sorted.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(40),
        children: const [
          Icon(Icons.assignment_outlined, size: 40, color: Color(0xFFC7C7CC)),
          SizedBox(height: 12),
          Text(
            '暂无安装任务\n在「已安装/可安装」中发起操作后在此查看进度',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
      itemCount: sorted.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _TaskCard(task: sorted[i]),
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
                  border: Border.all(
                    color: const Color(0xFFD8D8D8),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      size: 16,
                      color: Color(0xFF8E8E93),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchC,
                        onChanged: (v) => setState(() => _keyword = v),
                        decoration: const InputDecoration(
                          hintText: '搜索软件',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8E8E93),
                          ),
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
            // 已安装筛选（仅已安装 tab 有意义）
            if (_tab == 'installed')
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

/// Tab 按钮 — 对齐 web-debug software-tabs
class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  const _TabBtn({
    required this.label,
    required this.active,
    this.badge = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0256FF) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? const Color(0xFF0256FF) : const Color(0xFFD8D8D8),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active ? Colors.white : const Color(0xFF3D3D3D),
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
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
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF3D3D3D)),
        ),
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
  /// 已安装 tab 才显示卸载；可安装 tab 显示安装
  final bool showUninstall;

  const _SoftwareCard({
    required this.software,
    required this.onInstall,
    required this.onUninstall,
    required this.onUpgrade,
    required this.showUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final installed = software.installed;
    final upgradable = software.upgradable ?? false;
    final critical = software.critical;
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
              software.icon ??
                  (software.name.isNotEmpty
                      ? software.name[0].toUpperCase()
                      : '?'),
              style: const TextStyle(fontSize: 24, color: Color(0xFF6750A4)),
            ),
          ),
          const SizedBox(width: 12),
          // 名称 + 描述 + 版本
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        software.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                    if (critical) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.lock_outline,
                        size: 12,
                        color: Color(0xFF8E8E93),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  installed ? '当前版本 ${software.version ?? "--"}' : '未安装',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  software.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF898989),
                  ),
                ),
              ],
            ),
          ),
          // 操作按钮（对齐 web-debug：升级优先，卸载次之，安装独立 tab）
          if (!installed)
            _ActionBtn(label: '安装', onTap: onInstall)
          else if (upgradable)
            _ActionBtn(label: '升级', onTap: onUpgrade)
          else if (showUninstall)
            _ActionBtn(
              label: critical ? '🔒 卸载' : '卸载',
              onTap: critical ? null : onUninstall,
            )
          else
            const Text(
              '已是最新',
              style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
        ],
      ),
    );
  }
}

/// 安装任务卡片 — 对齐 web-debug task-card（进度条 + 阶段 + 输出 + 状态）
class _TaskCard extends StatelessWidget {
  final SoftwareTask task;
  const _TaskCard({required this.task});

  String get _actionLabel => switch (task.action) {
    'install' => '安装',
    'uninstall' => '卸载',
    _ => '升级',
  };

  String get _statusLabel => switch (task.status) {
    'success' => '成功',
    'failed' => '失败',
    _ => '进行中',
  };

  Color get _actionColor => switch (task.action) {
    'install' => const Color(0xFF0256FF),
    'uninstall' => const Color(0xFFFF453A),
    _ => const Color(0xFFFF9500),
  };

  String get _versionChange {
    final from = task.fromVersion;
    final to = task.toVersion;
    if (from != null && to != null) return '$from → $to';
    if (to != null) return '→ $to';
    if (from != null && task.status == 'success') return '$from → 已移除';
    return '';
  }

  String get _durationText {
    final end = task.completedAt ?? DateTime.now();
    final s = end.difference(task.startedAt).inSeconds;
    if (s < 60) return '${s}s';
    return '${s ~/ 60}m${s % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final running = task.isRunning;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：action 标签 + 包名 + 版本变化 + 状态
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _actionLabel,
                  style: TextStyle(fontSize: 11, color: _actionColor),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.package,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
              ),
              if (_versionChange.isNotEmpty)
                Text(
                  _versionChange,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: running
                      ? const Color(0xFFF0F0F0)
                      : task.status == 'success'
                      ? const Color(0x1A34C759)
                      : const Color(0x1AFF453A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: running
                        ? const Color(0xFF0256FF)
                        : task.status == 'success'
                        ? const Color(0xFF34C759)
                        : const Color(0xFFFF453A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (running) ...[
            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (task.progress / 100).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFFF0F0F0),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF0256FF)),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.stage.isEmpty ? '等待中' : task.stage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ),
                Text(
                  '${task.progress.round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
            if (task.output.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F8),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.output,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.4,
                    color: Color(0xFF636366),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ] else
            Text(
              '耗时 $_durationText',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _ActionBtn({required this.label, this.onTap});

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
          border: Border.all(
            color: onTap == null ? const Color(0xFFC7C7CC) : const Color(0xFF0256FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: onTap == null ? const Color(0xFFC7C7CC) : const Color(0xFF0256FF),
          ),
        ),
      ),
    );
  }
}
