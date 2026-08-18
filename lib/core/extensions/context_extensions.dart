import 'package:flutter/material.dart';

/// BuildContext 便捷扩展
extension ContextExtensions on BuildContext {
  /// 屏幕宽度
  double get screenWidth => MediaQuery.of(this).size.width;

  /// 屏幕高度
  double get screenHeight => MediaQuery.of(this).size.height;

  /// 是否横屏
  bool get isLandscape =>
      MediaQuery.of(this).orientation == Orientation.landscape;

  /// 是否竖屏
  bool get isPortrait =>
      MediaQuery.of(this).orientation == Orientation.portrait;

  /// 显示 SnackBar
  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade800 : null,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// 主题色
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// 文字主题
  TextTheme get textTheme => Theme.of(this).textTheme;
}
