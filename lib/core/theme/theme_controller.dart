import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// 主题模式 — 对齐 web-debug appStore.theme（auto/dark/light）
enum AppThemeMode { auto, light, dark }

extension AppThemeModeExt on AppThemeMode {
  String get storageValue => name;

  static AppThemeMode fromStorage(String? v) {
    return AppThemeMode.values.firstWhere(
      (m) => m.name == v,
      orElse: () => AppThemeMode.auto,
    );
  }

  String get label {
    switch (this) {
      case AppThemeMode.auto:
        return '跟随系统';
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
    }
  }
}

/// 主题控制器 — 三态主题（跟随系统/浅色/深色）+ SharedPreferences 持久化
/// 对齐 web-debug SettingsView 主题切换 + AppHeader 循环按钮
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.light) {
    _load();
  }

  AppThemeMode _mode = AppThemeMode.auto;

  /// 当前主题模式（auto/light/dark）
  AppThemeMode get mode => _mode;

  /// 加载持久化的主题模式
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.keyThemeMode);
      _mode = AppThemeModeExt.fromStorage(raw);
      state = _resolve(_mode);
    } catch (_) {
      state = ThemeMode.light;
    }
  }

  /// 设置主题模式并持久化
  Future<void> setMode(AppThemeMode mode) async {
    _mode = mode;
    state = _resolve(mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyThemeMode, mode.storageValue);
    } catch (_) {}
  }

  /// 循环切换：auto → light → dark → auto（对齐 web-debug AppHeader toggleTheme）
  Future<void> cycle() async {
    final next =
        AppThemeMode.values[(_mode.index + 1) % AppThemeMode.values.length];
    await setMode(next);
  }

  ThemeMode _resolve(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.auto:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>(
      (ref) => ThemeController(),
    );
