import 'dart:async';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';
import '../../shared/models/robot_device.dart';

/// mDNS 局域网设备发现
class MdnsDiscovery {
  final MDnsClient _client = MDnsClient();
  bool _started = false;
  Future<void>? _pendingStart;
  Future<List<RobotDevice>>? _runningScan;

  /// 扫描局域网中的 wo-bot 设备
  ///
  /// 流程：PTR 查询 → SRV 查询(host+port) → TXT 查询(capabilities) → DNS 解析 IP
  Future<List<RobotDevice>> discover({int timeout = 5}) {
    // 并发调用时串行化，避免同一 MDnsClient 上重复 start/lookup 报错
    final previous = _runningScan ?? Future.value(const <RobotDevice>[]);
    final current = previous.then((_) => _doDiscover(timeout: timeout));
    _runningScan = current;
    return current.whenComplete(() {
      if (identical(_runningScan, current)) _runningScan = null;
    });
  }

  Future<List<RobotDevice>> _doDiscover({required int timeout}) async {
    try {
      if (!_started) {
        // 并发扫描时复用同一个 start Future，避免重复 start() 报错
        _pendingStart ??= _client.start().then((_) {
          _started = true;
          _pendingStart = null;
        });
        await _pendingStart;
      }

      final devices = <RobotDevice>[];

      // 1. PTR 查询 _wobot._tcp.local
      AppLogger.info('开始 mDNS 扫描: ${AppConstants.mdnsServiceType}.local');
      final ptrResults = await _client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(
              '${AppConstants.mdnsServiceType}.local',
            ),
          )
          .timeout(Duration(seconds: timeout))
          .toList();

      AppLogger.info('发现 ${ptrResults.length} 个 PTR 记录');

      for (final ptr in ptrResults) {
        try {
          // 2. SRV 查询获取 host + port
          final srvResults = await _client
              .lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(ptr.domainName),
              )
              .timeout(const Duration(seconds: 3))
              .toList();

          if (srvResults.isEmpty) continue;

          // 3. TXT 查询获取 capabilities
          List<String> caps = [];
          try {
            final txtResults = await _client
                .lookup<TxtResourceRecord>(
                  ResourceRecordQuery.text(ptr.domainName),
                )
                .timeout(const Duration(seconds: 2))
                .toList();

            if (txtResults.isNotEmpty) {
              caps = txtResults.first.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          } catch (_) {
            // TXT 查询非必需
          }

          // 4. 解析 IP 地址
          final target = srvResults.first.target;
          final addresses = await InternetAddress.lookup(target)
              .timeout(const Duration(seconds: 3));

          if (addresses.isEmpty) continue;

          final ip = addresses.first.address;
          final port = srvResults.first.port;
          final deviceName = ptr.domainName.split('.').first;

          final device = RobotDevice(
            id: ptr.domainName,
            name: deviceName,
            ip: ip,
            port: port,
            serviceName: ptr.domainName,
            capabilities: caps,
          );

          devices.add(device);
          AppLogger.info('发现设备: $deviceName @ $ip:$port, 能力: $caps');
        } catch (e) {
          AppLogger.warn('解析设备失败: ${ptr.domainName} — $e');
        }
      }

      return devices;
    } catch (e) {
      AppLogger.error('mDNS 扫描失败', error: e);
      _client.stop();
      _started = false;
      return [];
    }
  }

  /// 停止 mDNS 客户端
  void stop() {
    if (_started) {
      _client.stop();
      _started = false;
      AppLogger.info('mDNS 客户端已停止');
    }
  }
}
