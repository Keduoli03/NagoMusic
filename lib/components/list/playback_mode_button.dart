import 'package:flutter/material.dart';

class PlaybackModeButton extends StatelessWidget {
  final bool isSequential;
  final int count;
  final VoidCallback onPlay;
  final VoidCallback onToggleMode;

  const PlaybackModeButton({
    super.key,
    required this.isSequential,
    required this.count,
    required this.onPlay,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      onLongPress: onToggleMode,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        children: [
          Icon(isSequential ? Icons.playlist_play : Icons.shuffle, size: 20),
          const SizedBox(width: 4),
          Text('${isSequential ? '顺序播放' : '随机播放'} ($count)'),
        ],
      ),
    );
  }
}
