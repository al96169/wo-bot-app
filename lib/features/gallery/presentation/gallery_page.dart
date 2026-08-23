import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 图库页 — 对齐 web-debug GalleryView
///
/// 工具栏(刷新/类型筛选/布局/多选) + 存储空间条 + 网格/列表 +
/// 预览弹层(下载/删除) + 滚动分页加载
class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});
  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  String _filter = 'all'; // all / photo / video
  String _layout = 'grid'; // grid / list
  bool _multiSelect = false;
  final Set<String> _selected = {};
  /// 缩略图 base64 → 解码字节缓存（避免每次 rebuild 重复解码导致闪烁）
  final Map<String, Uint8List> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    // 首帧后再刷新：resetGallery 修改 provider，initState 中直接调用会抛
    // "Tried to modify a provider while the widget tree was building"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    final store = ref.read(robotDataProvider.notifier);
    store.resetGallery();
    store.galleryLoading = true;
    store.notify();
    ref
        .read(connectionManagerProvider.notifier)
        .sendGetGalleryList(type: _filter);
  }

  void _loadMore() {
    final store = ref.read(robotDataProvider.notifier);
    if (store.galleryLoading || !store.galleryHasMore) return;
    store.galleryLoading = true;
    store.notify();
    ref
        .read(connectionManagerProvider.notifier)
        .sendGetGalleryList(
          type: _filter,
          page: store.galleryPage + 1,
        );
  }

  void _changeFilter(String type) {
    if (_filter == type) return;
    _filter = type;
    _refresh();
  }

  /// 下载单个文件（分块组装后保存到应用文档目录 + 弹打开方式）
  Future<void> _download(String fileName) async {
    AppToast.show('正在下载: $fileName');
    final manager = ref.read(connectionManagerProvider.notifier);
    final store = ref.read(robotDataProvider.notifier);
    // 图库下载必须走 DataChannel 分块（远程 WebRTC 场景无直连 HTTP）：
    // 先确保 DC 就绪，再发送 camera_media_download
    final dcReady = await manager.ensureDataChannelForDownload();
    if (!dcReady) {
      if (mounted) {
        AppToast.show('下载失败: 数据通道未就绪', type: AppToastType.error);
      }
      return;
    }
    // 发送下载请求（DC 优先，机器人端在 DC 上下文中分块发送 start/chunk/end）
    manager.sendGalleryDownload(fileName);
    final result = await _waitDownload(store, fileName);
    if (!mounted) return;
    if (result == null || !result.isSuccess) {
      AppToast.show(
        '下载失败: ${result?.error ?? '超时'}',
        type: AppToastType.error,
      );
      return;
    }
    // 保存到应用文档目录
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(result.bytes);
      if (!mounted) return;
      AppToast.show('下载完成: $fileName', type: AppToastType.success);
      // 弹系统打开方式
      OpenFilex.open(file.path);
    } catch (e) {
      debugPrint('[Gallery] 保存失败: $e');
      if (mounted) {
        AppToast.show('保存失败: $e', type: AppToastType.error);
      }
    }
  }

  /// 等待指定文件名的下载结果（订阅 store.galleryDownload）
  /// 视频分块传输可能较慢，超时放宽到 120s
  Future<GalleryDownloadResult?> _waitDownload(
    RobotDataStore store,
    String fileName,
  ) async {
    final completer = Completer<GalleryDownloadResult?>();
    void listener() {
      final r = store.galleryDownload.value;
      if (r != null && r.fileName == fileName) {
        completer.complete(r);
      }
    }

    store.galleryDownload.addListener(listener);
    final timer = Timer(const Duration(seconds: 120), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      store.galleryDownload.removeListener(listener);
    }
  }

  void _deleteItems(List<String> names) {
    if (names.isEmpty) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除选中的 ${names.length} 个文件？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF453A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        ref
            .read(connectionManagerProvider.notifier)
            .sendGalleryDelete(names);
        _selected.clear();
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final items = store.galleryItems;
    final storage = store.galleryStorage;
    final loading = store.galleryLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '图库'),
            // 工具栏
            _buildToolbar(store),
            // 存储空间条
            if (storage != null && storage.totalBytes > 0) _buildStorageBar(storage),
            // 列表
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 80) {
                    _loadMore();
                  }
                  return false;
                },
                child: items.isEmpty && !loading
                    ? _buildEmpty()
                    : _buildItems(items, loading),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(RobotDataStore store) {
    final total = store.galleryTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 6, 15, 8),
      child: Column(
        children: [
          Row(
            children: [
              // 刷新
              _IconBtn(
                icon: Icons.refresh,
                onTap: ref.read(robotDataProvider.notifier).galleryLoading
                    ? null
                    : _refresh,
              ),
              const SizedBox(width: 8),
              // 类型筛选
              _FilterChip(
                label: '全部',
                active: _filter == 'all',
                onTap: () => _changeFilter('all'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '照片',
                active: _filter == 'photo',
                onTap: () => _changeFilter('photo'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '视频',
                active: _filter == 'video',
                onTap: () => _changeFilter('video'),
              ),
              const Spacer(),
              // 布局切换
              _IconBtn(
                icon: _layout == 'grid'
                    ? Icons.view_list
                    : Icons.grid_view,
                onTap: () =>
                    setState(() => _layout = _layout == 'grid' ? 'list' : 'grid'),
              ),
              const SizedBox(width: 8),
              // 多选
              _IconBtn(
                icon: Icons.checklist,
                active: _multiSelect,
                onTap: () {
                  setState(() {
                    _multiSelect = !_multiSelect;
                    _selected.clear();
                  });
                },
              ),
            ],
          ),
          if (_multiSelect && _selected.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '已选 ${_selected.length} 项',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF3D3D3D)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _downloadSelected,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('下载'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0256FF),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _deleteItems(_selected.toList()),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF453A),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          // 数量
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${store.galleryItems.length} / $total 项',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ),
        ],
      ),
    );
  }

  void _downloadSelected() {
    for (final name in _selected) {
      _download(name);
    }
  }

  Widget _buildStorageBar(GalleryStorage storage) {
    final usedPercent = (storage.usedBytes / storage.totalBytes).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      child: Row(
        children: [
          const Text(
            '存储空间',
            style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usedPercent,
                minHeight: 6,
                backgroundColor: const Color(0xFFF0F0F0),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF0256FF)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_fmtSize(storage.usedBytes)} / ${_fmtSize(storage.totalBytes)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(40),
      children: const [
        Icon(Icons.photo_library_outlined, size: 40, color: Color(0xFFC7C7CC)),
        SizedBox(height: 12),
        Text(
          '暂无媒体文件\n在遥控面板拍照或录像后，文件会显示在这里',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
        ),
      ],
    );
  }

  Widget _buildItems(List<GalleryItem> items, bool loading) {
    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: _layout == 'grid'
          ? GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),
              itemCount: items.length + (loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final item = items[i];
                return _GridCard(
                  item: item,
                  thumbBytes: _thumbBytes(item),
                  selected: _selected.contains(item.name),
                  multiSelect: _multiSelect,
                  onTap: () => _openPreview(item),
                  onSelect: () => _toggleSelect(item.name),
                  onDelete: () => _deleteItems([item.name]),
                );
              },
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
              itemCount: items.length + (loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                final item = items[i];
                return _ListRow(
                  item: item,
                  thumbBytes: _thumbBytes(item),
                  selected: _selected.contains(item.name),
                  multiSelect: _multiSelect,
                  onTap: () => _openPreview(item),
                  onSelect: () => _toggleSelect(item.name),
                  onDownload: () => _download(item.name),
                  onDelete: () => _deleteItems([item.name]),
                );
              },
            ),
    );
  }

  void _toggleSelect(String name) {
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  void _openPreview(GalleryItem item) {
    if (_multiSelect) {
      _toggleSelect(item.name);
      return;
    }
    // 预览弹层：缩略图全屏展示 + 下载/删除
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (ctx) => _PreviewSheet(
        item: item,
        thumbBytes: _thumbBytes(item),
        onDownload: () {
          Navigator.of(ctx).pop();
          _download(item.name);
        },
        onDelete: () {
          Navigator.of(ctx).pop();
          _deleteItems([item.name]);
        },
      ),
    );
  }

  /// 解码缩略图 base64（带缓存，避免重建时重复解码闪烁）
  Uint8List? _thumbBytes(GalleryItem item) {
    final b64 = item.thumbnailBase64;
    if (b64 == null || b64.isEmpty) return null;
    final cached = _thumbCache[b64];
    if (cached != null) return cached;
    try {
      final bytes = base64Decode(b64);
      _thumbCache[b64] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static String _fmtSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _fmtDuration(double? s) {
    if (s == null || s <= 0) return '';
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0 ? '$m分${sec.round()}秒' : '${sec.round()}秒';
  }
}

/// 网格卡片
class _GridCard extends StatelessWidget {
  final GalleryItem item;
  final Uint8List? thumbBytes;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final VoidCallback onDelete;
  const _GridCard({
    required this.item,
    required this.thumbBytes,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF0256FF) : const Color(0xFFEEEEEE),
            width: selected ? 1.5 : 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 缩略图（已解码字节，gaplessPlayback 避免重建闪烁）
            if (thumbBytes != null)
              Image.memory(
                thumbBytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _ThumbPlaceholder(item: item),
              )
            else
              _ThumbPlaceholder(item: item),
            // 视频时长角标
            if (item.type == 'video' && (item.durationSec ?? 0) > 0)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _GalleryPageState._fmtDuration(item.durationSec),
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ),
            // 多选勾选
            if (multiSelect)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: onSelect,
                  child: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected
                        ? const Color(0xFF0256FF)
                        : const Color(0x88FFFFFF),
                  ),
                ),
              ),
            // 底部信息
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表行
class _ListRow extends StatelessWidget {
  final GalleryItem item;
  final Uint8List? thumbBytes;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  const _ListRow({
    required this.item,
    required this.thumbBytes,
    required this.selected,
    required this.multiSelect,
    required this.onTap,
    required this.onSelect,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF0256FF) : const Color(0xFFEEEEEE),
          width: selected ? 1.5 : 0.5,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
        leading: GestureDetector(
          onTap: multiSelect ? onSelect : null,
          child: SizedBox(
            width: 48,
            height: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: thumbBytes != null
                  ? Image.memory(
                      thumbBytes!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => Icon(
                        item.type == 'video' ? Icons.movie : Icons.photo,
                        color: const Color(0xFFC7C7CC),
                      ),
                    )
                  : Container(
                      color: const Color(0xFFF5F5F5),
                      child: Icon(
                        item.type == 'video' ? Icons.movie : Icons.photo,
                        color: const Color(0xFFC7C7CC),
                      ),
                    ),
            ),
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          '${item.type == 'video' ? '视频' : '照片'}'
          '${item.cameraId != null ? ' · 摄像头 ${item.cameraId}' : ''}'
          ' · ${_GalleryPageState._fmtSize(item.fileSize)}'
          '${item.durationSec != null ? ' · ${_GalleryPageState._fmtDuration(item.durationSec)}' : ''}'
          '${item.timestamp != null ? ' · ${item.timestamp}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
        ),
        trailing: multiSelect
            ? Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? const Color(0xFF0256FF)
                    : const Color(0xFFC7C7CC),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.download_outlined,
                      size: 20,
                      color: Color(0xFF0256FF),
                    ),
                    onPressed: onDownload,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Color(0xFFFF453A),
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
      ),
    );
  }
}

/// 缩略图占位
class _ThumbPlaceholder extends StatelessWidget {
  final GalleryItem item;
  const _ThumbPlaceholder({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF5F5F5),
      child: Icon(
        item.type == 'video' ? Icons.movie : Icons.photo,
        size: 28,
        color: const Color(0xFFC7C7CC),
      ),
    );
  }
}

/// 工具栏小图标按钮
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  const _IconBtn({required this.icon, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0x1A0256FF) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? const Color(0xFF0256FF) : const Color(0xFFD8D8D8),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? const Color(0xFF0256FF) : const Color(0xFF3D3D3D),
        ),
      ),
    );
  }
}

/// 筛选 chip
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0x1A0256FF) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? const Color(0xFF0256FF) : const Color(0xFFD8D8D8),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? const Color(0xFF0256FF) : const Color(0xFF3D3D3D),
          ),
        ),
      ),
    );
  }
}

/// 预览弹层 — 缩略图大图 + 文件名 + 下载/删除
class _PreviewSheet extends StatelessWidget {
  final GalleryItem item;
  final Uint8List? thumbBytes;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  const _PreviewSheet({
    required this.item,
    required this.thumbBytes,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 大图
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: thumbBytes != null
                    ? Image.memory(
                        thumbBytes!,
                        height: 240,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => SizedBox(
                          height: 200,
                          child: Icon(
                            item.type == 'video' ? Icons.movie : Icons.photo,
                            size: 64,
                            color: const Color(0xFFC7C7CC),
                          ),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        height: 200,
                        color: const Color(0xFFF5F5F5),
                        child: Icon(
                          item.type == 'video' ? Icons.movie : Icons.photo,
                          size: 64,
                          color: const Color(0xFFC7C7CC),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            // 文件名 + 元信息
            Text(
              item.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${item.type == 'video' ? '视频' : '照片'}'
              '${item.cameraId != null ? ' · 摄像头 ${item.cameraId}' : ''}'
              ' · ${_GalleryPageState._fmtSize(item.fileSize)}'
              '${item.durationSec != null ? ' · ${_GalleryPageState._fmtDuration(item.durationSec)}' : ''}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 16),
            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF453A),
                      side: const BorderSide(color: Color(0xFFFF453A)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('下载'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0256FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
