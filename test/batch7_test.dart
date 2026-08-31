// 批次 7 测试：SSH 终端数据流 / 主题控制器 / 命令日志
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wo_bot/core/theme/theme_controller.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SSH 输出追加/清空 + shellCwd 同步', () {
    final store = RobotDataStore();
    expect(store.sshOutput.length, 0);

    store.addSshOutput('cmd', 'ls -la');
    store.addSshOutput('out', 'total 8');
    expect(store.sshOutput.length, 2);
    expect(store.sshOutput[0].type, 'cmd');
    expect(store.sshOutput[0].text, 'ls -la');

    store.setShellCwd('/home');
    expect(store.shellCwd, '/home');

    store.clearSshOutput();
    expect(store.sshOutput.length, 0);
  });

  test('命令日志追加/清空', () {
    final store = RobotDataStore();
    store.addCmdLog('send', 'exec', 'pwd');
    store.addCmdLog('send', 'emergency', '急停触发');
    expect(store.cmdLogs.length, 2);
    expect(store.cmdLogs.first.direction, 'send');
    expect(store.cmdLogs.first.type, 'exec');

    store.clearCmdLogs();
    expect(store.cmdLogs.length, 0);
  });

  test('ThemeController 三态循环 + 持久化', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = ThemeController();
    // 等待异步 _load() 完成（初始 auto → ThemeMode.system）
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(controller.mode, AppThemeMode.auto);
    expect(controller.state, ThemeMode.system);

    await controller.setMode(AppThemeMode.dark);
    expect(controller.mode, AppThemeMode.dark);
    expect(controller.state, ThemeMode.dark);

    await controller.cycle(); // dark → auto
    expect(controller.mode, AppThemeMode.auto);

    await controller.cycle(); // auto → light
    expect(controller.mode, AppThemeMode.light);
    expect(controller.state, ThemeMode.light);

    // 持久化验证：新实例应恢复 light
    final reloaded = ThemeController();
    // 等待异步加载
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(reloaded.mode, AppThemeMode.light);
  });
}
