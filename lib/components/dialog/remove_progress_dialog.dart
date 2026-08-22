import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// 批量移除歌曲的进度快照。
class RemoveProgress {
  final int processed;
  final int total;
  final bool isRemoving;

  const RemoveProgress({
    required this.processed,
    required this.total,
    required this.isRemoving,
  });

  static const RemoveProgress idle = RemoveProgress(
    processed: 0,
    total: 0,
    isRemoving: false,
  );
}

/// 驱动 [RemoveProgressDialog] 的控制器。
///
/// 页面在批量移除时调用 [start] / [update] / [finish]，
/// 并用 [showDialogOn] 打开可随时关闭、重新打开的进度对话框。
class RemoveProgressController extends ValueNotifier<RemoveProgress> {
  RemoveProgressController() : super(RemoveProgress.idle);

  bool get isRemoving => value.isRemoving;

  int get processed => value.processed;

  void start(int total) {
    value = RemoveProgress(processed: 0, total: total, isRemoving: true);
  }

  void update(int processed, [int? total]) {
    value = RemoveProgress(
      processed: processed,
      total: total ?? value.total,
      isRemoving: true,
    );
  }

  void finish(int processed) {
    value = RemoveProgress(
      processed: processed,
      total: value.total,
      isRemoving: false,
    );
  }

  void showDialogOn(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => RemoveProgressDialog(controller: this),
    );
  }
}

/// 展示批量移除进度的对话框，未完成时可隐藏、之后再次打开。
class RemoveProgressDialog extends StatelessWidget {
  final RemoveProgressController controller;

  const RemoveProgressDialog({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RemoveProgress>(
      valueListenable: controller,
      builder: (context, progress, child) {
        final finished = !progress.isRemoving;
        return AppDialog(
          title: finished ? '移除完成' : '正在移除...',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: progress.total > 0
                    ? progress.processed / progress.total
                    : 0,
              ),
              const SizedBox(height: 16),
              Text('已移除: ${progress.processed}'),
              const SizedBox(height: 4),
              Text('总计: ${progress.total}'),
            ],
          ),
          confirmText: finished ? '知道了' : '隐藏',
          showCancel: false,
          onConfirm: () {},
        );
      },
    );
  }
}
