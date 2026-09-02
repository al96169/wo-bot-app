import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 音乐页 — 对齐 web-debug MusicView
///
/// 三 tab：本地音乐 / 播放列表 / 投播服务
/// 底部播放栏（进度/上一首/播放暂停/下一首/停止/音量）
class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({super.key});
  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage> {
  String _tab = 'local'; // local / playlist / stream
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    // 2s 轮询音乐状态（对齐 web-debug refreshTimer）
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final m = ref.read(connectionManagerProvider.notifier);
      m.sendGetMusicStatus();
      // 兜底：服务已运行但列表为空（如进入页面时服务未就绪、
      // 首次 music_list 被"服务未就绪"响应跳过）→ 补拉列表
      final store = ref.read(robotDataProvider.notifier);
      final svcRunning = store.services.any(
        (s) => s.serviceId == 'music_player' && s.status == 'running',
      );
      if (svcRunning && store.musicSongs.isEmpty) {
        m.sendGetMusicList();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final m = ref.read(connectionManagerProvider.notifier);
    m.sendGetMusicList();
    m.sendGetMusicStatus();
  }

  /// 启动音乐服务并等待就绪后自动拉取列表。
  /// 音乐服务冷启动需 1-3s，立即发 music_list 会命中 robot 端
  /// "服务未就绪"响应（无 songs），导致列表一直为空。
  void _startMusicService() {
    final m = ref.read(connectionManagerProvider.notifier);
    m.sendServiceControl('music_player', 'start');
    AppToast.show('正在启动音乐服务...');
    // 轮询等待服务 running 后拉取列表（最多 ~10s）
    var attempts = 0;
    Timer.periodic(const Duration(milliseconds: 800), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      attempts++;
      final services = ref.read(robotDataProvider.notifier).services;
      final running = services.any(
        (s) => s.serviceId == 'music_player' && s.status == 'running',
      );
      if (running || attempts >= 13) {
        t.cancel();
        _refresh();
        if (!running) {
          AppToast.show('音乐服务启动超时', type: AppToastType.error);
        }
      }
    });
  }

  void _send(String cmd, [Map<String, dynamic> data = const {}]) {
    ref.read(connectionManagerProvider.notifier).send(cmd, data);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final music = store.music;
    final songs = store.musicSongs;
    final services = store.services;
    final musicSvcRunning =
        services.any((s) => s.serviceId == 'music_player' && s.status == 'running');

    // 播放栏显示条件（对齐 web-debug showPlayerBar）
    final isActive = music.status == 'playing' || music.status == 'paused';
    final isRemoteSource =
        music.activeSource == 'dlna' ||
        music.activeSource == 'airplay' ||
        (music.status == 'playing' && music.currentTrack == null);

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '音乐'),
            // 服务未运行提示
            if (!musicSvcRunning)
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x14FFC107),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0x4DFFC107),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Color(0xFFFF9500),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '音乐播放服务未运行',
                          style: TextStyle(fontSize: 13, color: Color(0xFF3D3D3D)),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _startMusicService(),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0256FF),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 30),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('启动'),
                      ),
                    ],
                  ),
                ),
              ),
            // Tab 导航
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 6, 15, 8),
              child: Row(
                children: [
                  _TabBtn(
                    label: '本地音乐',
                    active: _tab == 'local',
                    onTap: () => setState(() => _tab = 'local'),
                  ),
                  const SizedBox(width: 8),
                  _TabBtn(
                    label: '播放列表',
                    active: _tab == 'playlist',
                    badge: music.playlist.length,
                    onTap: () => setState(() => _tab = 'playlist'),
                  ),
                  const SizedBox(width: 8),
                  _TabBtn(
                    label: '投播服务',
                    active: _tab == 'stream',
                    onTap: () => setState(() => _tab = 'stream'),
                  ),
                ],
              ),
            ),
            // 内容
            Expanded(
              child: switch (_tab) {
                'playlist' => _buildPlaylist(music),
                'stream' => _buildStream(music),
                _ => _buildLocal(songs, music),
              },
            ),
            // 底部播放栏
            if (isActive) _buildPlayerBar(music, isRemoteSource),
          ],
        ),
      ),
    );
  }

  // ---- 本地音乐 tab ----
  Widget _buildLocal(List<MusicTrack> songs, MusicStatus music) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: songs.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(40),
              children: const [
                Icon(Icons.music_note, size: 40, color: Color(0xFFC7C7CC)),
                SizedBox(height: 12),
                Text(
                  '暂无歌曲\n将音乐文件放入机器人的 ~/media/music 目录',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final s = songs[i];
                final isCurrent =
                    music.currentTrack?.filename == s.filename &&
                    music.status == 'playing';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: isCurrent
                          ? const Color(0xFF0256FF)
                          : const Color(0xFFEEEEEE),
                      width: isCurrent ? 1 : 0.5,
                    ),
                  ),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    leading: Icon(
                      isCurrent ? Icons.graphic_eq : Icons.music_note,
                      color: isCurrent
                          ? const Color(0xFF0256FF)
                          : const Color(0xFF8E8E93),
                    ),
                    title: Text(
                      s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      '${(s.format ?? '').toUpperCase()} · ${_fmtSize(s.size)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                    onTap: () {
                      ref
                          .read(connectionManagerProvider.notifier)
                          .sendMusicPlay(s.filename);
                    },
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.playlist_add,
                        size: 20,
                        color: Color(0xFF0256FF),
                      ),
                      tooltip: '添加到队列',
                      onPressed: () {
                        ref
                            .read(connectionManagerProvider.notifier)
                            .sendMusicPlaylistAdd(s.filename);
                        AppToast.show('已添加: ${s.name}');
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  // ---- 播放列表 tab ----
  Widget _buildPlaylist(MusicStatus music) {
    final playlist = music.playlist;
    if (playlist.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_play, size: 40, color: Color(0xFFC7C7CC)),
            SizedBox(height: 12),
            Text(
              '播放列表为空\n从本地音乐中添加歌曲到播放队列',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 15, 8),
          child: Row(
            children: [
              Text(
                '共 ${playlist.length} 首',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  ref
                      .read(connectionManagerProvider.notifier)
                      .sendMusicPlaylistClear();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF453A),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 30),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
            itemCount: playlist.length,
            itemBuilder: (context, i) {
              final t = playlist[i];
              final isCurrent =
                  music.currentTrack?.filename == t.filename &&
                  music.status == 'playing';
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isCurrent
                        ? const Color(0xFF0256FF)
                        : const Color(0xFFEEEEEE),
                    width: isCurrent ? 1 : 0.5,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: SizedBox(
                    width: 24,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                  title: Text(
                    t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  onTap: () {
                    ref
                        .read(connectionManagerProvider.notifier)
                        .sendMusicPlay(t.filename);
                  },
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: Color(0xFFC7C7CC),
                    ),
                    onPressed: () {
                      ref
                          .read(connectionManagerProvider.notifier)
                          .sendMusicPlaylistRemove(i);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- 投播服务 tab ----
  Widget _buildStream(MusicStatus music) {
    final active = music.activeServices;
    return ListView(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
      children: [
        _StreamCard(
          name: 'DLNA / UPnP',
          detail: '设备名: Wo-Bot · 端口: 49452',
          active: active.contains('dlna'),
        ),
        const SizedBox(height: 10),
        _StreamCard(
          name: 'AirPlay',
          detail: '设备名: Wo-Bot · 协议: RAOP',
          active: active.contains('airplay'),
        ),
        const SizedBox(height: 10),
        _StreamCard(
          name: 'RTMP / HLS',
          detail: '地址: rtmp://192.168.1.47/live/wobot',
          active: active.contains('rtmp'),
        ),
        const SizedBox(height: 16),
        const Text(
          '提示：DLNA/AirPlay 推流播放时无法控制进度/上下一首/暂停。',
          style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
        ),
      ],
    );
  }

  // ---- 底部播放栏 ----
  Widget _buildPlayerBar(MusicStatus music, bool isRemoteSource) {
    final track = music.currentTrack;
    final dur = track?.duration ?? 0.0;
    final progress = dur > 0 ? (music.position / dur).clamp(0.0, 1.0) : 0.0;
    final title = switch (music.activeSource) {
      'dlna' => 'DLNA 推流播放中',
      'airplay' => 'AirPlay 推流播放中',
      _ => track?.name ?? '推流播放中',
    };

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
              // 进度条（远程源不可拖动）
              LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth;
                  return GestureDetector(
                    onTapUp: isRemoteSource || dur <= 0
                        ? null
                        : (d) {
                            final ratio =
                                (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
                            ref
                                .read(connectionManagerProvider.notifier)
                                .sendMusicSeek(ratio * dur);
                          },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFF0F0F0),
                        valueColor: const AlwaysStoppedAnimation(
                          Color(0xFF0256FF),
                        ),
                      ),
                    ),
                  );
                },
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
                          title,
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
                          '${_fmtTime(music.position)} / ${_fmtTime(dur)}'
                          '${isRemoteSource ? ' · ${_sourceTag(music)}' : ''}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 控制按钮（远程源不可控制）
                  if (!isRemoteSource) ...[
                    IconButton(
                      icon: const Icon(Icons.skip_previous, size: 22),
                      color: const Color(0xFF3D3D3D),
                      onPressed: () => _send('music_previous'),
                    ),
                    IconButton(
                      icon: Icon(
                        music.status == 'playing'
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 34,
                      ),
                      color: const Color(0xFF0256FF),
                      onPressed: () {
                        if (music.status == 'playing') {
                          _send('music_pause');
                        } else {
                          _send('music_resume');
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 22),
                      color: const Color(0xFF3D3D3D),
                      onPressed: () => _send('music_next'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop, size: 22),
                      color: const Color(0xFF3D3D3D),
                      onPressed: () => _send('music_stop'),
                    ),
                  ],
                ],
              ),
              // 音量（独立一行占满宽度，便于精确控制）
              Row(
                children: [
                  const Icon(
                    Icons.volume_down,
                    size: 16,
                    color: Color(0xFF8E8E93),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 4,
                        thumbShape: RoundSliderThumbShape(
                          enabledThumbRadius: 8,
                        ),
                        overlayShape: RoundSliderOverlayShape(
                          overlayRadius: 16,
                        ),
                        activeTrackColor: Color(0xFF0256FF),
                        inactiveTrackColor: Color(0xFFD8D8D8),
                      ),
                      child: Slider(
                        value: music.volume.toDouble().clamp(0, 100),
                        max: 100,
                        divisions: 100,
                        label: '${music.volume.round()}',
                        onChanged: (v) {
                          ref
                              .read(connectionManagerProvider.notifier)
                              .sendMusicVolume(v.round());
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${music.volume.round()}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF3D3D3D),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _sourceTag(MusicStatus music) {
    return switch (music.activeSource) {
      'dlna' => 'DLNA',
      'airplay' => 'AirPlay',
      _ => '推流',
    };
  }

  static String _fmtTime(double seconds) {
    if (seconds <= 0 || seconds.isInfinite) return '--:--';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toStringAsFixed(0).padLeft(2, '0')}';
  }

  static String _fmtSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '--';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Tab 按钮
class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final int badge;
  final VoidCallback onTap;
  const _TabBtn({
    required this.label,
    required this.active,
    this.badge = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 32,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active ? Colors.white : const Color(0xFF3D3D3D),
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF0256FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 投播服务卡片
class _StreamCard extends StatelessWidget {
  final String name;
  final String detail;
  final bool active;
  const _StreamCard({
    required this.name,
    required this.detail,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.cast_connected : Icons.cast,
            color: active ? const Color(0xFF34C759) : const Color(0xFF8E8E93),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0x1A34C759)
                  : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              active ? '● 运行中' : '○ 未启动',
              style: TextStyle(
                fontSize: 11,
                color: active
                    ? const Color(0xFF34C759)
                    : const Color(0xFF8E8E93),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
