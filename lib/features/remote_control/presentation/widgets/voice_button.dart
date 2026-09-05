import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/network/connection_manager.dart';
import '../../../../core/utils/app_toast.dart';

/// 对讲组件 — 支持两种模式（对齐 web-debug RemoteView）：
/// - 喊话（record）：按住录音（AAC）→ 松开发送 voice_broadcast mode=record
/// - 电话（phone）：点击开关，实时采集 PCM（48kHz mono）流式发送 mode=phone
///
/// 底部对讲按钮按住=喊话；右侧小按钮切换/使用电话模式。
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

  // ---- 电话模式状态 ----
  bool _phoneActive = false;
  StreamSubscription<Uint8List>? _phoneSub;
  final List<Uint8List> _pcmAccumulator = [];
  Timer? _phoneSendTimer;

  @override
  void dispose() {
    _maxTimer?.cancel();
    _phoneSendTimer?.cancel();
    _phoneSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  // ==================== 喊话模式（record） ====================

  void _startRecord() {
    if (kIsWeb) {
      AppToast.show('对讲需在 App 真机使用（Web 不支持录音）');
      return;
    }
    _doStartRecord();
  }

  Future<void> _doStartRecord() async {
    if (_recording || _phoneActive) return;
    try {
      if (!await _recorder.hasPermission()) {
        AppToast.show('无麦克风权限', type: AppToastType.error);
        return;
      }
      final dir = await getTemporaryDirectory();
      _recordPath =
          '${dir.path}/voice_broadcast_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(sampleRate: 48000, numChannels: 1),
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
    manager.sendBinaryMessage('voice_broadcast', {
      'mode': 'record',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    }, bytes);
    AppToast.show('喊话已发送', type: AppToastType.success);
  }

  // ==================== 电话模式（phone，PCM 实时流） ====================

  /// 电话模式开关：点击开始实时 PCM 对讲，再点停止
  Future<void> _togglePhone() async {
    if (_phoneActive) {
      await _stopPhone();
    } else {
      await _startPhone();
    }
  }

  Future<void> _startPhone() async {
    if (_phoneActive || _recording) return;
    try {
      if (!await _recorder.hasPermission()) {
        AppToast.show('无麦克风权限', type: AppToastType.error);
        return;
      }
      _pcmAccumulator.clear();
      // 采集 48kHz mono PCM16 原始流（record pcm16bits = Linear PCM，无容器头）
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 48000,
          numChannels: 1,
        ),
      );
      _phoneSub = stream.listen((chunk) {
        // 剥离可能的 WAV/RIFF 容器头（部分平台 pcm16bits 带 header）
        _pcmAccumulator.add(_stripContainerHeader(chunk));
      });
      // 每 200ms 批量发送累积 PCM（对齐 web-debug 200ms 批量）
      _phoneSendTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_pcmAccumulator.isEmpty) return;
        final chunks = List<Uint8List>.from(_pcmAccumulator);
        _pcmAccumulator.clear();
        final totalLen = chunks.fold<int>(0, (s, c) => s + c.length);
        if (totalLen == 0) return;
        final combined = Uint8List(totalLen);
        var offset = 0;
        for (final c in chunks) {
          combined.setRange(offset, offset + c.length, c);
          offset += c.length;
        }
        final manager = ref.read(connectionManagerProvider.notifier);
        manager.sendBinaryMessage(
          'voice_broadcast',
          {
            'mode': 'phone',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'format': 'pcm_s16le',
            'rate': 48000,
          },
          combined,
          preferDataChannel: true, // 电话模式低延迟优先 DataChannel
        );
      });
      setState(() => _phoneActive = true);
      AppToast.show('电话对讲已开启（再点结束）', type: AppToastType.info);
    } catch (e) {
      debugPrint('[Voice] 电话模式启动失败: $e');
      AppToast.show('电话对讲不可用', type: AppToastType.error);
    }
  }

  Future<void> _stopPhone() async {
    _phoneSendTimer?.cancel();
    _phoneSendTimer = null;
    try {
      await _phoneSub?.cancel();
    } catch (_) {}
    _phoneSub = null;
    _pcmAccumulator.clear();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _phoneActive = false);
    AppToast.show('电话对讲已结束', type: AppToastType.info);
  }

  /// 剥离可能的 WAV/RIFF 容器头，保留裸 PCM 数据
  Uint8List _stripContainerHeader(Uint8List chunk) {
    // WAV: 前 4 字节 "RIFF"，需跳过文件头 + data 头到数据区
    if (chunk.length > 44 &&
        chunk[0] == 0x52 &&
        chunk[1] == 0x49 &&
        chunk[2] == 0x46 &&
        chunk[3] == 0x46) {
      // RIFF header; 查找 "data" 子块（偏移 36-39）
      if (chunk.length > 40 &&
          chunk[36] == 0x64 &&
          chunk[37] == 0x61 &&
          chunk[38] == 0x74 &&
          chunk[39] == 0x61) {
        final dataSize =
            chunk[40] |
            (chunk[41] << 8) |
            (chunk[42] << 16) |
            (chunk[43] << 24);
        final start = 44;
        final end = (start + dataSize).clamp(0, chunk.length);
        return Uint8List.sublistView(chunk, start, end);
      }
    }
    return chunk; // 已是裸 PCM
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 电话模式开关小按钮（对齐 web-debug 电话模式 toggle）
        GestureDetector(
          onTap: _togglePhone,
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _phoneActive
                  ? const Color(0xFF34C759)
                  : const Color(0xFF1C1C1E).withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(
                color: _phoneActive
                    ? const Color(0xFF34C759)
                    : const Color(0x66FFFFFF),
                width: 1,
              ),
            ),
            child: Icon(
              _phoneActive ? Icons.phone_in_talk : Icons.phone,
              size: 18,
              color: _phoneActive ? Colors.white : const Color(0xCCFFFFFF),
            ),
          ),
        ),
        // 按住喊话主按钮
        GestureDetector(
          onTapDown: (_) => _startRecord(),
          onTapUp: (_) => _stopAndSend(),
          onTapCancel: _stopAndSend,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _phoneActive
                  ? const Color(0xFF34C759)
                  : _recording
                  ? const Color(0xFFFF3B30)
                  : const Color(0xFF0256FF),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color:
                      (_recording
                              ? const Color(0xFFFF3B30)
                              : const Color(0xFF0256FF))
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
                  _phoneActive
                      ? '电话对讲中'
                      : _recording
                      ? '松开发送...'
                      : '按住喊话',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
