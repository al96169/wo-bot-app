import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/network/connection_manager.dart';
import '../../../../core/utils/app_toast.dart';

/// 对讲按钮 — 按住说话（push-to-talk）
///
/// 录音（AAC）→ 松开发送 voice_broadcast（record 模式，走 WebSocket 二进制）
/// 对齐 web-debug RemoteView 喊话（record 模式）；电话模式（PCM 直传）后续迭代
/// Web 端不支持本地录音（record 插件），显示提示降级
class VoiceButton extends ConsumerStatefulWidget {
  const VoiceButton({super.key});

  @override
  ConsumerState<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends ConsumerState<VoiceButton> {
  final AudioRecorder _recorder = AudioRecorder();
  String? _recordPath;
  bool _recording = false;
  Timer? _maxTimer;

  @override
  void dispose() {
    _maxTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _startRecord() {
    if (kIsWeb) {
      AppToast.show('对讲需在 App 真机使用（Web 不支持录音）');
      return;
    }
    _doStartRecord();
  }

  Future<void> _doStartRecord() async {
    if (_recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        AppToast.show('无麦克风权限', type: AppToastType.error);
        return;
      }
      final dir = await getTemporaryDirectory();
      _recordPath = '${dir.path}/voice_broadcast_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          sampleRate: 48000,
          numChannels: 1,
        ),
        path: _recordPath!,
      );
      setState(() => _recording = true);
      // 60 秒上限
      _maxTimer = Timer(const Duration(seconds: 60), _stopAndSend);
    } catch (e) {
      debugPrint('[Voice] 录音启动失败: $e');
      AppToast.show('麦克风不可用', type: AppToastType.error);
    }
  }

  Future<void> _stopAndSend() async {
    if (!_recording) return;
    _maxTimer?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      debugPrint('[Voice] 停止录音失败: $e');
    }
    setState(() => _recording = false);
    if (path == null || !File(path).existsSync()) return;

    final bytes = await File(path).readAsBytes();
    final manager = ref.read(connectionManagerProvider.notifier);
    manager.sendBinaryMessage(
      'voice_broadcast',
      {'mode': 'record', 'timestamp': DateTime.now().millisecondsSinceEpoch},
      bytes,
    );
    AppToast.show('喊话已发送', type: AppToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startRecord(),
      onTapUp: (_) => _stopAndSend(),
      onTapCancel: _stopAndSend,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _recording ? const Color(0xFFFF3B30) : const Color(0xFF0256FF),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (_recording ? const Color(0xFFFF3B30) : const Color(0xFF0256FF))
                  .withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _recording ? Icons.mic : Icons.mic_none,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              _recording ? '松开发送...' : '按住对讲',
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
