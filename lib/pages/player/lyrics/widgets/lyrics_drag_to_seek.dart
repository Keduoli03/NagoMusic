import 'package:flutter/material.dart';

import '../../../../app/services/lyrics/lyrics_service.dart';
import '../../../../app/services/player_service.dart';

class LyricsDragToSeek extends StatefulWidget {
  final bool enabled;
  final PlayerService player;
  final LyricsService lyrics;
  final Widget child;

  const LyricsDragToSeek({
    super.key,
    required this.enabled,
    required this.player,
    required this.lyrics,
    required this.child,
  });

  @override
  State<LyricsDragToSeek> createState() => _LyricsDragToSeekState();
}

class _LyricsDragToSeekState extends State<LyricsDragToSeek> {
  @override
  void initState() {
    super.initState();
    widget.lyrics.controller.isSelectingNotifier.addListener(_onSelectingChanged);
  }

  @override
  void didUpdateWidget(covariant LyricsDragToSeek oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics == widget.lyrics) return;
    oldWidget.lyrics.controller.isSelectingNotifier
        .removeListener(_onSelectingChanged);
    widget.lyrics.controller.isSelectingNotifier.addListener(_onSelectingChanged);
  }

  @override
  void dispose() {
    widget.lyrics.controller.isSelectingNotifier.removeListener(_onSelectingChanged);
    super.dispose();
  }

  void _onSelectingChanged() {
    final selecting = widget.lyrics.controller.isSelectingNotifier.value;

    if (!widget.enabled) {
      if (selecting) {
        widget.lyrics.controller.stopSelection();
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
