import 'package:flutter/material.dart';

import '../../app/services/haptic_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';

class SelectAllButton extends StatelessWidget {
  final bool isAllSelected;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onTap;

  const SelectAllButton({
    super.key,
    required this.isAllSelected,
    required this.selectedCount,
    required this.totalCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isAllSelected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 19,
                color: isAllSelected ? accent : c.muted,
              ),
              const SizedBox(width: 6),
              Text(
                '${isAllSelected ? '取消全选' : '全选'} ($selectedCount/$totalCount)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
