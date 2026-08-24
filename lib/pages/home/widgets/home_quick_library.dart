import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import '../../../app/services/haptic_service.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radii.dart';
import '../home_models.dart';

class HomeQuickLibrary extends StatelessWidget {
  final VoidCallback onArtists;
  final VoidCallback onAlbums;
  final VoidCallback onFolders;

  const HomeQuickLibrary({
    super.key,
    required this.onArtists,
    required this.onAlbums,
    required this.onFolders,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 三个瓦片各带一个强调色，但颜色只落在图标底上 —— 瓦片本身是和卡片同族的
    // 白底方角，不再是三块撞色渐变。
    final buttons = <QuickLibraryData>[
      QuickLibraryData(
        label: '艺术家',
        icon: AppIcons.person,
        accent: scheme.primary,
        onTap: onArtists,
      ),
      QuickLibraryData(
        label: '专辑',
        icon: AppIcons.album,
        accent: scheme.tertiary,
        onTap: onAlbums,
      ),
      QuickLibraryData(
        label: '文件夹',
        icon: AppIcons.folder,
        accent: scheme.secondary,
        onTap: onFolders,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: QuickLibraryButton(data: buttons[i])),
        ],
      ],
    );
  }
}

class QuickLibraryButton extends StatelessWidget {
  final QuickLibraryData data;

  const QuickLibraryButton({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = BorderRadius.circular(AppRadii.card);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () {
          Haptics.tap();
          data.onTap();
        },
        child: Ink(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: radius,
            border: Border.all(color: c.line, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: data.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: Icon(data.icon, size: 17, color: data.accent),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
