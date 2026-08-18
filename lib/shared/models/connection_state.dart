import 'robot_status.dart';

/// 连接状态枚举
enum AppConnectionState {
  disconnected,
  connecting,
  connected,
  error;

  /// 中文描述
  String get displayName {
    switch (this) {
      case AppConnectionState.disconnected:
        return '未连接';
      case AppConnectionState.connecting:
        return '连接中';
      case AppConnectionState.connected:
        return '已连接';
      case AppConnectionState.error:
        return '连接失败';
    }
  }

  /// 是否已连接
  bool get isConnected => this == AppConnectionState.connected;
}

/// 连接管理器完整状态（包含连接状态 + 机器人数据）
class ConnectionStateData {
  final AppConnectionState connectionState;
  final RobotStatus? robotStatus;
  final Map<String, dynamic>? robotInfo;

  const ConnectionStateData({
    this.connectionState = AppConnectionState.disconnected,
    this.robotStatus,
    this.robotInfo,
  });

  bool get isConnected => connectionState == AppConnectionState.connected;

  ConnectionStateData copyWith({
    AppConnectionState? connectionState,
    RobotStatus? robotStatus,
    Map<String, dynamic>? robotInfo,
    bool clearStatus = false,
    bool clearInfo = false,
  }) {
    return ConnectionStateData(
      connectionState: connectionState ?? this.connectionState,
      robotStatus: clearStatus ? null : (robotStatus ?? this.robotStatus),
      robotInfo: clearInfo ? null : (robotInfo ?? this.robotInfo),
    );
  }
}
