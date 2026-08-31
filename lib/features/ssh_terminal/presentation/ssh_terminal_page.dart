import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../shared/models/robot_data.dart';

/// SSH 终端页（批次 7）— 对齐 web-debug BottomPanel SSH 终端
///
/// 命令透传（exec_result）：输入命令回车 → sendExec(command) →
/// exec_result 的 stdout/stderr 分行追加到 RobotDataStore.sshOutput。
/// 支持 cd 命令（机器人端维护会话 cwd，通过 exec_result.cwd 同步显示）。
class SshTerminalPage extends ConsumerStatefulWidget {
  const SshTerminalPage({super.key});

  /// 打开 SSH 终端页
  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SshTerminalPage()));
  }

  @override
  ConsumerState<SshTerminalPage> createState() => _SshTerminalPageState();
}

class _SshTerminalPageState extends ConsumerState<SshTerminalPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 连接成功后自动发一条欢迎提示（对齐 web-debug：未连接时提示先连设备）
    Future.microtask(() {
      final store = ref.read(robotDataProvider.notifier);
      if (store.sshOutput.isEmpty) {
        store.addSshOutput('hint', 'SSH 终端已就绪 — 输入命令后回车执行（支持 cd 切换目录）');
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final cmd = _input.text.trim();
    if (cmd.isEmpty || _sending) return;
    setState(() => _sending = true);
    final store = ref.read(robotDataProvider.notifier);
    final manager = ref.read(connectionManagerProvider.notifier);
    // 用户输入回显（对齐 web-debug addSSHOutput({type:'cmd'})）
    store.addSshOutput('cmd', cmd);
    manager.sendExec(cmd);
    _input.clear();
    _scrollToBottom();
    // 短时锁定防连发
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _sending = false);
    });
  }

  void _clear() {
    ref.read(robotDataProvider.notifier).clearSshOutput();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _connected {
    final manager = ref.read(connectionManagerProvider);
    return manager == ConnState.connected;
  }

  @override
  Widget build(BuildContext context) {
    // robotDataProvider: StateNotifierProvider<RobotDataStore, int>
    // watch 版本号触发重建，数据通过 notifier 读取
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final connected = _connected;
    final output = store.sshOutput;
    // 新输出时自动滚动到底部
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2C2C2E),
        foregroundColor: Colors.white,
        title: const Text('SSH 终端'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 状态条：连接状态 + 当前工作目录 + 清屏
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected
                          ? const Color(0xFF34C759)
                          : const Color(0xFFFF453A),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      connected ? 'Terminal · ${store.shellCwd}' : '未连接设备',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _clear,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8E8E93),
                    ),
                    child: const Text('清屏', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF3A3A3C), height: 1),
            // 输出区
            Expanded(
              child: !connected
                  ? const Center(
                      child: Text(
                        '请先连接设备后再使用 SSH 终端',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: output.length,
                      itemBuilder: (context, i) => _buildLine(output[i]),
                    ),
            ),
            const Divider(color: Color(0xFF3A3A3C), height: 1),
            // 输入条
            Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                8,
                8,
                8 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _input,
                        enabled: connected,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          fontFamily: 'monospace',
                        ),
                        cursorColor: const Color(0xFF0A84FF),
                        decoration: const InputDecoration(
                          hintText: '输入命令后回车...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF636366),
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: connected ? _send : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0A84FF),
                      disabledBackgroundColor: const Color(0xFF3A3A3C),
                    ),
                    child: const Text('发送'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 输出行：cmd=用户命令(高亮) / out=stdout(白) / err=stderr(红) / hint=提示(灰)
  Widget _buildLine(SshOutputEntry entry) {
    Color color;
    FontWeight weight = FontWeight.normal;
    switch (entry.type) {
      case 'cmd':
        color = const Color(0xFF0A84FF);
        weight = FontWeight.w600;
        break;
      case 'err':
        color = const Color(0xFFFF453A);
        break;
      case 'hint':
        color = const Color(0xFF636366);
        break;
      default:
        color = const Color(0xFFE5E5EA);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        entry.text,
        style: TextStyle(
          fontSize: 12.5,
          color: color,
          fontWeight: weight,
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    );
  }
}
