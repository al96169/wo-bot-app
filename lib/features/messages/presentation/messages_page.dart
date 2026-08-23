import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/models/robot_data.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 消息页 — 匹配 Pixso 5:2598
///
/// 状态栏(76px) + 操作条(搜索/导出) + 消息卡片列表(49px)
/// 数据源: 机器人 `service_message` 推送（对齐 web-debug robotStore.messages）
class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});
  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  String _keyword = '';
  final _searchC = TextEditingController();

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final all = ref.read(robotDataProvider.notifier).messages;
    var messages = all;
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      messages = messages
          .where(
            (m) =>
                m.subject.toLowerCase().contains(kw) ||
                m.body.toLowerCase().contains(kw) ||
                m.source.toLowerCase().contains(kw),
          )
          .toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '消息'),
            // 操作条 (Pixso 5:2600, 40px)
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  children: [
                    // 搜索输入框 (Pixso 5:2602)
                    Expanded(
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: const Color(0xFFD8D8D8),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.search,
                              size: 16,
                              color: Color(0xFF8E8E93),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _searchC,
                                onChanged: (v) => setState(() => _keyword = v),
                                decoration: const InputDecoration(
                                  hintText: '搜索消息',
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF8E8E93),
                                  ),
                                  isDense: true,
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 导出 (Pixso 5:2608)
                    InkWell(
                      onTap: () => _exportMessages(messages),
                      borderRadius: BorderRadius.circular(15),
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: const Color(0xFFD8D8D8),
                            width: 0.5,
                          ),
                        ),
                        child: const Text(
                          '导出',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF3D3D3D),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 消息列表
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  // 消息由机器人推送产生，无拉取协议；下拉仅触发重建
                  setState(() {});
                },
                child: messages.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(40),
                        children: const [
                          Icon(
                            Icons.mail_outline,
                            size: 40,
                            color: Color(0xFFC7C7CC),
                          ),
                          SizedBox(height: 12),
                          Text(
                            '暂无消息\n机器人服务通知将在此显示',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
                        itemCount: messages.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _MessageCard(
                            msg: messages[i],
                            onTap: () => _openDetail(messages[i]),
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开消息详情 — 对齐 web-debug openDetail：点击即标记已读
  void _openDetail(RobotMessage msg) {
    ref.read(robotDataProvider.notifier).markMessageRead(msg.id, true);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (ctx) => _MessageDetailSheet(msg: msg),
    );
  }

  /// 导出消息 — 保存 txt 到应用文档目录 → 提示成功 → 系统打开方式选择器
  Future<void> _exportMessages(List<RobotMessage> messages) async {
    if (messages.isEmpty) {
      AppToast.show('暂无可导出的消息');
      return;
    }
    final sb = StringBuffer();
    for (final m in messages) {
      sb
        ..write('${_fmtTime(m.time)} [${m.source}] ${m.subject}')
        ..writeln()
        ..writeln(m.body.isEmpty ? m.summary : m.body)
        ..writeln('---');
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/wo-bot-messages-${DateTime.now().toIso8601String().split('T').first}.txt',
      );
      await file.writeAsString(sb.toString());
      if (!mounted) return;
      // 提示导出成功
      AppToast.show('导出成功：${file.path}', type: AppToastType.success);
      // 弹出系统"打开方式"选择器
      final result = await OpenFilex.open(file.path, type: 'text/plain');
      debugPrint('[Messages] open result: ${result.type} ${result.message}');
    } catch (e) {
      debugPrint('[Messages] 导出失败: $e');
      if (mounted) {
        AppToast.show('导出失败：$e', type: AppToastType.error);
      }
    }
  }

  /// 时间格式 — 对齐 web-debug fmtTime (MM/DD HH:mm)
  static String _fmtTime(DateTime t) {
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final h = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    return '$m/$d $h:$min';
  }
}

/// 消息卡片 — 匹配 Pixso 5:2664 (398×49: 未读点 + 标题 + 时间)
class _MessageCard extends StatelessWidget {
  final RobotMessage msg;
  final VoidCallback onTap;
  const _MessageCard({required this.msg, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dotColor = msg.read
        ? const Color(0xFFC7C7CC)
        : msg.severity == 'error'
        ? const Color(0xFFFF3B30)
        : msg.severity == 'warning'
        ? const Color(0xFFFF9500)
        : const Color(0xFF0256FF);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 49,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
          ),
          child: Row(
            children: [
              // 类型标记圆点（未读高亮，error/warning 着色）
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                ),
              ),
              const SizedBox(width: 10),
              // 标题
              Expanded(
                child: Text(
                  msg.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF3D3D3D),
                  ),
                ),
              ),
              // 时间
              Text(
                _MessagesPageState._fmtTime(msg.time),
                style: const TextStyle(fontSize: 12, color: Color(0xFF898989)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 消息详情底部弹层 — 对齐 web-debug MessageDetailDialog
class _MessageDetailSheet extends ConsumerWidget {
  final RobotMessage msg;
  const _MessageDetailSheet({required this.msg});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.subject,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_MessagesPageState._fmtTime(msg.time)} · ${msg.source} · '
              '${msg.read ? '已读' : '未读'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  msg.body.isEmpty ? msg.summary : msg.body,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: Color(0xFF3D3D3D),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    ref
                        .read(robotDataProvider.notifier)
                        .markMessageRead(msg.id, false);
                    Navigator.of(context).pop();
                  },
                  child: const Text(
                    '标记未读',
                    style: TextStyle(fontSize: 13, color: Color(0xFF3D3D3D)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0256FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: const Text('关闭', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
