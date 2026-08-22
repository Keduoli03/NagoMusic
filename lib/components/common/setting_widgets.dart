import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import 'app_switch.dart';
import 'labeled_slider.dart';
import 'surface_card.dart';

/// 一组设置项：圆角卡片壳 + 行间 hairline 分隔线 + 可选组标题。
///
/// 样式对齐 flutter_template_local 的 `SettingsGroup`。与模板的唯一区别是这里
/// 画了描边 —— 模板是灰底白卡，靠底色差就能看出卡片；这里页面是纯白，白卡必须
/// 有描边才看得见。
class AppSettingSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 行与行之间是否画分隔线。分组列表默认画。
  final bool showDividers;

  const AppSettingSection({
    super.key,
    this.title,
    required this.children,
    this.margin,
    this.padding,
    this.showDividers = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final content = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && showDividers) {
        content.add(
          Divider(height: 0.5, thickness: 0.5, indent: 16, color: c.line),
        );
      }
      content.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
            child: Text(
              title!,
              style: TextStyle(
                fontSize: 12.5,
                color: c.muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          margin: margin,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Column(children: content),
          ),
        ),
      ],
    );
  }
}

/// 设置项行 —— 可选图标 + 标题 + 副标题 + 右侧内容，设置页最高频的重复布局。
///
/// 样式对齐 flutter_template_local 的 `SettingsRow`：整行最小高 54，标题 15/w500，
/// 副标题 12/muted。
class AppSettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 破坏性动作（清空数据、删除）：标题与图标转 [AppColors.danger]。
  final bool destructive;

  const AppSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final fg = destructive ? c.danger : c.text;

    final row = Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(
                size: 20,
                color: destructive ? c.danger : c.muted,
              ),
              child: leading!,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: c.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            IconTheme.merge(
              data: IconThemeData(size: 18, color: c.muted),
              child: trailing!,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// 右侧带 `›` 箭头、点击进入下一页的设置行。
///
/// 传入 [route] 时走命名路由，否则使用 [onTap]。
class AppSettingNavTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? route;
  final VoidCallback? onTap;

  /// 箭头左边的灰色值文字（如「跟随系统」「已开启」）。
  final String? value;

  const AppSettingNavTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.route,
    this.onTap,
    this.value,
  }) : assert(
         route != null || onTap != null,
         'Either route or onTap must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppSettingTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty)
            Text(value!, style: TextStyle(fontSize: 14, color: c.muted)),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      onTap: onTap ?? () => Navigator.pushNamed(context, route!),
    );
  }
}

/// 右侧是 [AppSwitch] 的设置行，点整行等于拨开关。
class AppSettingSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSettingSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      trailing: AppSwitch(value: value, onChanged: onChanged),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

class AppSettingCheckboxTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSettingCheckboxTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingTile(
      title: title,
      subtitle: subtitle,
      trailing: SizedBox(
        width: 32,
        child: Align(
          alignment: Alignment.center,
          child: Checkbox(
            value: value,
            onChanged: onChanged == null ? null : (v) => onChanged!(v ?? value),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

class AppSettingSlider extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueText;
  final String? description;
  final ValueChanged<double> onChanged;

  const AppSettingSlider({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.valueText,
    this.description,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LabeledSlider(
      title: title,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      valueText: valueText,
      description: description,
      onChanged: onChanged,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    );
  }
}
