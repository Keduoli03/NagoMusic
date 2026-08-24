import 'package:flutter/material.dart';

import '../../components/index.dart';

/// 以底部弹层展示歌单命名/重命名对话框；新建、重命名、以及「添加到歌单」里
/// 顺手新建歌单都会用到，因此提成公共入口而不是各处各写一份。
Future<void> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String confirmText,
  required String? fallbackName,
  required Future<void> Function(String name) onSubmit,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: PlaylistNameDialog(
          title: title,
          initial: initial,
          confirmText: confirmText,
          fallbackName: fallbackName,
          onSubmit: onSubmit,
        ),
      );
    },
  );
}

class PlaylistNameDialog extends StatefulWidget {
  final String title;
  final String initial;
  final String confirmText;
  final String? fallbackName;
  final Future<void> Function(String name) onSubmit;

  const PlaylistNameDialog({
    super.key,
    required this.title,
    required this.initial,
    required this.confirmText,
    required this.fallbackName,
    required this.onSubmit,
  });

  @override
  State<PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<PlaylistNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty && widget.fallbackName == null) return;
    final name = trimmed.isEmpty ? widget.fallbackName! : trimmed;
    await widget.onSubmit(name);
  }

  Future<void> _submitAndClose() async {
    await _submit();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppSheetPanel(
      title: widget.title,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '歌单名称',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _submitAndClose(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: isDark
                          ? Colors.white.withAlpha(20)
                          : Colors.grey.withAlpha(26),
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _submitAndClose,
                    child: Text(
                      widget.confirmText,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
