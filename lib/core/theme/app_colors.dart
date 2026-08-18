import 'package:flutter/material.dart';

/// 调色板 — 匹配 Pixso 浅色主题设计
class AppColors {
  AppColors._();

  // 基础色 (Pixso 设计)
  static const Color background = Color(0xFFF9F9F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFE8E8E8);
  static const Color border = Color(0xFFEEEEEE);

  // 主色调 (保持蓝紫色系)
  static const Color primary = Color(0xFF6750A4);
  static const Color primaryLight = Color(0xFFD0BCFF);
  static const Color primaryContainer = Color(0xFFEADDFF);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // 语义色
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);

  // 文字色 (Pixso 设计)
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textHint = Color(0xFFC7C7CC);

  // 电池颜色
  static Color batteryColor(num level) {
    if (level <= 15) return error;
    if (level <= 30) return warning;
    return success;
  }

  // Wi-Fi 信号色
  static Color wifiSignalColor(int? signalDbm) {
    if (signalDbm == null) return textSecondary;
    if (signalDbm >= -50) return success;
    if (signalDbm >= -65) return const Color(0xFF34C759);
    if (signalDbm >= -75) return warning;
    return error;
  }
}
