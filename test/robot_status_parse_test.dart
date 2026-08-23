// 系统状态解析测试 — 真机嵌套格式 + mock 扁平格式
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/shared/models/robot_data.dart';
import 'package:wo_bot/shared/models/robot_status.dart';

void main() {
  test('解析真机嵌套 status 格式（battery/system/network）', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': {
        'level': 95,
        'status': 'discharging',
        'temperature': 35,
        'estimated_minutes': 120,
      },
      'system': {
        'cpu_percent': 42.5,
        'temperature': 60.1,
        'memory_percent': 51.3,
        'disk_percent': 80.2,
        'uptime': 86400,
        'hostname': 'jetson',
      },
      'network': {
        'ssid': 'HomeWiFi',
        'signal_strength': -55,
        'ip': '192.168.1.47',
      },
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
    s.updateFromJson({
      'battery': {'level': null},
      'system': {},
    });
    expect(s.batteryLevel, 0);
    expect(s.cpuUsage, 0);
  });

  test('真机 uptime 为 double 时不抛异常（回归：曾致 status 解析中断）', () {
    final s = SystemStatusData();
    // 真机实测：json['uptime'] 为 double（如 59662.86），且 system 内无 uptime
    s.updateFromJson({
      'battery': {'level': 95, 'status': 'discharging'},
      'system': {'cpu_percent': 12.3},
      'uptime': 59662.86214160919,
    });
    expect(s.uptime, 59662);
  });

  test('services 列表解析（含 double uptime，对齐真机格式）', () {
    final store = RobotDataStore();
    store.setServices([
      {
        'service_id': 'main',
        'name': 'wo-bot-control',
        'status': 'running',
        'pid': 1234,
        'uptime': 59662.86,
      },
      {'service_id': 'camera', 'name': 'camera_service', 'status': 'stopped'},
    ]);
    expect(store.services.length, 2);
    expect(store.services.first.serviceId, 'main');
    expect(store.services.first.name, 'wo-bot-control');
    expect(store.services.first.status, 'running');
    expect(store.services.first.uptime, 59662);
  });

  test('RobotStatus 按真机线格式解析（battery.status/system.*/network.*）', () {
    final rs = RobotStatus.fromJson({
      'battery': {'level': 95, 'status': 'charging', 'temperature': 35},
      'system': {
        'cpu_percent': 42.5,
        'memory_percent': 51.3,
        'disk_percent': 80.2,
        'uptime': 59662.86,
        'temperature': 60.1,
        'hostname': 'jetson',
      },
      'network': {
        'ssid': 'HomeWiFi',
        'signal_strength': -55,
        'ip': '192.168.1.47',
      },
    });
    expect(rs.batteryLevel, 95);
    expect(rs.batteryCharging, isTrue);
    expect(rs.cpuUsage, 42.5);
    expect(rs.memoryUsage, 51.3);
    expect(rs.diskUsage, 80.2);
    expect(rs.wifiSSID, 'HomeWiFi');
    expect(rs.wifiSignal, -55);
    expect(rs.ip, '192.168.1.47');
    expect(rs.uptime, 59662);
    expect(rs.temperature, 60.1);
  });

  test('解析真机 device_info（OS/内核/CPU/MAC/累计运行）', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': {'level': 95, 'status': 'discharging'},
      'system': {
        'cpu_percent': 10.0,
        'memory_percent': 63.0,
        'disk_percent': 90.7,
        'uptime': 74,
        'total_runtime': 36000,
        'temperature': 43.0,
        'hostname': 'yahboom',
      },
      'network': {
        'ip': '192.168.1.47',
        'ssid': 'MyHome',
        'signal_strength': -22,
        'mac': '48:8f:4c:d4:cd:42',
        'bluetooth_mac': '48:8F:4C:D4:CD:43',
      },
      'device_info': {
        'hostname': 'yahboom',
        'os': 'Ubuntu 18.04.6 LTS',
        'kernel': '4.9.337-tegra',
        'cpu_model': 'ARMv8 Processor rev 1 (v8l)',
        'cpu_count': 4,
        'ip': '192.168.1.47',
        'mac': '48:8f:4c:d4:cd:42',
        'bluetooth_mac': '48:8F:4C:D4:CD:43',
        'uptime': 74,
        'total_runtime': 36000,
      },
    });

    expect(s.os, 'Ubuntu 18.04.6 LTS');
    expect(s.kernel, '4.9.337-tegra');
    expect(s.cpuModel, 'ARMv8 Processor rev 1 (v8l)');
    expect(s.cpuCount, 4);
    expect(s.mac, '48:8f:4c:d4:cd:42');
    expect(s.bluetoothMac, '48:8F:4C:D4:CD:43');
    expect(s.totalRuntime, 36000);
    expect(s.hostname, 'yahboom');
    expect(s.ip, '192.168.1.47');
  });

  test('无电池数据（status=unknown）时 batteryStatus 正确保留', () {
    final s = SystemStatusData();
    s.updateFromJson({
      'battery': {'level': 100, 'status': 'unknown'},
      'system': {'cpu_percent': 15.0},
    });
    expect(s.batteryLevel, 100);
    expect(s.batteryStatus, 'unknown');
    expect(s.batteryCharging, false);
  });

  test('JSON decode 的 features(List<dynamic>) 用 .cast<String>() 赋给 List<String> 字段', () {
    // 模拟 jsonDecode 产物：List<dynamic>（无显式泛型）
    final raw = <dynamic>['websocket', 'exec', 'system', 'motion', 'camera'];
    // 与 ConnectionManager._handleMessage 相同的写法（真机 AOT 下旧写法会抛类型错误）
    final List<String> features = raw.cast<String>();
    expect(features, contains('motion'));
    expect(features, isA<List<String>>());
  });

  test('软件项 status:"installed" 判定为已安装并解析版本号', () {
    final sw = Software.fromJson({
      'name': 'wobot-control',
      'display_name': 'wo-bot 主控',
      'status': 'installed',
      'version': '2.1.0',
      'description': '主控服务',
      'category': 'core',
    });
    expect(sw.installed, isTrue);
    expect(sw.version, '2.1.0');
    expect(sw.displayName, 'wo-bot 主控');

    // 未安装（status 缺失或非 installed）
    final sw2 = Software.fromJson({'name': 'dance', 'display_name': '舞蹈'});
    expect(sw2.installed, isFalse);

    // 兼容 installed: true 布尔形式
    final sw3 = Software.fromJson({
      'name': 'x',
      'display_name': 'X',
      'installed': true,
    });
    expect(sw3.installed, isTrue);
  });
}
