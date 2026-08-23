import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 舞蹈页 — 对齐 web-debug DanceView
///
/// 舞蹈曲目网格 + 底部播放栏（进度/循环开关/播放暂停/停止）
class DancePage extends ConsumerStatefulWidget {
  const DancePage({super.key});
  @override
  ConsumerState<DancePage> createState() => _DancePageState();
}

class _DancePageState extends ConsumerState<DancePage> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _requestList();
    // 播放中每 1s 轮询进度（对齐 web-debug）
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final store = ref.read(robotDataProvider.notifier);
      if (store.danceStatus != 'stopped') {
        ref
            .read(connectionManagerProvider.notifier)
            .sendDanceCommand('status');
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _requestList() {
    ref.read(connectionManagerProvider.notifier).sendDanceCommand('list');
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final dances = store.dances;
    final status = store.danceStatus;
    final currentId = store.danceCurrentId;
    final progress = store.danceProgress;
    final isPlaying = status != 'stopped';
    final current = dances.where((d) => d.id == currentId).firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '舞蹈'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _requestList(),
                child: dances.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(40),
                        children: const [
                          Icon(Icons.celebration, size: 40, color: Color(0xFFC7C7CC)),
                          SizedBox(height: 12),
                          Text(
                            '暂无舞蹈数据\n点击刷新重试',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(15, 15, 15, 20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.2,
                        ),
                        itemCount: dances.length,
                        itemBuilder: (context, i) {
                          final d = dances[i];
                          final active =
                              currentId == d.id && isPlaying;
                          return _DanceCard(
                            dance: d,
                            active: active,
                            onTap: () {
                              ref
                                  .read(connectionManagerProvider.notifier)
                                  .sendDanceCommand('play', {
                                    'dance_id': d.id,
                                    'loop': store.danceLoop,
                                  });
                            },
                          );
                        },
                      ),
              ),
            ),
            // 底部播放栏
            _buildPlayerBar(store, status, current, isPlaying, progress),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerBar(
    RobotDataStore store,
    String status,
    DanceInfo? current,
    bool isPlaying,
    double progress,
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (progress * 100 / 100).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF0F0F0),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF0256FF)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPlaying
                              ? (current?.name ?? '舞蹈播放中')
                              : '无舞蹈播放',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1C1C1E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isPlaying
                              ? '${(progress * 100).round()}% · '
                                    '${status == 'playing' ? '播放中' : '已暂停'}'
                              : '点击 ▶ 开始播放',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 循环开关（点击即同步给机器人，避免轮询把本地开关覆盖回弹）
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '循环',
                        style: TextStyle(fontSize: 12, color: Color(0xFF3D3D3D)),
                      ),
                      Switch(
                        value: store.danceLoop,
                        onChanged: (v) {
                          store.danceLoop = v;
                          store.notify();
                          // 同步机器人端循环状态（dance set_loop），
                          // 否则 1s 轮询 dance_status 会用机器人端旧值覆盖本地开关
                          ref
                              .read(connectionManagerProvider.notifier)
                              .sendDanceCommand('set_loop', {'loop': v});
                        },
                        activeTrackColor: const Color(0xFF0256FF),
                      ),
                    ],
                  ),
                  // 控制按钮
                  IconButton(
                    icon: Icon(
                      status == 'playing'
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      size: 34,
                    ),
                    color: const Color(0xFF0256FF),
                    onPressed: () {
                      final m = ref.read(connectionManagerProvider.notifier);
                      if (status == 'stopped') {
                        if (store.dances.isNotEmpty) {
                          m.sendDanceCommand('play', {
                            'dance_id': store.dances.first.id,
                            'loop': store.danceLoop,
                          });
                        }
                      } else {
                        m.sendDanceCommand('pause');
                      }
                    },
                  ),
                  if (isPlaying)
                    IconButton(
                      icon: const Icon(Icons.stop, size: 22),
                      color: const Color(0xFF3D3D3D),
                      onPressed: () {
                        ref
                            .read(connectionManagerProvider.notifier)
                            .sendDanceCommand('stop');
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 舞蹈卡片
class _DanceCard extends StatelessWidget {
  final DanceInfo dance;
  final bool active;
  final VoidCallback onTap;
  const _DanceCard({
    required this.dance,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? const Color(0xFF0256FF) : const Color(0xFFEEEEEE),
            width: active ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dance.icon ?? '💃',
              style: const TextStyle(fontSize: 36),
            ),
            const SizedBox(height: 8),
            Text(
              dance.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _fmtDuration(dance.durationSec),
              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDuration(double sec) {
    if (sec <= 0) return '';
    final m = sec ~/ 60;
    final s = sec % 60;
    return m > 0 ? '$m分${s.round()}秒' : '${s.round()}秒';
  }
}
