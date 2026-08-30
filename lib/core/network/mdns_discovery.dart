import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import '../utils/logger.dart';
import '../../shared/models/robot_device.dart';

/// mDNS 局域网设备发现（自实现，对齐 web-debug 经验）
///
/// 背景：multicast_dns 包在 Android 上 PTR 查询正常但 SRV/TXT 具体查询收不到响应
/// （web-debug 也遇过：mDNS 的 A 记录解析不可靠）。
/// 方案（web-debug 同款）：只发 PTR 服务发现查询，**用响应包的源 IP 作为设备地址**
/// ——源 IP 总是 mDNS 广播者的真实地址，最可靠；端口用约定 8765。
class MdnsDiscovery {
  RawDatagramSocket? _socket;
  bool _scanning = false;

  /// Android 组播锁通道：网卡默认过滤组播包，需 MulticastLock 才能收到 mDNS 响应
  static const _multicastChannel = MethodChannel('wobot/multicast');

  static final InternetAddress _mDnsGroup = InternetAddress('224.0.0.251');

  Future<void> _acquireMulticastLock() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _multicastChannel.invokeMethod('acquire');
      } catch (e) {
        AppLogger.warn('MulticastLock 获取失败: $e');
      }
    }
  }

  Future<void> _releaseMulticastLock() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _multicastChannel.invokeMethod('release');
      } catch (_) {}
    }
  }

  /// 扫描局域网中的 wo-bot 设备（PTR 查询 + 响应源 IP）
  Future<List<RobotDevice>> discover({int timeout = 5}) async {
    if (_scanning) return const []; // 串行化，避免并发 bind 冲突
    _scanning = true;
    try {
      return await _doDiscover(timeout: timeout);
    } finally {
      _scanning = false;
    }
  }

  Future<List<RobotDevice>> _doDiscover({required int timeout}) async {
    await _acquireMulticastLock();
    final devices = <RobotDevice>{};
    try {
      if (_socket == null) {
        // 绑定 5353（mDNS 标准端口）：组播响应发到 5353，必须监听该端口才能收到
        // ttl: 255 必须设置——Dart 默认 ttl=0，发送组播包会直接报错
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          5353,
          ttl: 255,
        );
        // 加入组播组：必须遍历所有 IPv4 接口（手机同时连 WiFi+移动数据时，
        // 默认接口可能不是 WiFi，导致收不到 WiFi 组播响应）
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLinkLocal: true,
        );
        for (final iface in interfaces) {
          try {
            _socket!.joinMulticast(_mDnsGroup, iface);
            AppLogger.info('加入组播: ${iface.name} ${iface.addresses.first.address}');
          } catch (e) {
            AppLogger.warn('接口 ${iface.name} 加入组播失败: $e');
          }
        }
      }

      AppLogger.info('开始 mDNS 扫描: ${AppConstants.mdnsServiceType}.local');
      final query = _buildPtrQuery('${AppConstants.mdnsServiceType}.local');
      _socket!.send(query, _mDnsGroup, 5353);

      final deadline = DateTime.now().add(Duration(seconds: timeout));
      final sub = _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = _socket!.receive();
        if (dg == null) return;
        final parsed = _parsePtrResponse(dg.data);
        if (parsed == null) return;
        final (instance, displayName) = parsed;
        // 实例名形如 robot-xxx._wobot._tcp.local.，首个 label 即 robotId
        // （对齐 web-debug mdnsDiscovery：robotId = d.id）
        final robotId = instance.split('.').first;
        final device = RobotDevice(
          id: instance,
          name: displayName ?? robotId,
          ip: dg.address.address, // 响应包源 IP = 设备真实地址（web-debug referer 同款）
          port: AppConstants.defaultWebSocketPort,
          serviceName: instance,
          robotId: robotId,
        );
        devices.add(device);
        AppLogger.info('发现设备: ${device.name} @ ${device.ip}:${device.port}');
      });

      // 等待收集响应
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      await sub.cancel();
    } catch (e) {
      AppLogger.error('mDNS 扫描失败', error: e);
      _closeSocket();
    } finally {
      _releaseMulticastLock();
    }
    AppLogger.info('扫描完成: ${devices.length} 个设备');
    return devices.toList();
  }

  /// 构造 DNS PTR 查询包
  static Uint8List _buildPtrQuery(String service) {
    final b = BytesBuilder();
    // Header: id, flags, qdcount=1
    b.add([0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    // QNAME
    for (final label in service.split('.')) {
      b.add([label.length]);
      b.add(label.codeUnits);
    }
    b.add([0x00]);
    // QTYPE=PTR(12), QCLASS=IN(1)
    b.add([0x00, 0x0c, 0x00, 0x01]);
    return b.toBytes();
  }

  /// 解析 DNS 响应包：返回 (PTR 实例名, TXT 显示名)
  static (String, String?)? _parsePtrResponse(Uint8List data) {
    if (data.length < 12) return null;
    final bd = ByteData.sublistView(data);
    final qdCount = bd.getUint16(4);
    final anCount = bd.getUint16(6);
    final arCount = bd.getUint16(10);

    var offset = 12;
    // Skip questions
    for (var i = 0; i < qdCount; i++) {
      offset = _skipName(data, offset);
      if (offset < 0 || offset + 4 > data.length) return null;
      offset += 4; // QTYPE + QCLASS
    }

    String? instance;
    String? displayName;

    // Parse answers (找 PTR)
    for (var i = 0; i < anCount; i++) {
      final nameEnd = _skipName(data, offset);
      if (nameEnd < 0 || nameEnd + 10 > data.length) return null;
      final bd2 = ByteData.sublistView(data);
      final type = bd2.getUint16(nameEnd);
      final rdLength = bd2.getUint16(nameEnd + 8);
      final rdataStart = nameEnd + 10;
      if (rdataStart + rdLength > data.length) return null;
      if (type == 12 && instance == null) {
        final ins = _readName(data, rdataStart);
        if (ins != null && ins.endsWith('._wobot._tcp.local.')) {
          instance = ins;
        }
      }
      offset = rdataStart + rdLength;
    }
    if (instance == null) return null;

    // Parse additional (找 TXT 的 name 属性)
    for (var i = 0; i < arCount; i++) {
      final nameEnd = _skipName(data, offset);
      if (nameEnd < 0 || nameEnd + 10 > data.length) break;
      final bd2 = ByteData.sublistView(data);
      final type = bd2.getUint16(nameEnd);
      final rdLength = bd2.getUint16(nameEnd + 8);
      final rdataStart = nameEnd + 10;
      if (rdataStart + rdLength > data.length) break;
      if (type == 16) {
        final txt = _parseTxt(data, rdataStart, rdLength);
        if (txt.containsKey('name')) displayName = txt['name'];
      }
      offset = rdataStart + rdLength;
    }
    return (instance, displayName);
  }

  /// 解析 TXT rdata（长度前缀的 key=value 序列）
  static Map<String, String> _parseTxt(Uint8List data, int start, int length) {
    final map = <String, String>{};
    var p = start;
    final end = start + length;
    while (p < end && p < data.length) {
      final len = data[p];
      p++;
      if (len == 0 || p + len > end || p + len > data.length) break;
      final seg = String.fromCharCodes(data.sublist(p, p + len));
      final kv = seg.split('=');
      if (kv.length == 2) map[kv[0]] = kv[1];
      p += len;
    }
    return map;
  }

  /// 跳过 DNS 名称（返回下一个字段偏移）
  static int _skipName(Uint8List data, int offset) {
    var p = offset;
    var jumps = 0;
    while (p < data.length) {
      final len = data[p];
      if (len == 0) return p + 1;
      if ((len & 0xC0) == 0xC0) {
        // 压缩指针（最多跳 2 次）
        if (++jumps > 2) return -1;
        p += 2;
        return p;
      }
      p += 1 + len;
    }
    return -1;
  }

  /// 读取 DNS 名称（解压指针），返回完整字符串
  static String? _readName(Uint8List data, int offset) {
    final labels = <String>[];
    var p = offset;
    var jumps = 0;
    final visited = <int>{};
    while (p < data.length) {
      if (visited.contains(p)) return null; // 防循环
      visited.add(p);
      final len = data[p];
      if (len == 0) break;
      if ((len & 0xC0) == 0xC0) {
        if (p + 1 >= data.length) return null;
        if (++jumps > 8) return null;
        p = ((len & 0x3F) << 8) | data[p + 1];
        continue;
      }
      if (p + 1 + len > data.length) return null;
      labels.add(String.fromCharCodes(data.sublist(p + 1, p + 1 + len)));
      p += 1 + len;
    }
    if (labels.isEmpty) return null;
    return '${labels.join('.')}.';
  }

  /// 停止 mDNS 客户端
  void stop() {
    _closeSocket();
    _releaseMulticastLock();
  }

  void _closeSocket() {
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
