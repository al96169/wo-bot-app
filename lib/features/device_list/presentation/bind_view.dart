import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/connection_manager.dart';
import '../../../core/network/bind_service.dart';
import '../../../core/theme/app_colors.dart';

/// 绑定认证页面 — 完全匹配 web-debug BindView
class BindView extends ConsumerStatefulWidget {
  final VoidCallback? onBound;
  final VoidCallback? onCancel;
  const BindView({super.key, this.onBound, this.onCancel});

  @override
  ConsumerState<BindView> createState() => _BindViewState();
}

class _BindViewState extends ConsumerState<BindView> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _shareCodeController = TextEditingController();
  BindService get _bind => BindService.instance;

  @override
  void initState() {
    super.initState();
    _bind
      ..onStepChanged = (step) {
        if (mounted) setState(() {});
        if (step == BindStep.success && mounted) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              widget.onBound?.call();
              Navigator.of(context).pop();
            }
          });
        }
      }
      ..onError = (error) {
        if (mounted) setState(() {});
      };
  }
  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _shareCodeController.dispose();
    _bind.onStepChanged = null; // 防止 resetToSelect 触发死 widget 的 setState
    _bind.onError = null;
    _bind.resetToSelect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (_bind.step) {
      case BindStep.select: return _buildMethodSelect();
      case BindStep.display: return _buildCodeInput('屏幕显示配对数字', 6, '查看机器人屏幕上的数字并输入');
      case BindStep.tts: return _buildCodeInput('语音播报配对数字', 4, '听取机器人播报的数字并输入');
      case BindStep.gimbal: return _buildGimbalInput();
      case BindStep.shareCode: return _buildShareCodeInput();
      case BindStep.password: return _buildPasswordInput();
      case BindStep.verifying: return _buildVerifying();
      case BindStep.success: return _buildSuccess();
      case BindStep.failed: return _buildFailed();
    }
  }

  // ============== 方式选择 ==============
  Widget _buildMethodSelect() {
    final methods = _bind.methods;
    if (methods.isEmpty) {
      return const Center(child: Text('没有可用的认证方式'));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('选择认证方式', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ...methods.map((m) => _MethodCard(
          icon: m.icon,
          title: m.label,
          subtitle: m.description,
          onTap: () => _onSelectMethod(m),
        )),
        if (_bind.errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_bind.errorMessage, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
      ],
    );
  }

  void _onSelectMethod(BindMethod method) {
    _bind.selectMethod(method);
    if (method == BindMethod.shareCode) return; // share_code doesn't need bind_request

    // 对齐 web-debug selectMethod：发送 bind_request 后 isSubmitting 保持 false，
    // 确认按钮保持可用，等待用户输入验证码后再提交（提交时才置 true）
    final msg = _bind.buildBindRequest(method);
    ref.read(connectionManagerProvider.notifier).sendRaw(msg);
    setState(() {});
  }

  // ============== 数字验证码输入 ==============
  Widget _buildCodeInput(String title, int maxLength, String hint) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(hint, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: maxLength,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, letterSpacing: 8),
            decoration: const InputDecoration(
              counterText: '',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => _bind.resetToSelect(),
              child: const Text('返回'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _bind.isSubmitting ? null : _submitCode,
              child: _bind.isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('确认'),
            ),
          ],
        ),
        if (_bind.errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_bind.errorMessage, style: const TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }

  void _submitCode() {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    _bind.setVerifying();
    final msg = _bind.buildBindVerify(code);
    ref.read(connectionManagerProvider.notifier).sendRaw(msg);
  }

  // ============== 云台方向输入 ==============
  Widget _buildGimbalInput() {
    final inputs = _bind.gimbalInputs;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text('云台动作认证', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('观察云台转动方向，依次点击对应方向', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        // 已输入的方向槽位
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(BindService.gimbalSequenceLength, (i) {
            final filled = i < inputs.length;
            return Container(
              width: 48, height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(color: filled ? AppColors.primary : AppColors.divider, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: filled ? AppColors.primary.withValues(alpha: 0.15) : null,
              ),
              child: filled
                  ? Center(child: Text(_dirIcon(inputs[i]), style: const TextStyle(fontSize: 20)))
                  : null,
            );
          }),
        ),
        const SizedBox(height: 24),
        // 方向按钮
        Column(
          children: [
            _DirButton('up', '↑', () => _addGimbalDir('up')),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DirButton('left', '←', () => _addGimbalDir('left')),
                const SizedBox(width: 24),
                _DirButton('right', '→', () => _addGimbalDir('right')),
              ],
            ),
            const SizedBox(height: 8),
            _DirButton('down', '↓', () => _addGimbalDir('down')),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () {
                if (_bind.gimbalInputs.isNotEmpty) {
                  setState(() => _bind.gimbalInputs.removeLast());
                }
              },
              child: const Text('删除'),
            ),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () => _bind.resetToSelect(),
              child: const Text('返回'),
            ),
          ],
        ),
        if (_bind.errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_bind.errorMessage, style: const TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }

  void _addGimbalDir(String dir) {
    if (_bind.gimbalInputs.length >= BindService.gimbalSequenceLength) return;
    setState(() => _bind.gimbalInputs.add(dir));
    if (_bind.gimbalInputs.length == BindService.gimbalSequenceLength) {
      // 自动提交
      _bind.setVerifying();
      final msg = _bind.buildBindGimbalVerify();
      ref.read(connectionManagerProvider.notifier).sendRaw(msg);
    }
  }

  String _dirIcon(String dir) {
    switch (dir) {
      case 'up': return '↑';
      case 'down': return '↓';
      case 'left': return '←';
      case 'right': return '→';
      default: return '?';
    }
  }

  // ============== 分享码输入 ==============
  Widget _buildShareCodeInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Text('输入绑定码', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('输入从其他设备获取的 6 位分享码', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _shareCodeController,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, letterSpacing: 8),
            decoration: const InputDecoration(counterText: '', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => _bind.resetToSelect(),
              child: const Text('返回'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _bind.isSubmitting ? null : () {
                final code = _shareCodeController.text.trim();
                if (code.isEmpty) return;
                _bind.setVerifying();
                final msg = _bind.buildBindShareUse(code);
                ref.read(connectionManagerProvider.notifier).sendRaw(msg);
              },
              child: _bind.isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('绑定'),
            ),
          ],
        ),
      ],
    );
  }

  // ============== 密码输入 ==============
  Widget _buildPasswordInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('密码绑定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: '输入机器人密码',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton(
              onPressed: () => _bind.resetToSelect(),
              child: const Text('返回'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _bind.isSubmitting ? null : () {
                final pwd = _passwordController.text.trim();
                if (pwd.isEmpty) return;
                _bind.setVerifying();
                final msg = _bind.buildBindPassword(pwd);
                ref.read(connectionManagerProvider.notifier).sendRaw(msg);
              },
              child: const Text('确认'),
            ),
          ],
        ),
        if (_bind.errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_bind.errorMessage, style: const TextStyle(color: AppColors.error)),
          ),
      ],
    );
  }

  Widget _buildSuccess() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 64),
          SizedBox(height: 16),
          Text('绑定成功！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildVerifying() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(height: 16),
          Text('正在验证...', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildFailed() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.error, color: AppColors.error, size: 48),
              SizedBox(height: 8),
              Text('绑定失败', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        if (_bind.errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(_bind.errorMessage, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
          ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _bind.resetToSelect(),
              child: const Text('重试'),
            ),
          ],
        ),
      ],
    );
  }
}

// ============== 辅助组件 ==============

class _MethodCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _MethodCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Text(icon, style: const TextStyle(fontSize: 28)),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _DirButton extends StatelessWidget {
  final String direction;
  final String label;
  final VoidCallback onTap;
  const _DirButton(this.direction, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64, height: 64,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 28)),
      ),
    );
  }
}
