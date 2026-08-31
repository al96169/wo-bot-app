import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../shared/models/robot_data.dart';

/// 命令日志面板（批次 7）— 对齐 web-debug BottomPanel「控制指令」tab
///
/// 展示 ConnectionManager 各操作发送/接收的指令记录（sendExec 等已埋点）。
class CommandLogPage extends ConsumerWidget {
  const CommandLogPage({super.key});

  /// 打开命令日志页
  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CommandLogPage()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // robotDataProvider: StateNotifierProvider<RobotDataStore, int>
    // watch 版本号触发重建，数据通过 notifier 读取
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final logs = store.cmdLogs;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: const Text('控制指令'),
        actions: [
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: logs.isEmpty
                ? null
                : () => ref.read(robotDataProvider.notifier).clearCmdLogs(),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text(
                '暂无指令记录',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: logs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _CmdRow(entry: logs[i]),
            ),
    );
  }
}

class _CmdRow extends StatelessWidget {
  final CommandLogEntry entry;
  const _CmdRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isSend = entry.direction == 'send';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 方向箭头 + 时间
          SizedBox(
            width: 58,
            child: Text(
              isSend ? '↑' : '↓',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSend
                    ? const Color(0xFF6750A4)
                    : const Color(0xFF34C759),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 类型 + 数据
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.type,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.data,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1C1C1E),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
