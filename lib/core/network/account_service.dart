import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'device_store.dart';

/// 用户信息 — 匹配 web-debug UserInfo
class UserInfo {
  final String sub;
  final String? email;
  final String? name;
  final String? picture;

  const UserInfo({required this.sub, this.email, this.name, this.picture});

  factory UserInfo.fromJson(Map<String, dynamic> json) => UserInfo(
    sub: json['sub'] as String? ?? '',
    email: json['email'] as String?,
    name: json['name'] as String?,
    picture: json['picture'] as String?,
  );
}

/// 账号服务 — 匹配 web-debug useAuth.ts + services/account.ts
///
/// OAuth2 PKCE 流程:
/// 1. login() → 生成 PKCE pair → 跳转授权页面
/// 2. 回调 → handleCallback(code, state) → 换取 token → 获取用户信息
/// 3. 自动刷新 token
class AccountService {
  static AccountService? _instance;
  static AccountService get instance => _instance ??= AccountService._();

  AccountService._();

  /// HTTP 客户端 — 可注入 MockClient 进行测试
  http.Client httpClient = http.Client();

  // API 配置 — 匹配生产 wo-bot-account 服务（R00041 自定义授权码流程）
  // 用户中心/授权页: https://user.wo-bot.com（/app-new-bind）
  // 设备管理 API: https://api.wo-bot.com（/api/oauth/*、/api/devices）
  static const String _apiBase = 'https://api.wo-bot.com';
  static const String _authWebUrl = 'https://user.wo-bot.com';

  // App 应用标识与回调 URI（默认值，正式接入前需与 wo-bot-account 确认）
  // 回调 scheme: wobot://（Android intent-filter + iOS CFBundleURLTypes 已注册）
  static const String _clientId = 'wo-bot-app';
  static const String _redirectUri = 'wobot://auth/callback';

  // 授权 scope — 与 web-debug 一致（设备 + 授权应用管理）
  static const String _scope = 'devices apps';

  // 状态
  String? accessToken;
  String? refreshToken;
  int tokenExpiresAt = 0;
  UserInfo? user;
  bool _initialized = false;

  /// 登录/登出状态变化回调（个人页刷新用）
  VoidCallback? onAuthStateChanged;

  /// 通知登录状态已变化
  void notifyAuthChanged() {
    onAuthStateChanged?.call();
  }

  /// 测试用：重置单例状态，使 init() 可重新加载
  @visibleForTesting
  void resetForTest() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _initialized = false;
    accessToken = null;
    refreshToken = null;
    tokenExpiresAt = 0;
    user = null;
  }

  bool get isAuthenticated =>
      accessToken != null &&
      DateTime.now().millisecondsSinceEpoch < tokenExpiresAt;
  String? get accountToken => isAuthenticated ? accessToken : null;

  /// 初始化 — 从 localStorage 加载 token
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('wobot_access_token');
    refreshToken = prefs.getString('wobot_refresh_token');
    tokenExpiresAt = prefs.getInt('wobot_token_expires_at') ?? 0;
    final userRaw = prefs.getString('wobot_user');
    if (userRaw != null) {
      try {
        user = UserInfo.fromJson(jsonDecode(userRaw) as Map<String, dynamic>);
      } catch (_) {}
    }
    _initialized = true;

    if (isAuthenticated) {
      _scheduleRefresh();
    } else if (refreshToken != null) {
      // 尝试刷新
      await _refresh();
    }
  }

  /// 生成 PKCE code_verifier (64 字符随机串)
  String _generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(64, (_) => random.nextInt(251) + 5);
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// 生成 PKCE code_challenge = BASE64URL(SHA256(code_verifier))
  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  /// 生成 state (32 字符随机串)
  String _generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(251) + 5);
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// 登录 — 生成 PKCE 并返回授权 URL
  ///
  /// 返回授权 URL，由调用方打开浏览器跳转
  Future<String?> login() async {
    try {
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);
      final state = _generateState();

      // 保存 PKCE session
      final prefs = await SharedPreferences.getInstance();
      final pkceSession = jsonEncode({
        'code_verifier': codeVerifier,
        'state': state,
        'redirect_uri': _redirectUri,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await prefs.setString('wobot_pkce_session', pkceSession);

      // 构建授权 URL — 跳转用户中心 /app-new-bind 授权确认页
      final uri = Uri.parse('$_authWebUrl/app-new-bind').replace(
        queryParameters: {
          'client_id': _clientId,
          'redirect_uri': _redirectUri,
          'scope': _scope,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );

      debugPrint('[Account] 授权 URL: $uri');
      return uri.toString();
    } catch (e) {
      debugPrint('[Account] login 错误: $e');
      return null;
    }
  }

  /// 发起授权登录 — 用系统浏览器打开用户中心授权页
  ///
  /// 返回是否成功打开浏览器
  Future<bool> launchLogin() async {
    final url = await login();
    if (url == null) return false;
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      debugPrint('[Account] 已打开授权页: $ok');
      return ok;
    } catch (e) {
      debugPrint('[Account] 打开授权页失败: $e');
      return false;
    }
  }

  /// 处理回调 — 用 code 换取 token
  Future<bool> handleCallback(String code, String state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pkceRaw = prefs.getString('wobot_pkce_session');
      if (pkceRaw == null) {
        debugPrint('[Account] PKCE session 不存在');
        return false;
      }

      final pkce = jsonDecode(pkceRaw) as Map<String, dynamic>;
      final savedState = pkce['state'] as String?;
      final codeVerifier = pkce['code_verifier'] as String?;

      // 验证 state (防 CSRF)
      if (savedState != state) {
        debugPrint('[Account] state 不匹配: $savedState != $state');
        return false;
      }

      // 检查 PKCE session 是否过期 (10 分钟)
      final createdAt = pkce['created_at'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - createdAt > 10 * 60 * 1000) {
        debugPrint('[Account] PKCE session 已过期');
        return false;
      }

      // POST /api/oauth/token 换取 token
      final response = await httpClient
          .post(
            Uri.parse('$_apiBase/api/oauth/token'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'clientId': _clientId,
              'redirectUri': _redirectUri,
              'codeVerifier': codeVerifier,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          '[Account] token 换取失败: ${response.statusCode} ${response.body}',
        );
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['data'] as Map<String, dynamic>? ?? data;
      accessToken = result['accessToken'] as String?;
      refreshToken = result['refreshToken'] as String? ?? refreshToken;
      final expiresIn = result['expiresIn'] as int? ?? 3600;
      tokenExpiresAt = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;

      if (accessToken == null) {
        debugPrint('[Account] 未获得 accessToken');
        return false;
      }

      // 保存 token
      await prefs.setString('wobot_access_token', accessToken!);
      if (refreshToken != null) {
        await prefs.setString('wobot_refresh_token', refreshToken!);
      }
      await prefs.setInt('wobot_token_expires_at', tokenExpiresAt);

      // 清除 PKCE session
      await prefs.remove('wobot_pkce_session');

      // 获取用户信息
      await _fetchUserInfo();

      _scheduleRefresh();
      debugPrint('[Account] 登录成功: ${user?.name ?? user?.email}');
      return true;
    } catch (e) {
      debugPrint('[Account] handleCallback 错误: $e');
      return false;
    }
  }

  /// 获取用户信息
  Future<void> _fetchUserInfo() async {
    if (accessToken == null) return;
    try {
      final response = await httpClient
          .get(
            Uri.parse('$_apiBase/api/oauth/userinfo'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final result = data['data'] as Map<String, dynamic>? ?? data;
        user = UserInfo.fromJson(result);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('wobot_user', jsonEncode(result));
      }
    } catch (e) {
      debugPrint('[Account] 获取用户信息失败: $e');
    }
  }

  /// 刷新 token
  Future<bool> _refresh() async {
    if (refreshToken == null) return false;
    try {
      final response = await httpClient
          .post(
            Uri.parse('$_apiBase/api/oauth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'refreshToken': refreshToken,
              'clientId': _clientId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = data['data'] as Map<String, dynamic>? ?? data;
      accessToken = result['accessToken'] as String? ?? accessToken;
      refreshToken = result['refreshToken'] as String? ?? refreshToken;
      final expiresIn = result['expiresIn'] as int? ?? 3600;
      tokenExpiresAt = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wobot_access_token', accessToken!);
      if (refreshToken != null) {
        await prefs.setString('wobot_refresh_token', refreshToken!);
      }
      await prefs.setInt('wobot_token_expires_at', tokenExpiresAt);

      _scheduleRefresh();
      return true;
    } catch (e) {
      debugPrint('[Account] 刷新 token 失败: $e');
      return false;
    }
  }

  /// 安排自动刷新 (过期前 5 分钟)
  Timer? _refreshTimer;

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    final remaining = tokenExpiresAt - DateTime.now().millisecondsSinceEpoch;
    final refreshAt = remaining - 5 * 60 * 1000; // 提前 5 分钟
    if (refreshAt <= 0) {
      _refresh();
      return;
    }
    _refreshTimer = Timer(Duration(milliseconds: refreshAt), () {
      if (isAuthenticated) _refresh();
    });
  }

  /// 登出
  Future<void> logout() async {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    accessToken = null;
    refreshToken = null;
    tokenExpiresAt = 0;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wobot_access_token');
    await prefs.remove('wobot_refresh_token');
    await prefs.remove('wobot_token_expires_at');
    await prefs.remove('wobot_user');
    debugPrint('[Account] 已登出');
  }

  /// 获取 HTTP 认证头
  Map<String, String> get authHeader {
    if (isAuthenticated && accessToken != null) {
      return {'Authorization': 'Bearer $accessToken'};
    }
    return {};
  }

  // ===================== API 调用 (匹配 web-debug account.ts) =====================

  /// 查询用户设备列表
  Future<List<Map<String, dynamic>>> getDevices() async {
    if (!isAuthenticated) return [];
    try {
      final response = await httpClient
          .get(Uri.parse('$_apiBase/api/devices'), headers: authHeader)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['data'] as List? ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[Account] getDevices 错误: $e');
    }
    return [];
  }

  /// 查询用户云端设备列表（类型化，供 UI 直接渲染）
  Future<List<CloudDevice>> fetchCloudDevices() async {
    final raw = await getDevices();
    return raw.map(CloudDevice.fromJson).toList();
  }

  /// 绑定设备到云端 — 对齐 web-debug account.ts
  /// 请求体必须是 {payload, proof}（机器人签发的绑定证明，R00040-1 9 步验证）
  Future<bool> bindDevice(Map<String, dynamic> payload, String proof) async {
    if (!isAuthenticated) return false;
    try {
      final body = {'payload': payload, 'proof': proof};
      final response = await httpClient
          .post(
            Uri.parse('$_apiBase/api/devices/bind'),
            headers: {...authHeader, 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Account] bindDevice 错误: $e');
      return false;
    }
  }

  /// 查询设备在线状态（对齐 web-debug account.ts getDeviceStatus）
  Future<Map<String, dynamic>?> getDeviceStatus(String robotId) async {
    if (!isAuthenticated) return null;
    try {
      final response = await httpClient
          .get(
            Uri.parse('$_apiBase/api/devices/$robotId/status'),
            headers: authHeader,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['data'] as Map<String, dynamic>? ?? data;
      }
    } catch (e) {
      debugPrint('[Account] getDeviceStatus 错误: $e');
    }
    return null;
  }

  /// 查询已授权的应用列表（对齐 web-debug account.ts getAuthorizedApps）
  Future<List<Map<String, dynamic>>> getAuthorizedApps() async {
    if (!isAuthenticated) return [];
    try {
      final response = await httpClient
          .get(
            Uri.parse('$_apiBase/api/oauth/apps'),
            headers: authHeader,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['data'] as List? ?? []).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[Account] getAuthorizedApps 错误: $e');
    }
    return [];
  }

  /// 撤销授权应用（对齐 web-debug account.ts revokeApp）
  Future<bool> revokeApp(String grantId) async {
    if (!isAuthenticated) return false;
    try {
      final response = await httpClient
          .delete(
            Uri.parse('$_apiBase/api/oauth/apps/$grantId'),
            headers: authHeader,
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Account] revokeApp 错误: $e');
      return false;
    }
  }

  /// 解绑设备
  Future<bool> unbindDevice(String robotId) async {
    if (!isAuthenticated) return false;
    try {
      final response = await httpClient
          .delete(
            Uri.parse('$_apiBase/api/devices/$robotId'),
            headers: authHeader,
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Account] unbindDevice 错误: $e');
      return false;
    }
  }

  /// 重命名设备
  Future<bool> renameDevice(String robotId, String robotName) async {
    if (!isAuthenticated) return false;
    try {
      final response = await httpClient
          .patch(
            Uri.parse('$_apiBase/api/devices/$robotId'),
            headers: {...authHeader, 'Content-Type': 'application/json'},
            body: jsonEncode({'robotName': robotName}),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Account] renameDevice 错误: $e');
      return false;
    }
  }
}
