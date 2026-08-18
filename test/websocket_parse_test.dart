// WebSocket 消息解析测试 — NaN/Infinity 非标准 JSON 容错
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// 复制 WsClient._onData 的容错逻辑用于测试（无法直接注入私有方法）
String _sanitize(String text) {
  if (text.contains('NaN') || text.contains('Infinity')) {
    return text.replaceAllMapped(
      RegExp(r'(?<=[:,\[\{])\s*(NaN|-?Infinity)\s*(?=[,\}\]])'),
      (_) => 'null',
    );
  }
  return text;
}

void main() {
  test('NaN/Infinity 数值替换后可正常解析', () {
    const raw = '{"type": "status", "data": {"battery": NaN, "temp": Infinity, "x": -Infinity, "ok": 1}}';
    final fixed = _sanitize(raw);
    final json = jsonDecode(fixed) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>;
    expect(data['battery'], isNull);
    expect(data['temp'], isNull);
    expect(data['x'], isNull);
    expect(data['ok'], 1);
  });

  test('字符串内的 NaN 不被误替换', () {
    const raw = '{"msg": "value NaN inside", "b": NaN}';
    final fixed = _sanitize(raw);
    final json = jsonDecode(fixed) as Map<String, dynamic>;
    expect(json['msg'], 'value NaN inside');
    expect(json['b'], isNull);
  });

  test('标准 JSON 不受影响', () {
    const raw = '{"type": "logs", "data": {"mode": "tail", "has_more": false}}';
    final json = jsonDecode(_sanitize(raw)) as Map<String, dynamic>;
    expect(json['type'], 'logs');
  });
}
