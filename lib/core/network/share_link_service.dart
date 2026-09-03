import 'package:flutter/foundation.dart';

/// 分享链接数据（从深链 wobot://connect 解析）
class ShareLinkData {
  final String robotIp;
  final int robotPort;
  final String shareCode;
  final String? robotId;
  const ShareLinkData({
    required this.robotIp,
    required this.robotPort,
    required this.shareCode,
    this.robotId,
  });
}

/// 分享链接服务 — 接收深链分享数据，由设备列表页消费自动连接绑定。
///
/// 对齐 web-debug App.vue 分享链接逻辑（robotIp+robotPort+shareCode → 自动连接）。
class ShareLinkService {
  ShareLinkService._();
  static final ShareLinkService instance = ShareLinkService._();

  /// 待处理的分享链接（深链到达时暂存，消费后清空）
  ShareLinkData? pending;

  /// 有新分享链接时的通知（UI 层注册消费）
  void Function(ShareLinkData data)? onShareLink;

  /// 提交分享链接（AuthCallbackHandler 解析深链后调用）
  void submit(ShareLinkData data) {
    debugPrint(
      '[ShareLink] 收到分享链接: ${data.robotIp}:${data.robotPort} code=${data.shareCode}',
    );
    pending = data;
    onShareLink?.call(data);
  }

  /// 消费分享链接（设备列表页处理后清空）
  ShareLinkData? take() {
    final d = pending;
    pending = null;
    return d;
  }
}
