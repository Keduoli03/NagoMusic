import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// 紧凑搜索输入框，做成能直接塞进 [AppTopBar] 的 `titleWidget`。
///
/// 结构照搬 `flutter_template_local` 的 `SearchAppBar._SearchField`：
/// **固定高度的 Container + Row + 无边框 TextField**，而不是给 TextField 配一套
/// `InputDecoration`。原因是 `InputDecoration` 的 `prefixIcon` / `suffixIcon` 会
/// 按 48x48 的触摸目标参与布局，图标和文字各自按自己的规则垂直居中，在矮框里
/// 必然对不齐——顶栏里的返回箭头和框内的放大镜会差出几个像素。
/// 自己搭 Row 之后 `crossAxisAlignment` 默认 center，图标、文字、清空按钮和外面
/// 的返回箭头就都落在同一条中线上了。
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '搜索',
    this.autofocus = false,
    this.height = 38,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;

  /// 输入框净高。顶栏 56 高，留 38 上下各余 9。
  final double height;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 点清空按钮时额外要做的事（清空 controller 由本组件负责）。
  final VoidCallback? onClear;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // 只为了刷新清空按钮的显隐。
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    widget.focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final hasText = widget.controller.text.isNotEmpty;

    return Container(
      height: widget.height,
      // 自带右边距，免得每个调用方都要在外面包一层 Padding 给 actions 让位。
      margin: const EdgeInsets.only(right: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(color: c.mediaBg, borderRadius: AppRadii.rPill),
      child: Row(
        children: [
          Icon(AppIcons.search, size: 18, color: c.muted),
          AppSpacing.wGapSm,
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: AppTypography.body.on(c.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: AppTypography.body.on(c.muted),
              ),
            ),
          ),
          if (hasText)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clear,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Icon(AppIcons.close, size: 16, color: c.muted),
              ),
            ),
        ],
      ),
    );
  }
}
