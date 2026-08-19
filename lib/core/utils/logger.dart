import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'debug_overlay.dart';

/// 应用日志工具
class AppLogger {
  AppLogger._();

  static bool _debugMode = false;

  /// 开启/关闭调试输出
  static void setDebugMode(bool enabled) {
    _debugMode = enabled;
  }

  static void info(String message, {String? tag}) {
    _log('INFO', message, tag: tag);
  }

  static void warn(String message, {String? tag}) {
    _log('WARN', message, tag: tag);
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log('ERROR', message, tag: tag);
    if (error != null) {
      debugPrint('  ↳ $error');
    }
    if (stackTrace != null) {
      debugPrint('  ↳ $stackTrace');
    }
  }

  static void debug(String message, {String? tag}) {
    if (!_debugMode) return;
    _log('DEBUG', message, tag: tag);
  }

  static void _log(String level, String message, {String? tag}) {
    final now = DateTime.now();
    final ts =
        '${now.year}-${_p(now.month)}-${_p(now.day)} '
        '${_p(now.hour)}:${_p(now.minute)}:${_p(now.second)}';
    final tagStr = tag != null ? ' [$tag]' : '';
    final line = '[$level] $ts$tagStr - $message';
    debugPrint(line);
    DebugLogBuffer.add(line); // 同时写入可见调试面板
    if (kDebugMode) {
      developer.log(message, name: tag ?? 'wo-bot', level: level.hashCode);
    }
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
