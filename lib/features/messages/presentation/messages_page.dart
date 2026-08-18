import 'package:flutter/material.dart';

/// 消息页面 — 匹配 Pixso 1:4589
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            // ---- 顶栏 74px (Pixso 1:4590) ----
            // 返回按钮 + "消息" 标题
            SizedBox(
              height: 74,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                child: Row(
                  children: [
                    // 返回按钮 44×44 无背景 (Pixso 1:3206, 1:3211)
                    Tooltip(
                      message: '返回',
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(22),
                        child: Container(
                          width: 44, height: 44,
                          alignment: Alignment.center,
                          child: const Icon(Icons.arrow_back, size: 22, color: Color(0xFF6750A4)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 标题 "消息" bold 19.6 主色紫 (Pixso 1:4593)
                    const Text('消息', style: TextStyle(fontSize: 19.6, fontWeight: FontWeight.bold, color: Color(0xFF6750A4))),
                  ],
                ),
              ),
            ),
            // ---- 消息列表 (Pixso 1:4594) ----
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ListView.separated(
                  padding: const EdgeInsets.only(top: 10),
                  itemCount: _mockMessages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _MessageCard(msg: _mockMessages[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息卡片 408×100 — 匹配 Pixso Component_1_4647
class _MessageCard extends StatelessWidget {
  final _MockMessage msg;
  const _MessageCard({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: 类型 + 时间
          Row(children: [
            Text(msg.type, style: const TextStyle(fontSize: 12, color: Color(0xFF6750A4))),
            const Spacer(),
            Text(msg.time, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          ]),
          const SizedBox(height: 8),
          // Row 2: 标题
          Text(msg.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          // Row 3: 内容预览
          Text(msg.preview, style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
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
  const _MockMessage(this.type, this.time, this.title, this.preview);
}

const _mockMessages = [
  _MockMessage('设备消息', '2024/8/16 14:00', '设备固件更新通知', '您的「我的小蜗」固件已更新至 v2.1.0，新增云台自动校准功能'),
  _MockMessage('系统通知', '2024/8/15 09:30', 'Wo-Bot 服务协议更新', '我们更新了服务协议和隐私政策，请查阅最新版本'),
  _MockMessage('设备消息', '2024/8/14 18:00', '设备离线提醒', '「我的小蜗」已离线超过 30 分钟，请检查设备连接'),
];
