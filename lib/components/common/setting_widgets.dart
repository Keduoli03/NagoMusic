import 'package:flutter/material.dart';

import 'labeled_slider.dart';

class AppSettingSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final bool showDividers;

  const AppSettingSection({
    super.key,
    this.title,
    required this.children,
    this.margin,
    this.padding,
    this.showDividers = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && showDividers) {
        content.add(const Divider(height: 1));
      }
      content.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        Card(
          margin: margin ?? EdgeInsets.zero,
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: Column(
              children: content,
            ),
          ),
        ),
      ],
    );
  }
}

class AppSettingTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AppSettingTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class AppSettingSwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const AppSettingSwitchTile({
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
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
      ),
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
        width: 40,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
    );
  }
}
