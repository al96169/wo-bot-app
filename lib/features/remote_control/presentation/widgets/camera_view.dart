import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// 单摄像头画面 — 主摄/副摄通用
///
/// 有视频流 → RTCVideoView 渲染；无流 → 占位提示；录制中 → 红色边框
class CameraView extends StatefulWidget {
  final MediaStream? stream;
  final String label;
  final bool enabled;
  final bool recording;
  final RTCVideoViewObjectFit objectFit;

  const CameraView({
    super.key,
    required this.stream,
    required this.label,
    this.enabled = true,
    this.recording = false,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _rendererReady = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  /// 初始化 renderer（web 上 initialize 可能抛错，隔离避免 Uncaught Error）
  void _initRenderer() {
    _renderer.initialize().then((_) {
      if (mounted) {
        setState(() => _rendererReady = true);
        if (widget.stream != null) {
          _renderer.srcObject = widget.stream;
        }
      }
    }).catchError((Object e) {
      debugPrint('[CameraView] renderer 初始化失败: $e');
    });
  }

  @override
  void didUpdateWidget(covariant CameraView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream && _rendererReady) {
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasStream =
        widget.stream != null && widget.enabled && _rendererReady;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(10),
        border: widget.recording
            ? Border.all(color: const Color(0xFFFF3B30), width: 2)
            : Border.all(color: const Color(0xFF3A3A3C)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 视频流
          if (hasStream)
            RTCVideoView(
              _renderer,
              objectFit: widget.objectFit,
            )
          else
            _Placeholder(label: widget.label, waiting: widget.enabled),
          // 录制标记
          if (widget.recording)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xCCFF3B30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'REC',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 标签
          Positioned(
            bottom: 6,
            left: 8,
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 10, color: Color(0xAAFFFFFF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 占位（无流 / 未开启）
class _Placeholder extends StatelessWidget {
  final String label;
  final bool waiting;
  const _Placeholder({required this.label, required this.waiting});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            waiting ? Icons.videocam : Icons.videocam_off,
            size: 32,
            color: const Color(0xFF555557),
          ),
          const SizedBox(height: 6),
          Text(
            waiting ? '等待视频流...' : label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}
