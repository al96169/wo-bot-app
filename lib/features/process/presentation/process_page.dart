import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 进程管理页 — 匹配 Pixso 5:4451
///
/// 服务列表（每行 57px：服务名 + 停止/重启按钮）
/// 数据源: service_status 消息 + sendServiceControl
class ProcessPage extends ConsumerStatefulWidget {
  const ProcessPage({super.key});
  @override
  ConsumerState<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends ConsumerState<ProcessPage> {
  @override
  void initState() {
    super.initState();
    // 进入页面拉取服务状态
    ref.read(connectionManagerProvider.notifier).sendGetServiceStatus();
  }

  void _control(String serviceId, String action, String name) {
    ref.read(connectionManagerProvider.notifier).sendServiceControl(serviceId, action);
    AppToast.show(
      action == 'start' ? '正在启动 $name...' : action == 'stop' ? '正在停止 $name...' : '正在重启 $name...',
      type: AppToastType.info,
    );
    // 延迟刷新状态
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) ref.read(connectionManagerProvider.notifier).sendGetServiceStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final services = store.services;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '进程'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async =>
                    ref.read(connectionManagerProvider.notifier).sendGetServiceStatus(),
                child: services.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(40),
                        children: const [
                          Icon(Icons.memory, size: 40, color: Color(0xFFC7C7CC)),
                          SizedBox(height: 12),
                          Text(
                            '暂无服务数据\n下拉刷新重试',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < services.length; i++) ...[
                                  if (i > 0)
                                    const Divider(height: 0.5, thickness: 0.5, color: Color(0xFFD8D8D8)),
                                  _ServiceRow(
                                    service: services[i],
                                    onStart: () => _control(services[i].serviceId, 'start', services[i].name),
                                    onStop: () => _control(services[i].serviceId, 'stop', services[i].name),
                                    onRestart: () => _control(services[i].serviceId, 'restart', services[i].name),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 服务行 — 匹配 Pixso 5:4455 (388×57: 名称 + 停止/启动/重启)
class _ServiceRow extends StatelessWidget {
  final dynamic service;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  const _ServiceRow({
    required this.service,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
  });

  String get _name => service.name as String? ?? '服务';
  String get _status => service.status as String? ?? '';

  @override
  Widget build(BuildContext context) {
    final running = _status == 'running';
    return SizedBox(
      height: 57,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Row(
          children: [
            // 状态圆点
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: running ? const Color(0xFF34C759) : const Color(0xFFC7C7CC),
              ),
            ),
            const SizedBox(width: 10),
            // 服务名 14sp (Pixso 5:4456)
            Expanded(
              child: Text(
                _name,
                style: const TextStyle(fontSize: 14, color: Color(0xFF3D3D3D)),
              ),
            ),
            // 操作按钮 (Pixso 5:4553, 76×27) — 停止/启动 + 重启（对齐 web-debug）
            if (running) ...[
              _ActionBtn(label: '停止', onTap: onStop),
              const SizedBox(width: 8),
            ] else ...[
              _ActionBtn(label: '启动', onTap: onStart),
              const SizedBox(width: 8),
            ],
            _ActionBtn(label: '重启', onTap: onRestart),
          ],
        ),
      ),
    );
  }
}

/// 操作按钮 — 27px 高，蓝色边框
class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF0256FF), width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0256FF)),
        ),
      ),
    );
  }
}
