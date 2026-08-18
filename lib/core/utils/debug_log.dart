import 'package:flutter/foundation.dart';

/// 平台无关的调试日志——同时输出到 debugPrint（logcat/终端）和 browser console。
void debugLog(String message) {
  debugPrint(message);
}
