import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_radii.dart';

/// 「标签在左、灰底输入框在右」的表单行。
///
/// 和 [AppTextFieldTile]（浮动 label 的无边框输入行）是两种方言：那个用于设置页
/// 里零散的一两个输入框，这个用于**连接配置这类字段成组、需要横向对齐**的表单
/// —— 标签固定宽度、右侧是填充块，一列扫下来标签和输入框各自成线。
class AppFormFieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool enabled;
  final bool obscureText;

  /// 标签后面缀一个红色 `*`。只是视觉提示，校验仍在提交时做。
  final bool required;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  /// 输入框内右侧的附加控件（显示密码、清空等）。
  final Widget? suffix;

  final ValueChanged<String>? onChanged;

  /// 标签列宽。同一组行必须用同一个值才对得齐，默认值见 [labelWidth]。
  static const double labelWidth = 64;

  const AppFormFieldRow({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.enabled = true,
    this.obscureText = false,
    this.required = false,
    this.keyboardType,
    this.textInputAction,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _FormRowShell(
      label: label,
      required: required,
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        autocorrect: false,
        enableSuggestions: !obscureText,
        style: TextStyle(fontSize: 15, color: c.text),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.mediaBg,
          hintText: hintText,
          hintStyle: TextStyle(fontSize: 15, color: c.muted),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: _border,
          enabledBorder: _border,
          focusedBorder: _border,
          disabledBorder: _border,
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
        ),
      ),
    );
  }

  static const OutlineInputBorder _border = OutlineInputBorder(
    borderRadius: AppRadii.rPanel,
    borderSide: BorderSide.none,
  );
}

/// 和 [AppFormFieldRow] 同一套排版的只读行：右侧是当前值 + `›`，点开去选。
class AppFormValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool enabled;
  final bool required;
  final VoidCallback? onTap;

  const AppFormValueRow({
    super.key,
    required this.label,
    required this.value,
    this.enabled = true,
    this.required = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _FormRowShell(
      label: label,
      required: required,
      child: Material(
        color: c.mediaBg,
        borderRadius: AppRadii.rPanel,
        child: InkWell(
          borderRadius: AppRadii.rPanel,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: enabled ? c.text : c.muted,
                    ),
                  ),
                ),
                Icon(AppIcons.chevronRight, size: 18, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormRowShell extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;

  const _FormRowShell({
    required this.label,
    required this.required,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: AppFormFieldRow.labelWidth,
            child: Text.rich(
              TextSpan(
                text: label,
                children: required
                    ? [
                        TextSpan(
                          text: ' *',
                          style: TextStyle(color: c.danger),
                        ),
                      ]
                    : null,
              ),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}
