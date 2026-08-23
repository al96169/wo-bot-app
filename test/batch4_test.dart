// 批次 4 测试：音乐状态/舞蹈/图库列表与分块下载解析
import 'package:flutter_test/flutter_test.dart';
import 'package:wo_bot/core/network/robot_data_store.dart';
import 'package:wo_bot/shared/models/robot_data.dart';

void main() {
  test('music_status 解析（播放中 + 当前曲目 + 播放列表）', () {
    final store = RobotDataStore();
    store.updateMusicFromJson({
      'status': 'playing',
      'volume': 80,
      'position': 35.5,
      'current_track': {
        'name': '晴天',
        'filename': 'qintian.mp3',
        'size': 4194304,
        'format': 'mp3',
        'duration': 180,
      },
      'playlist': [
        {'name': '晴天', 'filename': 'qintian.mp3'},
        {'name': '夜曲', 'filename': 'yequ.mp3'},
      ],
      'active_source': null,
      'active_services': ['dlna', 'airplay'],
    });

    expect(store.music.status, 'playing');
    expect(store.music.volume, 80);
    expect(store.music.position, 35.5);
    expect(store.music.currentTrack?.name, '晴天');
    expect(store.music.playlist.length, 2);
    expect(store.music.activeServices, contains('dlna'));
  });

  test('music_list 曲库解析', () {
    final store = RobotDataStore();
    store.setMusicSongs([
      {'name': '晴天', 'filename': 'qintian.mp3', 'format': 'mp3', 'size': 1000000},
      {'name': '夜曲', 'filename': 'yequ.mp3'},
    ]);
    expect(store.musicSongs.length, 2);
    expect(store.musicSongs.first.name, '晴天');
    expect(store.musicSongs.first.filename, 'qintian.mp3');
  });

  test('dance_list / dance_status 解析', () {
    final store = RobotDataStore();
    store.setDances([
      {'id': 'd1', 'name': '街舞', 'duration_sec': 90},
      {'id': 'd2', 'name': '机械舞', 'duration_sec': 120},
    ]);
    expect(store.dances.length, 2);
    expect(store.dances.first.id, 'd1');

    store.setDanceStatus('playing', danceId: 'd1', progress: 0.5, loop: true);
    expect(store.danceStatus, 'playing');
    expect(store.danceCurrentId, 'd1');
    expect(store.danceProgress, 0.5);
    expect(store.danceLoop, isTrue);
  });

  test('图库列表解析（files + storage + 分页）', () {
    final store = RobotDataStore();
    store.setGalleryItems([
      {
        'file_name': 'photo_001.jpg',
        'name': 'photo_001.jpg',
        'type': 'photo',
        'size_bytes': 204800,
        'thumbnail_base64': 'aGVsbG8=',
        'camera_id': 0,
        'timestamp': '2026-08-23 10:00',
      },
      {
        'file_name': 'video_001.mp4',
        'name': 'video_001.mp4',
        'type': 'video',
        'size_bytes': 10485760,
        'duration_s': 15.5,
        'camera_id': 1,
      },
    ]);
    expect(store.galleryItems.length, 2);
    final photo = store.galleryItems.first;
    expect(photo.type, 'photo');
    expect(photo.thumbnailBase64, 'aGVsbG8=');
    expect(photo.fileSize, 204800);
    expect(store.galleryItems[1].durationSec, 15.5);

    store.setGalleryPageInfo(1, 50, true);
    expect(store.galleryPage, 1);
    expect(store.galleryTotal, 50);
    expect(store.galleryHasMore, isTrue);

    store.setGalleryStorageFromJson({
      'total_bytes': 1024 * 1024 * 1024,
      'used_bytes': 512 * 1024 * 1024,
      'available_bytes': 512 * 1024 * 1024,
    });
    expect(store.galleryStorage?.totalBytes, 1073741824);
  });

  test('图库分块下载结果通知', () {
    final store = RobotDataStore();
    GalleryDownloadResult? captured;
    store.galleryDownload.addListener(() {
      captured = store.galleryDownload.value;
    });

    store.notifyGalleryDownload(
      const GalleryDownloadResult(
        fileName: 'photo_001.jpg',
        bytes: [1, 2, 3],
        sizeBytes: 3,
      ),
    );
    expect(captured, isNotNull);
    expect(captured!.fileName, 'photo_001.jpg');
    expect(captured!.isSuccess, isTrue);
    expect(captured!.bytes, [1, 2, 3]);

    // 失败结果
    store.notifyGalleryDownload(
      const GalleryDownloadResult(
        fileName: 'x.jpg',
        bytes: [],
        error: '文件过大',
      ),
    );
    expect(captured!.isSuccess, isFalse);
    expect(captured!.error, '文件过大');
  });

  test('SoftwareTask 进度模型字段', () {
    final t = SoftwareTask(
      id: '1',
      package: 'hello',
      action: 'install',
      progress: 30,
      startedAt: DateTime.now(),
    );
    expect(t.isRunning, isTrue);
    expect(t.progress, 30);
  });
}
