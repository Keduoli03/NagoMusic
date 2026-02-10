import 'package:flutter/material.dart';

import '../dialog/app_dialog.dart';

class SourceScanDialog extends StatelessWidget {
  final int processed;
  final int added;
  final int total;
  final bool isScanning;
  final VoidCallback onCancel;
  final VoidCallback onHide;

  const SourceScanDialog({
    super.key,
    required this.processed,
    required this.added,
    required this.total,
    this.isScanning = true,
    required this.onCancel,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final isFinished = !isScanning;
    return AppDialog(
      title: isFinished ? '扫描完成' : '正在扫描...',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: total > 0 ? processed / total : 0,
          ),
          const SizedBox(height: 16),
          Text('已扫描: $processed'),
          const SizedBox(height: 4),
          Text('已添加: $added'),
        ],
      ),
      cancelText: '取消',
      confirmText: isFinished ? '知道了' : '隐藏',
      isDestructive: !isFinished,
      showCancel: !isFinished,
      onCancel: onCancel,
      onConfirm: onHide,
    );
  }
}
