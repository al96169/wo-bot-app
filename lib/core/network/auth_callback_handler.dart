import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'account_service.dart';

/// 授权回调处理 — 监听 `wobot://auth/callback?code=...&state=...` 深链
///
/// 用户在用户中心授权确认后，浏览器重定向到 wobot:// 回调，
/// 由系统拉起 App，此处捕获 code + state 并换取 token。
class AuthCallbackHandler {
  AuthCallbackHandler._();

  static final AuthCallbackHandler instance = AuthCallbackHandler._();

  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  /// 启动监听（App 启动时调用一次）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final appLinks = AppLinks();
    // 监听深链流
    _sub = appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object e) => debugPrint('[AuthCallback] 监听错误: $e'),
    );

    // App 被冷启动拉起时，读取初始 URI
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) _handleUri(initial);
    } catch (e) {
      debugPrint('[AuthCallback] 读取初始链接失败: $e');
    }
  }

  /// 处理回调 URI
  Future<void> _handleUri(Uri uri) async {
    debugPrint('[AuthCallback] 收到回调: $uri');
    // 仅处理 wobot://auth/callback
    if (uri.scheme != 'wobot' || uri.host != 'auth') return;
    if (uri.path != '/callback') return;

    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      debugPrint('[AuthCallback] 缺少 code 或 state');
      return;
    }

    final ok = await AccountService.instance.handleCallback(code, state);
    debugPrint('[AuthCallback] 登录结果: $ok');
    // 通知界面刷新登录状态
    AccountService.instance.notifyAuthChanged();
  }

  /// 释放监听
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
