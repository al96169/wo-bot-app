import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/robot_device.dart';

/// 设备存储 — 匹配 web-debug src/stores/devices.ts
class DeviceStore extends StateNotifier<DeviceStoreState> {
  DeviceStore() : super(const DeviceStoreState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('wobot_debug_devices');
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final devices = (json['devices'] as List? ?? [])
            .map((d) => _withCompatRobotId(RobotDevice.fromJson(d as Map<String, dynamic>)))
            .where((d) => d.ip.isNotEmpty && d.port > 0)
            .toList();
        // 按 robotId 去重（优先 robotId，兼容旧数据 id）
        final seen = <String>{};
        final deduped = <RobotDevice>[];
        for (final d in devices) {
          final key = d.robotId ?? d.id;
          if (!seen.contains(key)) {
            seen.add(key);
            deduped.add(d);
          }
        }
        RobotDevice? current;
        if (json['currentDevice'] != null) {
          try {
            current = _withCompatRobotId(
              RobotDevice.fromJson(
                json['currentDevice'] as Map<String, dynamic>,
              ),
            );
          } catch (_) {}
        }
        state = DeviceStoreState(devices: deduped, currentDevice: current);
        debugPrint('[DeviceStore] 加载 ${deduped.length} 个设备');
      } catch (e) {
        debugPrint('[DeviceStore] 加载失败: $e');
      }
    }
  }

  /// 兼容旧数据：robotId 为空时从 id（PTR 实例名）提取。
  /// 实例名形如 robot-xxx._wobot._tcp.local.，首个 label 即 robotId。
  static RobotDevice _withCompatRobotId(RobotDevice d) {
    if (d.robotId != null && d.robotId!.isNotEmpty) return d;
    final id = d.id;
    if (id.contains('._wobot._tcp.local.')) {
      return d.copyWith(robotId: id.split('.').first);
    }
    return d;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'devices': state.devices.map((d) => d.toJson()).toList(),
      'currentDevice': state.currentDevice?.toJson(),
    };
    await prefs.setString('wobot_debug_devices', jsonEncode(json));
  }

  /// 添加设备
  Future<void> addDevice(RobotDevice device) async {
    final devices = [...state.devices];
    // 去重: 按 ip:port
    final key = '${device.ip}:${device.port}';
    devices.removeWhere((d) => '${d.ip}:${d.port}' == key);
    devices.insert(0, device);
    state = state.copyWith(devices: devices);
    await _save();
    debugPrint(
      '[DeviceStore] 添加设备: ${device.name} @ ${device.ip}:${device.port}',
    );
  }

  /// 移除设备
  Future<void> removeDevice(String id) async {
    final devices = state.devices.where((d) => d.id != id).toList();
    RobotDevice? current = state.currentDevice;
    if (current?.id == id) {
      current = devices.isNotEmpty ? devices.first : null;
    }
    state = state.copyWith(devices: devices, currentDevice: current);
    await _save();
  }

  /// 选择当前设备
  Future<void> selectDevice(String id) async {
    final device = state.devices.where((d) => d.id == id).firstOrNull;
    if (device != null) {
      state = state.copyWith(currentDevice: device);
      await _save();
    }
  }

  /// 设置当前设备 (连接成功后更新)
  Future<void> setCurrentDevice(RobotDevice device) async {
    // 优先按 robotId 匹配，其次按 id，再按 ip:port（对齐 web-debug setCurrentDevice）
    final existing = state.devices
        .where(
          (d) =>
              (device.robotId != null && d.robotId == device.robotId) ||
              d.id == device.id ||
              (d.ip == device.ip && d.port == device.port),
        )
        .firstOrNull;

    if (existing != null) {
      // 更新属性，保留 ip:port；补全 robotId（云端和本地设备 id 可能不同但 robotId 相同）
      final updated = existing.copyWith(
        name: device.name.isNotEmpty ? device.name : existing.name,
        capabilities: device.capabilities.isNotEmpty
            ? device.capabilities
            : existing.capabilities,
        robotId: device.robotId ?? existing.robotId,
        localAvailable: device.localAvailable || existing.localAvailable,
      );
      final devices = state.devices
          .map((d) => d.id == updated.id ? updated : d)
          .toList();
      state = state.copyWith(devices: devices, currentDevice: updated);
    } else {
      await addDevice(device);
      state = state.copyWith(currentDevice: device);
    }
    await _save();
  }

  /// 更新设备 robotId (连接成功后由后端返回)
  Future<void> updateDeviceRobotId(String robotId) async {
    if (state.currentDevice == null) return;
    final updated = state.currentDevice!.copyWith(
      id: robotId,
      robotId: robotId,
    );
    final devices = state.devices
        .map((d) => d.id == state.currentDevice!.id ? updated : d)
        .toList();
    state = state.copyWith(devices: devices, currentDevice: updated);
    await _save();
  }

  /// 设置设备在线状态
  void setDeviceOnline(String id, bool online) {
    // 只更新 currentDevice 的在线标记
    if (state.currentDevice?.id == id) {
      // RobotDevice 没有 online 字段，用 lastSeen 表示
    }
  }

  /// 添加发现的设备 (不保存，只是临时显示)
  void addDiscoveredDevices(List<RobotDevice> discovered) {
    final existing = {...state.devices.map((d) => '${d.ip}:${d.port}')};
    final newDevices = discovered
        .where((d) => !existing.contains('${d.ip}:${d.port}'))
        .toList();
    state = state.copyWith(discovered: newDevices);
  }

  /// 从发现列表导入到设备列表
  Future<void> importDiscovered(RobotDevice device) async {
    await addDevice(device);
    final discovered = state.discovered
        .where((d) => '${d.ip}:${d.port}' != '${device.ip}:${device.port}')
        .toList();
    state = state.copyWith(discovered: discovered);
  }

  /// 清空云端设备
  void clearCloudDevices() {
    state = state.copyWith(cloudDevices: []);
  }

  /// 设置云端设备
  void setCloudDevices(List<CloudDevice> devices) {
    state = state.copyWith(cloudDevices: devices);
  }

  /// 云端设备过滤：排除已出现在本地已保存设备或发现列表中的 robotId
  /// （对齐 web-debug cloudDevicesFiltered：按 robotId 匹配）
  List<CloudDevice> get cloudDevicesFiltered {
    // 本地设备的 robotId 集合（优先 robotId，其次 id，兼容旧数据）
    final localRobotIds = state.devices
        .map((d) => d.robotId ?? d.id)
        .where((s) => s.isNotEmpty)
        .toSet();
    final discoveredRobotIds = state.discovered
        .map((d) => d.robotId ?? d.id)
        .where((s) => s.isNotEmpty)
        .toSet();
    return state.cloudDevices
        .where(
          (c) =>
              !localRobotIds.contains(c.robotId) &&
              !discoveredRobotIds.contains(c.robotId),
        )
        .toList();
  }

  /// 云端设备中是否存在指定 robotId（是否已绑定到当前用户）
  bool isCloudBound(String robotId) =>
      state.cloudDevices.any((c) => c.robotId == robotId);

  /// 查找指定 robotId 对应的云端设备
  CloudDevice? findCloudDevice(String robotId) {
    for (final c in state.cloudDevices) {
      if (c.robotId == robotId) return c;
    }
    return null;
  }

  /// 合并设备列表：本地已保存设备 + 云端绑定设备，按 robotId/id 去重
  /// - 同一设备同时存在本地+云端时只显示一次，保留有 ip:port 的本地记录
  /// - 纯云端设备（本地未保存）转换为 RobotDevice 形态（ip/port 为空，
  ///   bound=true，localAvailable=云端在线），由 UI 区分本地/云端连接
  /// （对齐 web-debug mergedDevices：本地 key 用 robotId || id）
  List<RobotDevice> get mergedDevices {
    final localKeys = state.devices
        .map((d) => d.robotId ?? d.id)
        .where((s) => s.isNotEmpty)
        .toSet();
    final merged = <RobotDevice>[...state.devices];
    for (final c in cloudDevicesFiltered) {
      if (localKeys.contains(c.robotId)) continue;
      merged.add(
        RobotDevice(
          id: c.robotId,
          name: (c.robotName?.isNotEmpty ?? false) ? c.robotName! : c.robotId,
          ip: '',
          port: 0,
          serviceName: '',
          bound: true,
          localAvailable: c.status == 'online',
          robotId: c.robotId,
        ),
      );
    }
    return merged;
  }
}

/// 云端设备 — 匹配 web-debug CloudDevice
class CloudDevice {
  final String robotId;
  final String? robotName;
  final String clientId;
  final String status;
  final String? lastSeenAt;
  final String boundAt;

  const CloudDevice({
    required this.robotId,
    this.robotName,
    required this.clientId,
    this.status = 'offline',
    this.lastSeenAt,
    required this.boundAt,
  });

  factory CloudDevice.fromJson(Map<String, dynamic> json) => CloudDevice(
    robotId: json['robotId'] as String? ?? '',
    robotName: json['robotName'] as String?,
    clientId: json['clientId'] as String? ?? '',
    status: json['status'] as String? ?? 'offline',
    lastSeenAt: json['lastSeenAt'] as String?,
    boundAt: json['boundAt'] as String? ?? '',
  );
}

/// 设备存储状态
class DeviceStoreState {
  final List<RobotDevice> devices;
  final RobotDevice? currentDevice;
  final List<RobotDevice> discovered;
  final List<CloudDevice> cloudDevices;

  const DeviceStoreState({
    this.devices = const [],
    this.currentDevice,
    this.discovered = const [],
    this.cloudDevices = const [],
  });

  DeviceStoreState copyWith({
    List<RobotDevice>? devices,
    RobotDevice? currentDevice,
    List<RobotDevice>? discovered,
    List<CloudDevice>? cloudDevices,
  }) {
    return DeviceStoreState(
      devices: devices ?? this.devices,
      currentDevice: currentDevice ?? this.currentDevice,
      discovered: discovered ?? this.discovered,
      cloudDevices: cloudDevices ?? this.cloudDevices,
    );
  }
}

final deviceStoreProvider =
    StateNotifierProvider<DeviceStore, DeviceStoreState>(
      (ref) => DeviceStore(),
    );
