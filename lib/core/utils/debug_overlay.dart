import 'package:flutter/material.dart';

/// 全局调试日志缓冲——跨页面可见
class DebugLogBuffer {
  static final List<String> _logs = [];
  static const _maxLines = 200;

  static List<String> get logs => List.unmodifiable(_logs);

  static void add(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _logs.add('[$ts] $msg');
    if (_logs.length > _maxLines) _logs.removeAt(0);
  }

  static void clear() => _logs.clear();
}

/// 可放在任何页面底部的调试日志面板（半透明覆盖）
class DebugLogOverlay extends StatefulWidget {
  final double height;
  const DebugLogOverlay({super.key, this.height = 120});

  @override
  State<DebugLogOverlay> createState() => _DebugLogOverlayState();
}

class _DebugLogOverlayState extends State<DebugLogOverlay> {
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _version = DebugLogBuffer.logs.length;
  }

  @override
  Widget build(BuildContext context) {
    // 每帧检查是否有新日志
    if (_version != DebugLogBuffer.logs.length) {
      _version = DebugLogBuffer.logs.length;
      Future.microtask(() => setState(() {}));
    }
    final logs = DebugLogBuffer.logs;
    if (logs.isEmpty) return const SizedBox.shrink();

    return Container(
      height: widget.height,
      width: double.infinity,
      color: const Color(0xCC000000),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (_, i) => Text(
                logs[i],
                style: TextStyle(
                  fontSize: 9,
                  fontFamily: 'monospace',
                  color: _logColor(logs[i]),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          const Text('📋 DEBUG LOG', style: TextStyle(color: Colors.green, fontSize: 9, fontWeight: FontWeight.bold)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              DebugLogBuffer.clear();
              setState(() {});
            },
            child: const Text('CLEAR', style: TextStyle(color: Colors.red, fontSize: 9)),
          ),
        ],
      ),
    );
  }

  Color _logColor(String msg) {
    if (msg.contains('[WS]') || msg.contains('[CM]')) return Colors.cyan;
    if (msg.contains('ERROR') || msg.contains('失败') || msg.contains('error')) return Colors.red;
    if (msg.contains('成功') || msg.contains('OK')) return Colors.green;
    return Colors.white70;
  }
}
