import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/network/auth_callback_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动授权回调监听（wobot://auth/callback 深链）
  AuthCallbackHandler.instance.init();
  runApp(const ProviderScope(child: WoBotApp()));
}
