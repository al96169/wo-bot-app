import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/utils/logger.dart';
import '../../../shared/models/robot_device.dart';

/// 设备列表状态管理 — 负责扫描发现的设备 (持久化由 DeviceStore 管理)
class DeviceListNotifier extends StateNotifier<AsyncValue<List<RobotDevice>>> {
  final ConnectionManager _connectionManager;

  DeviceListNotifier(this._connectionManager)
    : super(const AsyncValue.loading()) {
    startScan();
  }

  /// 开始扫描局域网设备
  Future<void> startScan() async {
    debugPrint('[DLP] startScan()');
    AppLogger.info('开始扫描局域网设备...');
    try {
      final devices = await _connectionManager.discoverDevices();
      debugPrint('[DLP] mDNS found ${devices.length} devices');
      AppLogger.info('扫描完成: ${devices.length} 个设备');
      state = AsyncValue.data(devices);
    } catch (e) {
      debugPrint('[DLP] scan error: $e');
      AppLogger.error('设备扫描失败', error: e);
      // 扫描失败不阻断，返回空列表
      state = const AsyncValue.data([]);
    }
  }
}

/// DeviceListNotifier 的 Riverpod Provider
final deviceListProvider =
    StateNotifierProvider<DeviceListNotifier, AsyncValue<List<RobotDevice>>>(
      (ref) => DeviceListNotifier(ref.read(connectionManagerProvider.notifier)),
    );
