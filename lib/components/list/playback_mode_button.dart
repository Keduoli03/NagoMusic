import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

class PlaybackModeButton extends StatelessWidget {
  final bool isSequential;
  final int count;
  final VoidCallback onPlay;
  final VoidCallback? onDoubleTap;
  final VoidCallback onToggleMode;

  const PlaybackModeButton({
    super.key,
    required this.isSequential,
    required this.count,
    required this.onPlay,
    this.onDoubleTap,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      onDoubleTap: onDoubleTap,
      onLongPress: onToggleMode,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isSequential ? AppIcons.playlist : AppIcons.shuffle, size: 20),
            const SizedBox(width: 4),
            Text(
              '${isSequential ? '顺序播放' : '随机播放'} ($count)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
