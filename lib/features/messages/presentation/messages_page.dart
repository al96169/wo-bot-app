import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 消息页 — 匹配 Pixso 5:2598
///
/// 状态栏(76px) + 操作条(搜索/导出) + 消息卡片列表(49px)
/// 数据源: 机器人消息（当前为 mock，后续对接协议）
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
    var messages = _mockMessages;
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      messages = messages
          .where((m) => m.title.toLowerCase().contains(kw) || m.preview.toLowerCase().contains(kw))
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
                          border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 16, color: Color(0xFF8E8E93)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextField(
                                controller: _searchC,
                                onChanged: (v) => setState(() => _keyword = v),
                                decoration: const InputDecoration(
                                  hintText: '搜索消息',
                                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
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
                      onTap: () {},
                      borderRadius: BorderRadius.circular(15),
                      child: Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: const Color(0xFFD8D8D8), width: 0.5),
                        ),
                        child: const Text('导出', style: TextStyle(fontSize: 13, color: Color(0xFF3D3D3D))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 消息列表
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {},
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(15, 0, 15, 20),
                  itemCount: messages.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _MessageCard(msg: messages[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息卡片 — 匹配 Pixso 5:2664 (398×49: 类型 + 标题 + 时间)
class _MessageCard extends StatelessWidget {
  final _MockMessage msg;
  const _MessageCard({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 49,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Row(
        children: [
          // 类型标记圆点
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: msg.read ? const Color(0xFFC7C7CC) : const Color(0xFF0256FF),
            ),
          ),
          const SizedBox(width: 10),
          // 标题
          Expanded(
            child: Text(
              msg.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFF3D3D3D)),
            ),
          ),
          // 时间
          Text(
            msg.time,
            style: const TextStyle(fontSize: 12, color: Color(0xFF898989)),
          ),
        ],
      ),
    );
  }
}

class _MockMessage {
  final String type;
  final String time;
  final String title;
  final String preview;
  final bool read;
  const _MockMessage(this.type, this.time, this.title, this.preview, {this.read = false});
}

const _mockMessages = [
  _MockMessage('设备消息', '2024/8/16 14:00', '设备固件更新通知', '您的「我的小蜗」固件已更新至 v2.1.0，新增云台自动校准功能'),
  _MockMessage('系统通知', '2024/8/15 09:30', 'Wo-Bot 服务协议更新', '我们更新了服务协议和隐私政策，请查阅最新版本'),
  _MockMessage('设备消息', '2024/8/14 18:00', '设备离线提醒', '「我的小蜗」已离线超过 30 分钟，请检查设备连接', read: true),
  _MockMessage('设备消息', '2024/8/13 10:00', '低电量提醒', '「我的小蜗」电量低于 20%，请及时充电'),
  _MockMessage('系统通知', '2024/8/12 16:30', '新版本可用', 'v2.0.0 已发布，支持舞蹈与音乐功能', read: true),
];
