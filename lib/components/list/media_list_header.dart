import 'package:flutter/material.dart';

import 'multi_select_toggle_button.dart';
import 'playback_mode_button.dart';
import 'select_all_button.dart';
import 'sort_action_button.dart';

class MediaListHeader extends StatelessWidget {
  final bool multiSelect;
  final bool isAllSelected;
  final int selectedCount;
  final int totalCount;
  final bool isSequentialPlay;
  final VoidCallback onToggleSelectAll;
  final VoidCallback onPlay;
  final VoidCallback onTogglePlayMode;
  final VoidCallback onSort;
  final VoidCallback onToggleMultiSelect;

  const MediaListHeader({
    super.key,
    required this.multiSelect,
    required this.isAllSelected,
    required this.selectedCount,
    required this.totalCount,
    required this.isSequentialPlay,
    required this.onToggleSelectAll,
    required this.onPlay,
    required this.onTogglePlayMode,
    required this.onSort,
    required this.onToggleMultiSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      child: Row(
        children: [
          multiSelect
              ? SelectAllButton(
                  isAllSelected: isAllSelected,
                  selectedCount: selectedCount,
                  totalCount: totalCount,
                  onTap: onToggleSelectAll,
                )
              : PlaybackModeButton(
                  isSequential: isSequentialPlay,
                  count: totalCount,
                  onPlay: onPlay,
                  onToggleMode: onTogglePlayMode,
                ),
          const Spacer(),
          SortActionButton(onTap: onSort),
          MultiSelectToggleButton(
            enabled: multiSelect,
            onTap: onToggleMultiSelect,
          ),
        ],
      ),
    );
  }
}
