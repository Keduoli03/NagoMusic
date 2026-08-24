import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'media_list_action_button.dart';

class MultiSelectToggleButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;

  const MultiSelectToggleButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 开关态以前是靠 checklist / checklist_rtl 两个方向相反的图标区分，很难看出
    // 哪个是「开」。现在图标不变，用强调色淡底表示已开启。
    return MediaListActionButton(
      icon: AppIcons.checks,
      tooltip: enabled ? '退出多选' : '多选',
      active: enabled,
      onTap: onTap,
    );
  }
}
