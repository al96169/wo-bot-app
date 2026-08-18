// 系统状态解析测试 — 真机嵌套格式 + mock 扁平格式
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_bot/shared/models/robot_data.dart';

void main() {
  test('解析真机嵌套 status 格式（battery/system/network）', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': {'level': 95, 'status': 'discharging', 'temperature': 35, 'estimated_minutes': 120},
      'system': {'cpu_percent': 42.5, 'temperature': 60.1, 'memory_percent': 51.3, 'disk_percent': 80.2, 'uptime': 86400, 'hostname': 'jetson'},
      'network': {'ssid': 'HomeWiFi', 'signal_strength': -55, 'ip': '192.168.1.47'},
    });

    expect(s.batteryLevel, 95);
    expect(s.batteryCharging, false);
    expect(s.cpuUsage, 42.5);
    expect(s.memoryUsage, 51.3);
    expect(s.diskUsage, 80.2);
    expect(s.wifiSSID, 'HomeWiFi');
    expect(s.wifiSignal, -55);
    expect(s.ip, '192.168.1.47');
    expect(s.hostname, 'jetson');
    expect(s.uptime, 86400);
    expect(s.cpuTemp, 60.1);
  });

  test('解析充电中状态', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': {'level': 100, 'status': 'charging'},
    });
    expect(s.batteryLevel, 100);
    expect(s.batteryCharging, true);
  });

  test('兼容 mock 扁平格式', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': 50,
      'cpu': 30.5,
      'memory': 40,
      'disk': 70,
      'wifi_ssid': 'MockWiFi',
      'wifi_signal': -60,
      'ip': '127.0.0.1',
      'uptime': 3600,
    });
    expect(s.batteryLevel, 50);
    expect(s.cpuUsage, 30.5);
    expect(s.memoryUsage, 40);
    expect(s.diskUsage, 70);
    expect(s.wifiSSID, 'MockWiFi');
    expect(s.wifiSignal, -60);
  });

  test('字段缺失时保留默认值不抛异常', () {
    final s = SystemStatusData();
    s.updateFromJson({'battery': {'level': null}, 'system': {}});
    expect(s.batteryLevel, 0);
    expect(s.cpuUsage, 0);
  });
}
