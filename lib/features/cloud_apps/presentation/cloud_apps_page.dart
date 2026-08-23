import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/account_service.dart';
import '../../../core/utils/app_toast.dart';
import '../../../shared/widgets/feature_status_bar.dart';

/// 授权应用管理页 — 对齐 web-debug CloudAppsView
///
/// 列出当前账号授权的第三方应用，支持撤销授权
class CloudAppsPage extends ConsumerStatefulWidget {
  const CloudAppsPage({super.key});
  @override
  ConsumerState<CloudAppsPage> createState() => _CloudAppsPageState();
}

class _CloudAppsPageState extends ConsumerState<CloudAppsPage> {
  List<Map<String, dynamic>> _apps = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final apps = await AccountService.instance.getAuthorizedApps();
    if (mounted) {
      setState(() {
        _apps = apps;
        _loading = false;
      });
    }
  }

  void _revoke(Map<String, dynamic> app) {
    final grantId = (app['grantId'] ?? app['id'] ?? app['grant_id']).toString();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤销授权'),
        content: Text('确定撤销「${app['appName'] ?? app['name'] ?? grantId}」的访问权限吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF453A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    ).then((ok) async {
      if (ok == true) {
        final success = await AccountService.instance.revokeApp(grantId);
        if (!mounted) return;
        AppToast.show(
          success ? '已撤销授权' : '撤销失败',
          type: success ? AppToastType.success : AppToastType.error,
        );
        if (success) _load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Column(
          children: [
            const FeatureStatusBar(title: '授权应用'),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _apps.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(40),
                      children: const [
                        Icon(Icons.apps, size: 40, color: Color(0xFFC7C7CC)),
                        SizedBox(height: 12),
                        Text(
                          '暂无授权应用\n登录后在此查看授权给第三方应用的服务',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(15, 10, 15, 20),
                        itemCount: _apps.length,
                        itemBuilder: (context, i) {
                          final app = _apps[i];
                          final name = '${app['appName'] ?? app['name'] ?? '应用'}';
                          final grantId =
                              '${app['grantId'] ?? app['id'] ?? app['grant_id'] ?? ''}';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: const Color(0xFFEEEEEE),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3F0FA),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Color(0xFF6750A4),
                                    ),
                                  ),
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
                                        'Grant ID: $grantId',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF8E8E93),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => _revoke(app),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFF453A),
                                    side: const BorderSide(color: Color(0xFFFF453A)),
                                    minimumSize: const Size(0, 32),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('撤销', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
