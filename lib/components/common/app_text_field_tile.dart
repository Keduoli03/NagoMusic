import 'package:flutter/material.dart';

/// 设置类页面中的无边框文本输入行。
class AppTextFieldTile extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool enabled;
  final bool obscureText;
  final Widget? suffix;

  const AppTextFieldTile({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    required this.enabled,
    this.obscureText = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
