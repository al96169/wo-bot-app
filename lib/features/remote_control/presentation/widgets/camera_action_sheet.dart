import 'package:flutter/material.dart';

/// 遥控功能弹窗按钮项
class ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;

  const ActionItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.active = false,
  });
}

/// 摄像头功能弹窗 — 拍照/录像切换/画质/图库入口/云台归位
///
/// 以底部弹层呼出（对齐需求：功能使用按钮弹窗呼出）
class CameraActionSheet extends StatelessWidget {
  final bool isRecording;
  final String recordTime;
  final String quality;
  final VoidCallback onCapture;
  final VoidCallback onRecordToggle;
  final void Function(String mode) onQualityChange;
  final VoidCallback onGallery;
  final VoidCallback onGimbalCenter;

  const CameraActionSheet({
    super.key,
    required this.isRecording,
    required this.recordTime,
    required this.quality,
    required this.onCapture,
    required this.onRecordToggle,
    required this.onQualityChange,
    required this.onGallery,
    required this.onGimbalCenter,
  });

  static const _qualities = [
    ('auto', '自动'),
    ('high', '高画质'),
    ('medium', '中画质'),
    ('low', '低画质'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '摄像头功能',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ActionButton(icon: Icons.photo_camera, label: '拍照', onTap: onCapture),
                _ActionButton(
                  icon: isRecording ? Icons.stop : Icons.fiber_manual_record,
                  label: isRecording ? '停止录像' : '录像',
                  color: const Color(0xFFFF3B30),
                  active: isRecording,
                  onTap: onRecordToggle,
                ),
                _ActionButton(icon: Icons.photo_library, label: '图库', onTap: onGallery),
                _ActionButton(icon: Icons.center_focus_strong, label: '云台归位', onTap: onGimbalCenter),
              ],
            ),
            const SizedBox(height: 12),
            // 录制状态
            if (isRecording)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 10, color: Color(0xFFFF3B30)),
                    const SizedBox(width: 6),
                    Text(
                      'REC $recordTime',
                      style: const TextStyle(fontSize: 12, color: Color(0xFFFF3B30)),
                    ),
                  ],
                ),
              ),
            // 画质
            const Text('直播画质', style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in _qualities)
                  ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: quality == value,
                    onSelected: (_) => onQualityChange(value),
                    selectedColor: const Color(0xFF0256FF),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: quality == value ? Colors.white : const Color(0xFF3D3D3D),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 弹窗内操作按钮（竖向：图标 + 文字）
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF0256FF);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.12) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? c : const Color(0xFFE5E5E5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: c),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
      ),
    );
  }
}
