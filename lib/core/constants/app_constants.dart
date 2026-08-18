/// 应用全局常量
class AppConstants {
  AppConstants._();

  // ---- mDNS ----
  static const String mdnsServiceType = '_wobot._tcp';
  static const int mdnsDiscoveryTimeout = 5;

  // ---- 端口 ----
  static const int defaultWebSocketPort = 8765;
  static const int defaultWebRtcPort = 8554;
  static const int defaultSshPort = 22;

  // ---- 连接 ----
  static const int maxReconnectAttempts = 5;
  static const int reconnectBaseDelayMs = 1000;
  static const int reconnectMaxDelayMs = 30000;
  static const int heartbeatIntervalSec = 30;
  static const int connectionTimeoutSec = 10;

  // ---- 状态更新间隔 ----
  static const int statusUpdateIntervalSec = 2;

  // ---- 摇杆 ----
  static const double joystickDeadZone = 0.1;
  static const double joystickMaxSpeed = 1.0;
  static const int directionButtonRepeatMs = 100;

  // ---- 存储键名 ----
  static const String keyLastConnectedDevice = 'last_connected_device';
  static const String keySavedDevices = 'saved_devices';
  static const String keyThemeMode = 'theme_mode';
}
