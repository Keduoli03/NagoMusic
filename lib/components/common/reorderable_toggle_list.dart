import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_icons.dart';
import 'app_switch.dart';
import 'setting_widgets.dart';

/// 一项可拖拽排序、可独立开关的设置行。
///
/// [enabled] 用 [ValueListenable] 而不是裸 bool：调用方的开关状态大多来自
/// `PrefEntry`，让这里直接订阅省掉一层 `ValueListenableBuilder` 的转发。
@immutable
class AppReorderableToggleItem {
  const AppReorderableToggleItem({
    required this.itemKey,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  /// 参与 [Key] 生成，必须在列表里唯一。
  final String itemKey;
  final String title;
  final String subtitle;
  final ValueListenable<bool> enabled;
  final ValueChanged<bool> onChanged;
}

/// 一组「可拖拽排序 + 每项独立开关」的设置行。
///
/// 从「播放器 → 底部操作栏」那份设置抽出来的通用组件：拖手柄 + 开关组合的这套
/// UI 不该只属于播放器的底部按钮，任何"一组可选功能，用户自己排序 + 勾选"的
/// 场景都能直接拿去用（比如以后要给首页卡片、侧边栏项做同样的自定义）。
class AppReorderableToggleList extends StatelessWidget {
  const AppReorderableToggleList({
    super.key,
    required this.items,
    required this.onReorder,
  });

  /// 已经按当前顺序排好的项。
  final List<AppReorderableToggleItem> items;

  /// 语义和 [ReorderableListView.onReorder] 完全一致，包括那个容易踩坑的
  /// 「newIndex 在原位置之后时要减一」——调用方自己处理，这个组件不代劳，
  /// 因为它不知道调用方的存储层是怎么应用这个新顺序的。
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: onReorder,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return AppSettingTile(
          key: ValueKey(item.itemKey),
          title: item.title,
          subtitle: item.subtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: item.enabled,
                builder: (context, enabled, _) {
                  return AppSwitch(value: enabled, onChanged: item.onChanged);
                },
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(AppIcons.dragHandle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
