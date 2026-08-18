import 'dart:async';
import 'package:flutter/material.dart';

/// Toast 类型 — 匹配 web-debug appStore.showToast(message, type)
enum AppToastType { success, error, info }

/// 全局 Toast — 对齐 web-debug 行为
///
/// - 3 秒自动消失
/// - 相同消息去重（同类型同文案不重复弹）
/// - 顶部弹出，成功绿 / 错误红 / 信息蓝
class AppToast {
  AppToast._();

  static AppToastType? _currentType;
  static String? _currentMessage;
  static Timer? _timer;
  static OverlayEntry? _entry;
  static BuildContext? _overlayContext;

  /// 注册 Overlay 上下文（MaterialApp builder 中调用一次）
  static void register(BuildContext context) {
    _overlayContext = context;
  }

  /// 显示 Toast
  static void show(String message, {AppToastType type = AppToastType.info}) {
    if (message.isEmpty) return;
    // 同消息去重：相同类型+文案时不重复弹出
    if (_currentMessage == message && _currentType == type) return;

    _timer?.cancel();
    _removeEntry();

    _currentMessage = message;
    _currentType = type;
    _showEntry(message, type);

    _timer = Timer(const Duration(seconds: 3), () {
      _removeEntry();
      _currentMessage = null;
      _currentType = null;
    });
  }

  /// 立即清除
  static void dismiss() {
    _timer?.cancel();
    _removeEntry();
    _currentMessage = null;
    _currentType = null;
  }

  static void _showEntry(String message, AppToastType type) {
    final ctx = _overlayContext;
    if (ctx == null) return;
    final overlay = Overlay.of(ctx, rootOverlay: true);

    _entry = OverlayEntry(
      builder: (context) => _AppToastView(message: message, type: type),
    );
    overlay.insert(_entry!);
  }

  static void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }
}

class _AppToastView extends StatelessWidget {
  final String message;
  final AppToastType type;

  const _AppToastView({required this.message, required this.type});

  @override
  Widget build(BuildContext context) {
    final (Color bg, IconData icon) = switch (type) {
      AppToastType.success => (const Color(0xFF34C759), Icons.check_circle),
      AppToastType.error => (const Color(0xFFFF3B30), Icons.error),
      AppToastType.info => (const Color(0xFF0256FF), Icons.info),
    };

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
