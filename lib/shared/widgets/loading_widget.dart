import 'package:flutter/material.dart';

/// 加载指示器
class AppLoadingWidget extends StatelessWidget {
  final String? message;
  final double size;

  const AppLoadingWidget({super.key, this.message, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(strokeWidth: 3),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 全屏加载遮罩
class AppFullScreenLoading extends StatelessWidget {
  final String? message;

  const AppFullScreenLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: AppLoadingWidget(message: message ?? '处理中...'),
    );
  }
}
