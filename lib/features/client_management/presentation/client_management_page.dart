import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/bind_service.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/robot_data_store.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 客户端管理页 — 对齐 web-debug ClientManagementView
///
/// 绑定列表（移除）+ 分享码生成/倒计时 + 密码绑定配置
class ClientManagementPage extends ConsumerStatefulWidget {
  const ClientManagementPage({super.key});
  @override
  ConsumerState<ClientManagementPage> createState() => _ClientManagementPageState();
}

class _ClientManagementPageState extends ConsumerState<ClientManagementPage> {
  String _shareCode = '';
  int _shareCountdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // 接收分享码生成回调（BindService 单例，handleShareCreated 时触发）
    BindService.instance.onShareCreated = (code, expiresIn) {
      if (!mounted) return;
      setState(() {
        _shareCode = code;
        _shareCountdown = expiresIn;
      });
      _startCountdown();
    };
    // 首帧后拉取绑定列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(connectionManagerProvider.notifier).sendBindList();
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _shareCountdown--;
        if (_shareCountdown <= 0) {
          _shareCountdown = 0;
          _shareCode = '';
          _countdownTimer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _createShare() {
    setState(() {
      _shareCode = '';
      _shareCountdown = 0;
    });
    ref.read(connectionManagerProvider.notifier).sendBindShareCreate();
  }

  /// 处理 bind_share_created（在 build 里检查 store 变更不合适，用回调方式：
  /// ConnectionManager 已在 _bind.handleShareCreated 处理，此处轮询 store 无该字段，
  /// 改为：页面主动刷新列表时顺带检查。为简单可靠，分享码由 CM 回调存入临时字段。）
  void _removeBinding(String clientId) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认移除'),
        content: const Text('确定要移除此客户端的绑定吗？移除后该设备需要重新绑定才能使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        ref.read(connectionManagerProvider.notifier).sendBindRemove(clientId);
        AppToast.show('已发送移除指令');
      }
    });
  }

  Future<void> _showPasswordDialog() async {
    final pwdC = TextEditingController();
    final confirmC = TextEditingController();
    final enabled = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置绑定密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pwdC,
              obscureText: true,
              decoration: const InputDecoration(hintText: '新密码'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmC,
              obscureText: true,
              decoration: const InputDecoration(hintText: '确认新密码'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (pwdC.text.isEmpty || pwdC.text != confirmC.text) {
                AppToast.show('两次密码不一致或为空', type: AppToastType.error);
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (enabled == true && pwdC.text.isNotEmpty) {
      ref
          .read(connectionManagerProvider.notifier)
          .sendBindPasswordUpdate(password: pwdC.text);
      AppToast.show('密码已更新', type: AppToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(robotDataProvider);
    final store = ref.read(robotDataProvider.notifier);
    final bindings = store.bindings;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '客户端管理'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
                children: [
                  // 分享码卡片
                  _SectionCard(
                    title: '分享码绑定',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _shareCode.isNotEmpty && _shareCountdown > 0
                                  ? '分享码: $_shareCode'
                                  : '生成一次性分享码，其他人输入后绑定',
                              style: TextStyle(
                                fontSize: 14,
                                color: _shareCode.isNotEmpty
                                    ? const Color(0xFF0256FF)
                                    : const Color(0xFF3D3D3D),
                                fontWeight: _shareCode.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (_shareCode.isNotEmpty && _shareCountdown > 0) ...[
                            Text(
                              '${_shareCountdown}s',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18, color: Color(0xFF0256FF)),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _shareCode));
                                AppToast.show('分享码已复制', type: AppToastType.success);
                              },
                            ),
                          ],
                          FilledButton(
                            onPressed: _createShare,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0256FF),
                              minimumSize: const Size(0, 36),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            child: Text(_shareCode.isNotEmpty ? '重新生成' : '生成分享码'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 密码绑定
                  _SectionCard(
                    title: '密码绑定',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.lock_outline, size: 20, color: Color(0xFF0256FF)),
                        title: const Text('设置/修改绑定密码', style: TextStyle(fontSize: 14)),
                        trailing: const Icon(Icons.chevron_right, color: Color(0xFFC7C7CC)),
                        onTap: _showPasswordDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 绑定列表
                  _SectionCard(
                    title: '已绑定客户端（${bindings.length}）',
                    children: bindings.isEmpty
                        ? [
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: Text(
                                  '暂无已绑定的客户端',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                                ),
                              ),
                            ),
                          ]
                        : [
                            for (final b in bindings)
                              _BindingRow(
                                binding: b,
                                onRemove: () => _removeBinding('${b['clientId']}'),
                              ),
                          ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 绑定行
class _BindingRow extends StatelessWidget {
  final Map<String, dynamic> binding;
  final VoidCallback onRemove;
  const _BindingRow({required this.binding, required this.onRemove});

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '--';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.month}/${local.day} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final clientId = '${binding['clientId'] ?? ''}';
    final clientName = '${binding['clientName'] ?? clientId}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.smartphone, size: 18, color: Color(0xFF8E8E93)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF1C1C1E)),
                ),
                const SizedBox(height: 2),
                Text(
                  'ID: ${clientId.length > 16 ? '${clientId.substring(0, 16)}...' : clientId}'
                  ' · 绑定: ${_fmtTime(binding['boundAt'] as String?)}'
                  ' · 最近: ${_fmtTime(binding['lastSeen'] as String?)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF8E8E93)),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onRemove,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF453A),
              side: const BorderSide(color: Color(0xFFFF453A)),
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('移除', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3D3D3D)),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}
