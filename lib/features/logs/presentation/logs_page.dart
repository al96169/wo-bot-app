import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 日志页 — 匹配 Pixso 5:1694
///
/// 操作条(搜索/级别筛选/顺序/导出) + 日志流列表
/// 数据源: requestLogs({mode: tail/since/before}) + logs 消息
class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  String _keyword = '';
  String _level = 'all';

  /// 是否倒序显示（最新在上）。默认倒序。
  bool _descending = true;
  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchTail();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  void _fetchTail() {
    ref
        .read(connectionManagerProvider.notifier)
        .requestLogs(level: _level == 'all' ? '' : _level);
  }

  void _fetchNew() {
    final store = ref.read(robotDataProvider.notifier);
    if (store.logCursor == 0) {
      _fetchTail();
      return;
    }
    ref
        .read(connectionManagerProvider.notifier)
        .requestLogs(
          mode: 'since',
          sinceLine: store.logCursor,
          level: _level == 'all' ? '' : _level,
        );
  }

  void _fetchOlder() {
    final store = ref.read(robotDataProvider.notifier);
    if (store.logs.isEmpty || !store.logHasMore) return;
    final oldest = store.logs.first.lineNo;
    if (oldest <= 0) return;
    ref
        .read(connectionManagerProvider.notifier)
        .requestLogs(
          mode: 'before',
          beforeLine: oldest,
          level: _level == 'all' ? '' : _level,
        );
  }

  /// 导出日志 — 复制到剪贴板（web/移动端通用）
  Future<void> _exportLogs(List<LogEntry> logs) async {
    if (logs.isEmpty) {
      AppToast.show('暂无可导出的日志');
      return;
    }
    final sb = StringBuffer();
    for (final l in logs) {
      sb.writeln('[$l.time] [$l.level] [$l.source] $l.message');
    }
    await Clipboard.setData(ClipboardData(text: sb.toString()));
    if (mounted) {
      AppToast.show('已复制 ${logs.length} 条日志到剪贴板', type: AppToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    var logs = store.logs;

    // 关键字过滤
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      logs = logs
          .where(
            (l) =>
                l.message.toLowerCase().contains(kw) ||
                l.source.toLowerCase().contains(kw),
          )
          .toList();
    }
    // 级别过滤
    if (_level != 'all') {
      logs = logs.where((l) => l.level == _level).toList();
    }
    // 顺序：默认倒序（最新在上），点击切换正序（最早在上）
    if (_descending) logs = logs.reversed.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '日志'),
            // 操作条 (Pixso 5:2120, 40px)
            _buildActionBar(logs),
            // 日志列表
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _fetchNew(),
                child: _buildLogList(logs),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(List<LogEntry> logs) {
    if (logs.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(40),
        children: const [
          Icon(Icons.receipt_long_outlined, size: 40, color: Color(0xFFC7C7CC)),
          SizedBox(height: 12),
          Text(
            '暂无日志\n下拉刷新或切换级别筛选重试',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
          ),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // 滚动到底部时加载更早日志
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 80) {
          _fetchOlder();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
        itemCount: logs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '共 ${logs.length} 条日志，下拉刷新，滚动到底加载更多',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
            );
          }
          final log = logs[i - 1];
          return _LogRow(log: log);
        },
      ),
    );
  }

  Widget _buildActionBar(List<LogEntry> logs) {
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            // 搜索输入框 (Pixso 5:2551)
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
                          hintText: '搜索日志',
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
            // 级别筛选 (Pixso 5:2553)
            _FilterChip(
              label: _level,
              onTap: () {
                showModalBottomSheet<String>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: ['all', 'debug', 'info', 'warn', 'error']
                          .map(
                            (l) => ListTile(
                              title: Text(l),
                              trailing: l == _level
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => Navigator.pop(ctx, l),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ).then((v) {
                  if (v != null) {
                    setState(() => _level = v);
                    _fetchTail();
                  }
                });
              },
            ),
            const SizedBox(width: 8),
            // 顺序切换 (Pixso 5:2555)
            _FilterChip(
              label: _descending ? '倒序' : '顺序',
              onTap: () => setState(() => _descending = !_descending),
            ),
            const SizedBox(width: 8),
            // 导出 (Pixso 5:2558)
            _FilterChip(label: '导出', onTap: () => _exportLogs(logs)),
          ],
        ),
      ),
    );
  }
}

/// 操作条小按钮 — 匹配 Pixso 5:2553 (白底圆角15 高30)
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

/// 日志行 — 时间 + 级别 + 来源 + 消息
class _LogRow extends StatelessWidget {
  final LogEntry log;
  const _LogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final levelColor = switch (log.level) {
      'error' => const Color(0xFFFF3B30),
      'warn' || 'warning' => const Color(0xFFFF9500),
      'debug' => const Color(0xFF8E8E93),
      _ => const Color(0xFF3D3D3D),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间 11sp
          SizedBox(
            width: 62,
            child: Text(
              _time(log.time),
              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ),
          // 级别标记
          Container(
            width: 34,
            alignment: Alignment.center,
            child: Text(
              log.level,
              style: TextStyle(
                fontSize: 10,
                color: levelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 来源
          SizedBox(
            width: 70,
            child: Text(
              log.source,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6750A4)),
            ),
          ),
          // 消息
          Expanded(
            child: Text(
              log.message,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1C1C1E)),
            ),
          ),
        ],
      ),
    );
  }

  String _time(String time) {
    final parts = time.split(' ');
    if (parts.length >= 2) return parts[1].split(',')[0];
    return time;
  }
}
