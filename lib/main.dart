import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/network/account_service.dart';
import 'core/network/auth_callback_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时加载账号 token（否则重启后 accessToken 为 null，
  // 个人页外点云端设备会误报"需登录"）
  await AccountService.instance.init();
  // 启动授权回调监听（wobot://auth/callback 深链）
  AuthCallbackHandler.instance.init();
  runApp(const ProviderScope(child: WoBotApp()));
}
