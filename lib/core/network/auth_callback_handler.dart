import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'account_service.dart';
import 'share_link_service.dart';

/// 深链回调处理 — 监听 `wobot://` 协议：
/// - `wobot://auth/callback?code=&state=` — 授权登录回调
/// - `wobot://connect?robotIp=&robotPort=&shareCode=&robotId=` — 分享链接自动连接
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
    if (uri.scheme != 'wobot') return;

    // 1. 授权回调 wobot://auth/callback
    if (uri.host == 'auth') {
      if (uri.path != '/callback') return;
      final code = uri.queryParameters['code'];
      final state = uri.queryParameters['state'];
      if (code == null || state == null) {
        debugPrint('[AuthCallback] 缺少 code 或 state');
        return;
      }
      final ok = await AccountService.instance.handleCallback(code, state);
      debugPrint('[AuthCallback] 登录结果: $ok');
      AccountService.instance.notifyAuthChanged();
      return;
    }

    // 2. 分享链接 wobot://connect?robotIp=&robotPort=&shareCode=&robotId=
    if (uri.host == 'connect') {
      final ip = uri.queryParameters['robotIp'] ?? '';
      final port = int.tryParse(uri.queryParameters['robotPort'] ?? '') ?? 0;
      final code = uri.queryParameters['shareCode'] ?? '';
      final robotId = uri.queryParameters['robotId'];
      if (ip.isEmpty || port <= 0 || code.isEmpty) {
        debugPrint('[AuthCallback] 分享链接参数不完整: $uri');
        return;
      }
      ShareLinkService.instance.submit(
        ShareLinkData(
          robotIp: ip,
          robotPort: port,
          shareCode: code,
          robotId: robotId,
        ),
      );
    }
  }

  /// 释放监听
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
