import 'package:flutter/material.dart';

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Icon(isAllSelected ? Icons.check_circle : Icons.circle_outlined, size: 20),
          const SizedBox(width: 4),
          Text('${isAllSelected ? '取消全选' : '全选'} ($selectedCount/$totalCount)'),
        ],
      ),
    );
  }
}
