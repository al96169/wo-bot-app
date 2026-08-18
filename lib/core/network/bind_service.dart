import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 绑定方式 — 匹配 web-debug BindingMethod
enum BindMethod { display, tts, gimbal, shareCode, password }

extension BindMethodExt on BindMethod {
  String get label {
    switch (this) {
      case BindMethod.display:
        return '屏幕显示';
      case BindMethod.tts:
        return '语音播报';
      case BindMethod.gimbal:
        return '云台动作';
      case BindMethod.shareCode:
        return '输入绑定码';
      case BindMethod.password:
        return '密码绑定';
    }
  }

  String get icon {
    switch (this) {
      case BindMethod.display:
        return '🖥️';
      case BindMethod.tts:
        return '🔊';
      case BindMethod.gimbal:
        return '🎮';
      case BindMethod.shareCode:
        return '🔗';
      case BindMethod.password:
        return '🔑';
    }
  }

  String get description {
    switch (this) {
      case BindMethod.display:
        return '机器人在屏幕上显示 6 位数字，请在此输入';
      case BindMethod.tts:
        return '机器人将通过语音播报 4 位数字，请在此输入';
      case BindMethod.gimbal:
        return '观察云台转动方向，依次点击对应方向按钮';
      case BindMethod.shareCode:
        return '输入从其他设备获取的分享码直接绑定';
      case BindMethod.password:
        return '输入机器人密码完成绑定';
    }
  }

  String get serverId {
    switch (this) {
      case BindMethod.display:
        return 'display';
      case BindMethod.tts:
        return 'tts';
      case BindMethod.gimbal:
        return 'gimbal';
      case BindMethod.shareCode:
        return 'share_code';
      case BindMethod.password:
        return 'password';
    }
  }

  static BindMethod fromServer(String id) {
    switch (id) {
      case 'display':
        return BindMethod.display;
      case 'tts':
        return BindMethod.tts;
      case 'gimbal':
        return BindMethod.gimbal;
      case 'share_code':
        return BindMethod.shareCode;
      case 'password':
        return BindMethod.password;
      default:
        return BindMethod.password;
    }
  }
}

/// 绑定步骤
enum BindStep {
  select,
  display,
  tts,
  gimbal,
  shareCode,
  password,
  verifying,
  success,
  failed,
}

/// 绑定凭证 — 匹配 web-debug StoredBinding
class BindingCredential {
  final String robotId;
  final String clientId;
  final String clientToken;
  final String deviceIp;
  final int devicePort;
  final String clientName;
  final String boundAt;

  const BindingCredential({
    required this.robotId,
    required this.clientId,
    required this.clientToken,
    required this.deviceIp,
    this.devicePort = 8765,
    this.clientName = '',
    this.boundAt = '',
  });

  Map<String, dynamic> toJson() => {
    'robotId': robotId,
    'clientId': clientId,
    'clientToken': clientToken,
    'deviceIp': deviceIp,
    'devicePort': devicePort,
    'clientName': clientName,
    'boundAt': boundAt,
  };

  factory BindingCredential.fromJson(Map<String, dynamic> json) =>
      BindingCredential(
        robotId: json['robotId'] as String? ?? '',
        clientId: json['clientId'] as String? ?? '',
        clientToken: json['clientToken'] as String? ?? '',
        deviceIp: json['deviceIp'] as String? ?? '',
        devicePort: json['devicePort'] as int? ?? 8765,
        clientName: json['clientName'] as String? ?? '',
        boundAt: json['boundAt'] as String? ?? '',
      );
}

/// 绑定服务 — 完全匹配 web-debug useWebSocket.ts 绑定逻辑
class BindService {
  static BindService? _instance;
  String _clientId = '';
  String _clientName = '';
  bool _initialized = false;

  BindStep step = BindStep.select;
  List<BindMethod> methods = [];
  String requestToken = '';
  String errorMessage = '';
  int attempts = 0;
  bool isSubmitting = false;
  BindingCredential? activeCredential;
  List<BindingCredential> allCredentials = [];

  // 云台输入
  final List<String> gimbalInputs = [];
  static const gimbalSequenceLength = 4;

  // 分享码
  String shareCode = '';
  String shareCreatedCode = '';
  int shareExpiresIn = 0;

  // Callbacks
  void Function(BindStep step)? onStepChanged;
  void Function(List<BindMethod> methods)? onMethodsReady;
  void Function(BindingCredential credential)? onBound;
  void Function(String error)? onError;
  void Function(String code, int expiresIn)? onShareCreated;

  BindService._();
  static BindService get instance => _instance ??= BindService._();

  String get clientId => _clientId;
  String get clientName => _clientName;
  bool get isBound => activeCredential != null;
  bool get isInitialized => _initialized;

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();

    _clientId =
        prefs.getString('wobot_client_id') ??
        'c-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(999999)}';
    await prefs.setString('wobot_client_id', _clientId);

    _clientName =
        prefs.getString('wobot_client_name') ??
        'Flutter ${DateTime.now().toIso8601String().substring(0, 10)}';
    await prefs.setString('wobot_client_name', _clientName);

    // 加载已保存凭证
    final raw = prefs.getString('wobot_bindings');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        allCredentials = list
            .map((j) => BindingCredential.fromJson(j as Map<String, dynamic>))
            .toList();
        debugPrint('[Bind] 已加载 ${allCredentials.length} 个绑定凭证');
      } catch (e) {
        debugPrint('[Bind] 凭证加载失败: $e');
      }
    }
    _initialized = true;
  }

  /// 获取指定 IP:Port 的已保存凭证
  BindingCredential? getCredentialFor(String ip, int port) {
    try {
      return allCredentials.firstWhere(
        (c) => c.deviceIp == ip && c.devicePort == port,
      );
    } catch (_) {
      return null;
    }
  }

  /// 按 robotId 获取凭证
  BindingCredential? getCredentialByRobotId(String robotId) {
    try {
      return allCredentials.firstWhere((c) => c.robotId == robotId);
    } catch (_) {
      return null;
    }
  }

  /// 保存绑定凭据
  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'wobot_bindings',
      jsonEncode(allCredentials.map((c) => c.toJson()).toList()),
    );
  }

  // ===================== 消息生成 (匹配 web-debug 格式) =====================

  /// 处理 auth_required 消息
  void handleAuthRequired(Map<String, dynamic>? data) {
    final rawMethods = data?['methods'];
    if (rawMethods is List && rawMethods.isNotEmpty) {
      methods = rawMethods
          .map((m) {
            if (m is String) return BindMethodExt.fromServer(m);
            if (m is Map)
              return BindMethodExt.fromServer(m['id'] as String? ?? '');
            return BindMethod.password;
          })
          .where((m) => m != BindMethod.shareCode)
          .toList();
    }
    // 始终添加分享码
    if (!methods.contains(BindMethod.shareCode)) {
      methods.add(BindMethod.shareCode);
    }

    step = BindStep.select;
    errorMessage = '';
    isSubmitting = false;
    gimbalInputs.clear();
    debugPrint(
      '[Bind] auth_required methods: ${methods.map((m) => m.serverId).join(', ')}',
    );
    onMethodsReady?.call(methods);
    onStepChanged?.call(BindStep.select);
  }

  /// 选择绑定方式 — 生成 requestToken
  void selectMethod(BindMethod method) {
    if (method == BindMethod.shareCode) {
      step = BindStep.shareCode;
      errorMessage = '';
      isSubmitting = false;
      onStepChanged?.call(BindStep.shareCode);
      return;
    }

    requestToken =
        'rt-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(99999).toString().padLeft(5, '0')}';
    errorMessage = '';
    gimbalInputs.clear();
    isSubmitting = false;

    switch (method) {
      case BindMethod.display:
        step = BindStep.display;
        break;
      case BindMethod.tts:
        step = BindStep.tts;
        break;
      case BindMethod.gimbal:
        step = BindStep.gimbal;
        break;
      case BindMethod.password:
        step = BindStep.password;
        break;
      default:
        step = BindStep.select;
        return;
    }
    onStepChanged?.call(step);
    debugPrint('[Bind] selectMethod: ${method.serverId} rt=$requestToken');
  }

  /// 生成 bind_request 消息 — { type: "bind_request", data: { requestToken, clientId, clientName, method } }
  Map<String, dynamic> buildBindRequest(BindMethod method) {
    return {
      'type': 'bind_request',
      'data': {
        'requestToken': requestToken,
        'clientId': _clientId,
        'clientName': _clientName,
        'method': method.serverId,
      },
    };
  }

  /// 生成 bind_verify 消息 — 验证码方式
  Map<String, dynamic> buildBindVerify(String code) {
    return {
      'type': 'bind_verify',
      'data': {'requestToken': requestToken, 'randomCode': code},
    };
  }

  /// 生成 bind_verify 消息 — 云台方向序列
  Map<String, dynamic> buildBindGimbalVerify() {
    return {
      'type': 'bind_verify',
      'data': {
        'requestToken': requestToken,
        'randomCode': gimbalInputs.join(','),
      },
    };
  }

  /// 生成 bind_share_use 消息 — 分享码直接绑定
  Map<String, dynamic> buildBindShareUse(String code) {
    return {
      'type': 'bind_share_use',
      'data': {
        'shareCode': code,
        'clientId': _clientId,
        'clientName': _clientName,
      },
    };
  }

  /// 生成 bind_password 消息
  Map<String, dynamic> buildBindPassword(String password) {
    return {
      'type': 'bind_password',
      'data': {'requestToken': requestToken, 'password': password},
    };
  }

  // 兼容早期测试与调用方使用的扁平消息 API；线上发送使用 build* 方法。
  Map<String, dynamic> getBindRequest(BindMethod method) => {
    'type': 'bind_request',
    'requestToken': requestToken,
    'clientId': _clientId,
    'clientName': _clientName,
    'method': method.serverId,
  };

  Map<String, dynamic> getBindVerify(String code) => {
    'type': 'bind_verify',
    'requestToken': requestToken,
    'randomCode': code,
  };

  Map<String, dynamic> getBindGimbalVerify() => {
    'type': 'bind_verify',
    'requestToken': requestToken,
    'sequence': List<String>.of(gimbalInputs),
  };

  Map<String, dynamic> getBindShareCode(String code) => {
    'type': 'bind_share_use',
    'shareCode': code,
    'clientId': _clientId,
    'clientName': _clientName,
  };

  /// 生成 bind_replay 消息 — 重新显示/播报验证码
  Map<String, dynamic> buildBindReplay() {
    return {
      'type': 'bind_replay',
      'data': {'requestToken': requestToken},
    };
  }

  /// 生成 bind_cancel 消息
  Map<String, dynamic> buildBindCancel() {
    return {
      'type': 'bind_cancel',
      'data': {'requestToken': requestToken},
    };
  }

  // ===================== 消息处理 =====================

  /// 处理 bind_request_ack
  void handleBindRequestAck(Map<String, dynamic> data) {
    debugPrint('[Bind] bind_request_ack: $data');
    isSubmitting = false;
    // 关键：服务器会签发新的 requestToken，必须用它覆盖本地生成的 token，
    // 后续 bind_verify 才能匹配服务器端绑定会话（对齐 web-debug BindView）
    final serverToken = data['requestToken'] as String?;
    if (serverToken != null && serverToken.isNotEmpty) {
      requestToken = serverToken;
      debugPrint('[Bind] 使用服务器签发 requestToken: $requestToken');
    }
    // 服务器确认请求，等待用户输入验证码
  }

  /// 处理 bind_success
  Future<void> handleBindSuccess(
    Map<String, dynamic> data,
    String deviceIp,
    int devicePort,
  ) async {
    final robotId =
        (data['robotId'] as String?) ?? (data['robot_id'] as String?) ?? '';
    final clientToken =
        (data['clientToken'] as String?) ??
        (data['client_token'] as String?) ??
        '';
    final clientId = (data['clientId'] as String?) ?? _clientId;

    final cred = BindingCredential(
      robotId: robotId,
      clientId: clientId,
      clientToken: clientToken,
      deviceIp: deviceIp,
      devicePort: devicePort,
      clientName: _clientName,
      boundAt: DateTime.now().toIso8601String(),
    );

    // 去重保存
    allCredentials.removeWhere(
      (c) =>
          c.robotId == robotId ||
          (c.deviceIp == deviceIp && c.devicePort == devicePort),
    );
    allCredentials.insert(0, cred);
    activeCredential = cred;

    await _saveCredentials();
    step = BindStep.success;
    errorMessage = '';
    isSubmitting = false;
    debugPrint('[Bind] bind_success: robotId=$robotId');
    onStepChanged?.call(BindStep.success);
    onBound?.call(cred);
  }

  /// 处理 bind_failed
  void handleBindFailed(Map<String, dynamic>? data) {
    errorMessage = data?['error'] as String? ?? '绑定失败';
    attempts = data?['attempts'] as int? ?? 0;
    step = BindStep.failed;
    isSubmitting = false;
    debugPrint('[Bind] bind_failed: $errorMessage (attempts=$attempts)');
    onStepChanged?.call(BindStep.failed);
    onError?.call(errorMessage);
  }

  /// 处理 bind_share_created
  void handleShareCreated(Map<String, dynamic> data) {
    shareCreatedCode = data['code'] as String? ?? '';
    shareExpiresIn = data['expires_in'] as int? ?? 0;
    debugPrint(
      '[Bind] share_created: $shareCreatedCode (expires in ${shareExpiresIn}s)',
    );
    onShareCreated?.call(shareCreatedCode, shareExpiresIn);
  }

  /// 重置到选择步骤
  void resetToSelect() {
    step = BindStep.select;
    errorMessage = '';
    isSubmitting = false;
    gimbalInputs.clear();
    requestToken = '';
    onStepChanged?.call(BindStep.select);
  }

  /// 设置 verifying 状态
  void setVerifying() {
    isSubmitting = true;
    step = BindStep.verifying;
    onStepChanged?.call(BindStep.verifying);
  }

  /// 获取认证 URL 参数 (用于 WebSocket 连接)
  Map<String, String> getAuthParams({String? shareCode, String? accountToken}) {
    final params = <String, String>{'clientId': _clientId};
    if (activeCredential != null) {
      params['clientToken'] = activeCredential!.clientToken;
    }
    if (shareCode != null && shareCode.isNotEmpty) {
      params['shareCode'] = shareCode;
    }
    if (accountToken != null && accountToken.isNotEmpty) {
      params['accountToken'] = accountToken;
    }
    return params;
  }
}
