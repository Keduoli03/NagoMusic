import 'package:flutter/material.dart';

import '../../../app/services/player_service.dart';
import 'lyric_view.dart';
import '../widgets/player_background.dart';
import '../widgets/player_top_bar.dart';

class LyricPage extends StatelessWidget {
  final PlayerService _player = PlayerService.instance;

  LyricPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          PlayerBackground(songSignal: _player.currentSongSignal),
          SafeArea(
            child: Column(
              children: [
                PlayerTopBar(onBack: () => Navigator.pop(context)),
                Expanded(
                  child: const PlayerLyricsView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
