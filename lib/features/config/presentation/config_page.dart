import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/widgets/feature_status_bar.dart';
import '../../client_management/presentation/client_management_page.dart';

/// 配置页 — 对齐 web-debug ConfigView
///
/// 分 tab：功能开关 / 运动方式 / 摄像头 / 网络 / 省电配置 / JSON 编辑器 / 绑定配置
/// 数据源: config_get → config_get_ack；保存用 config_set {config: 全量}
class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});
  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  String _tab = 'features';

  /// 编辑中的配置（深拷贝自 store.robotConfig）
  Map<String, dynamic> _edit = {};
  bool _loaded = false;

  /// JSON 编辑器状态
  String _jsonText = '';
  String _jsonError = '';
  bool _applying = false;

  static const _coreFeatures = ['websocket', 'exec', 'system'];

  static const _featureLabels = {
    'websocket': 'WebSocket 通信',
    'exec': '远程命令执行',
    'system': '系统管理',
    'motion': '运动控制',
    'camera': '摄像头',
    'gimbal': '云台控制',
    'dance': '跳舞',
    'music': '音乐播放',
    'voice_broadcast': '语音喊话',
  };

  @override
  void initState() {
    super.initState();
    // 首帧后拉取配置（避免 initState 修改 provider）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(connectionManagerProvider.notifier).sendConfigGet();
    });
  }

  Map<String, dynamic> _deepCopy(Map<String, dynamic> src) {
    return jsonDecode(jsonEncode(src)) as Map<String, dynamic>;
  }

  void _syncFromStore() {
    final store = ref.read(robotDataProvider.notifier);
    if (store.configLoaded && store.robotConfig.isNotEmpty) {
      setState(() {
        _edit = _deepCopy(store.robotConfig);
        _loaded = true;
        _jsonText = const JsonEncoder.withIndent('  ').convert(_edit);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    if (store.configLoaded && !_loaded) {
      _syncFromStore();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '配置'),
            // Tab 导航（横向滚动）
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                children: [
                  _TabChip(label: '功能', active: _tab == 'features', onTap: () => setState(() => _tab = 'features')),
                  const SizedBox(width: 6),
                  _TabChip(label: '运动', active: _tab == 'motion', onTap: () => setState(() => _tab = 'motion')),
                  const SizedBox(width: 6),
                  _TabChip(label: '摄像头', active: _tab == 'camera', onTap: () => setState(() => _tab = 'camera')),
                  const SizedBox(width: 6),
                  _TabChip(label: '网络', active: _tab == 'network', onTap: () => setState(() => _tab = 'network')),
                  const SizedBox(width: 6),
                  _TabChip(label: '省电', active: _tab == 'power', onTap: () => setState(() => _tab = 'power')),
                  const SizedBox(width: 6),
                  _TabChip(label: 'JSON', active: _tab == 'json', onTap: () => setState(() => _tab = 'json')),
                  const SizedBox(width: 6),
                  _TabChip(label: '绑定', active: _tab == 'bind', onTap: () => setState(() => _tab = 'bind')),
                ],
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 10),
                          Text('加载配置中...', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
                        ],
                      ),
                    )
                  : switch (_tab) {
                      'features' => _buildFeatures(),
                      'motion' => _buildMotion(),
                      'camera' => _buildCamera(),
                      'network' => _buildNetwork(),
                      'power' => _buildPower(),
                      'json' => _buildJsonEditor(),
                      'bind' => _buildBindEntry(),
                      _ => const SizedBox(),
                    },
            ),
            // 底部保存按钮（JSON tab 除外）
            if (_loaded && _tab != 'json')
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton(
                      onPressed: _applying ? null : _applyConfig,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0256FF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: Text(_applying ? '应用配置中...' : '应用配置'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 功能开关 ----
  Widget _buildFeatures() {
    final features = _edit['features'] as Map<String, dynamic>? ?? {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
      children: [
        _SectionCard(
          title: '功能列表',
          children: [
            for (final entry in features.entries)
              _SwitchRow(
                label: _featureLabels[entry.key] ?? entry.key,
                value: entry.value == true,
                enabled: !_coreFeatures.contains(entry.key),
                hint: _coreFeatures.contains(entry.key) ? '核心功能不可关闭' : null,
                onChanged: (v) {
                  setState(() => features[entry.key] = v);
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '修改后点击「应用配置」保存；部分变更需重启机器人生效。',
          style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
        ),
      ],
    );
  }

  // ---- 运动方式 ----
  Widget _buildMotion() {
    final motion = _edit['motion'] as Map<String, dynamic>? ?? {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
      children: [
        _SectionCard(
          title: '运动方式',
          children: [
            _DropdownRow(
              label: '驱动类型',
              value: motion['drive_type'] as String? ?? 'mecanum',
              options: const ['mecanum', 'ackermann', 'differential'],
              onChanged: (v) => setState(() => motion['drive_type'] = v),
            ),
            _SliderRow(
              label: '最大线速度',
              value: ((motion['max_linear_speed'] as num?)?.toDouble() ?? 1.0),
              min: 0.1,
              max: 2.0,
                            onChanged: (v) => setState(() => motion['max_linear_speed'] = v),
            ),
            _SliderRow(
              label: '最大角速度',
              value: ((motion['max_angular_speed'] as num?)?.toDouble() ?? 1.0),
              min: 0.1,
              max: 3.0,
                            onChanged: (v) => setState(() => motion['max_angular_speed'] = v),
            ),
            _TextFieldRow(
              label: '串口设备',
              value: motion['serial_port'] as String? ?? '',
              onChanged: (v) => setState(() => motion['serial_port'] = v),
            ),
            _TextFieldRow(
              label: '串口波特率',
              value: '${motion['serial_baudrate'] ?? 115200}',
              numeric: true,
              onChanged: (v) => setState(() => motion['serial_baudrate'] = int.tryParse(v) ?? 115200),
            ),
          ],
        ),
      ],
    );
  }

  // ---- 摄像头 ----
  Widget _buildCamera() {
    final camera = _edit['camera'] as Map<String, dynamic>? ?? {};
    final res = camera['resolution'] as Map<String, dynamic>? ?? {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
      children: [
        _SectionCard(
          title: '摄像头',
          children: [
            _SwitchRow(
              label: '启用摄像头',
              value: camera['enabled'] == true,
              onChanged: (v) => setState(() => camera['enabled'] = v),
            ),
            _DropdownRow(
              label: '默认摄像头',
              value: '${camera['default_camera'] ?? 0}',
              options: const ['0', '1'],
              onChanged: (v) => setState(() => camera['default_camera'] = int.tryParse(v) ?? 0),
            ),
            _SliderRow(
              label: '分辨率宽度',
              value: ((res['width'] as num?)?.toDouble() ?? 640),
              min: 320,
              max: 1280,
              step: 160,
                            onChanged: (v) => setState(() => res['width'] = v.round()),
            ),
            _SliderRow(
              label: '分辨率高度',
              value: ((res['height'] as num?)?.toDouble() ?? 480),
              min: 240,
              max: 960,
              step: 120,
                            onChanged: (v) => setState(() => res['height'] = v.round()),
            ),
            _DropdownRow(
              label: '拍照画质',
              value: camera['capture_quality'] as String? ?? 'high',
              options: const ['high', 'medium', 'low'],
              onChanged: (v) => setState(() => camera['capture_quality'] = v),
            ),
            _DropdownRow(
              label: '录像画质',
              value: camera['record_quality'] as String? ?? 'high',
              options: const ['high', 'medium', 'low'],
              onChanged: (v) => setState(() => camera['record_quality'] = v),
            ),
            _SwitchRow(
              label: '水平翻转',
              value: camera['flip_horizontal'] == true,
              onChanged: (v) => setState(() => camera['flip_horizontal'] = v),
            ),
            _SwitchRow(
              label: '垂直翻转',
              value: camera['flip_vertical'] == true,
              onChanged: (v) => setState(() => camera['flip_vertical'] = v),
            ),
          ],
        ),
      ],
    );
  }

  // ---- 网络 ----
  Widget _buildNetwork() {
    final server = _edit['server'] as Map<String, dynamic>? ?? {};
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
      children: [
        _SectionCard(
          title: '网络',
          children: [
            _TextFieldRow(
              label: '监听地址',
              value: server['host'] as String? ?? '0.0.0.0',
              onChanged: (v) => setState(() => server['host'] = v),
            ),
            _TextFieldRow(
              label: 'WebSocket 端口',
              value: '${server['port'] ?? 8765}',
              numeric: true,
              onChanged: (v) => setState(() => server['port'] = int.tryParse(v) ?? 8765),
            ),
            _TextFieldRow(
              label: 'HTTP 端口',
              value: '${server['http_port'] ?? 8000}',
              numeric: true,
              onChanged: (v) => setState(() => server['http_port'] = int.tryParse(v) ?? 8000),
            ),
            _TextFieldRow(
              label: '广播 IP（留空自动）',
              value: server['advertised_ip'] as String? ?? '',
              onChanged: (v) => setState(() => server['advertised_ip'] = v),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '修改广播 IP 后需重启服务生效。',
          style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
        ),
      ],
    );
  }

  // ---- 省电 ----
  Widget _buildPower() {
    final power = _edit['power_policy'] as Map<String, dynamic>? ?? {};
    final threshold = (power['threshold'] as num?)?.toInt() ?? 30;
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
      children: [
        _SectionCard(
          title: '省电配置',
          children: [
            _SliderRow(
              label: '省电模式阈值',
              value: threshold.toDouble(),
              min: 0,
              max: 100,
              step: 5,
              suffix: '%',
              displayValue: '$threshold%',
              onChanged: (v) => setState(() => power['threshold'] = v.round()),
            ),
          ],
        ),
      ],
    );
  }

  // ---- JSON 编辑器 ----
  Widget _buildJsonEditor() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
              ),
              child: TextField(
                controller: TextEditingController(text: _jsonText),
                maxLines: null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
                onChanged: (v) {
                  _jsonText = v;
                  try {
                    jsonDecode(v);
                    _jsonError = '';
                  } catch (e) {
                    _jsonError = 'JSON 格式错误: $e';
                  }
                },
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '{ "robot": { ... } }',
                ),
              ),
            ),
          ),
        ),
        if (_jsonError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text(
              _jsonError,
              style: const TextStyle(fontSize: 11, color: Color(0xFFFF3B30)),
            ),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      try {
                        _edit = jsonDecode(_jsonText) as Map<String, dynamic>;
                        _jsonError = '';
                        AppToast.show('JSON 已载入，请点击应用保存');
                      } catch (e) {
                        AppToast.show('JSON 格式错误', type: AppToastType.error);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0256FF),
                      side: const BorderSide(color: Color(0xFF0256FF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    child: const Text('载入'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _applying ? null : _applyConfig,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0256FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    child: Text(_applying ? '应用中...' : '应用配置'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- 绑定配置入口 ----
  Widget _buildBindEntry() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
      children: [
        _SectionCard(
          title: '绑定配置',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link, color: Color(0xFF0256FF)),
              title: const Text('客户端管理', style: TextStyle(fontSize: 14)),
              subtitle: const Text('查看绑定列表、分享码、密码配置', style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC)),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ClientManagementPage()),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  // ---- 应用配置 ----
  Future<void> _applyConfig() async {
    if (_applying) return;
    setState(() => _applying = true);
    try {
      ref.read(connectionManagerProvider.notifier).sendConfigSet(_edit);
      AppToast.show('配置已发送，等待确认...');
      // 5s 后刷新（config_set_ack 也会触发重新拉取）
      await Future<void>.delayed(const Duration(seconds: 5));
      if (mounted) {
        ref.read(connectionManagerProvider.notifier).sendConfigGet();
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }
}

// ===================== 通用组件 =====================

class _TabChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 32,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0256FF) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? const Color(0xFF0256FF) : const Color(0xFFD8D8D8),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: active ? Colors.white : const Color(0xFF3D3D3D),
          ),
        ),
      ),
    );
  }
}

/// 白底圆角卡片容器
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3D3D3D),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 开关行
class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final String? hint;
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: enabled ? const Color(0xFF3D3D3D) : const Color(0xFFC7C7CC),
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeTrackColor: const Color(0xFF0256FF),
        ),
      ],
    );
  }
}

/// 下拉选择行
class _DropdownRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const _DropdownRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D))),
        ),
        DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          underline: const SizedBox.shrink(),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

/// 滑杆行
class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double? step;
  final String suffix;
  final String? displayValue;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step,
    this.suffix = '',
    this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D))),
            ),
            Text(
              displayValue ?? '${value.toStringAsFixed(1)}$suffix',
              style: const TextStyle(fontSize: 13, color: Color(0xFF1C1C1E)),
            ),
          ],
        ),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 3,
            activeTrackColor: Color(0xFF0256FF),
            inactiveTrackColor: Color(0xFFD8D8D8),
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: step != null ? ((max - min) / step!).round() : null,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// 文本输入行
class _TextFieldRow extends StatelessWidget {
  final String label;
  final String value;
  final bool numeric;
  final ValueChanged<String> onChanged;
  const _TextFieldRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.numeric = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D))),
          ),
          Expanded(
            child: TextField(
              controller: TextEditingController(text: value),
              keyboardType: numeric ? TextInputType.number : TextInputType.text,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: Color(0xFFD8D8D8), width: 0.5),
                ),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
