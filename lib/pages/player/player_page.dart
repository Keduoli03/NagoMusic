import 'dart:io';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import 'lyrics/lyric_view.dart';
import 'widgets/player_background.dart';
import 'widgets/player_bottom_panel.dart';
import 'widgets/player_header.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final PlayerService _player = PlayerService.instance;
  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

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
                PlayerHeader(songSignal: _player.currentSongSignal),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    children: [
                      _PlayerView(
                        player: _player,
                        onTapLyrics: () => _pageController.animateToPage(
                          1,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                        ),
                      ),
                      const PlayerLyricsView(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerView extends StatelessWidget {
  final PlayerService player;
  final VoidCallback onTapLyrics;

  const _PlayerView({
    required this.player,
    required this.onTapLyrics,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 1),
        _PlayerArtwork(songSignal: player.currentSongSignal),
        const Spacer(flex: 1),
        PlayerBottomPanel(
          player: player,
          onTapLyrics: onTapLyrics,
        ),
      ],
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  final Signal<SongEntity?> songSignal;

  const _PlayerArtwork({required this.songSignal});

  @override
  Widget build(BuildContext context) {
    return Watch.builder(
      builder: (context) {
        final song = songSignal.value;
        final border = BorderRadius.circular(12);
        final cover = song?.localCoverPath;
        final hasCover = cover != null && cover.isNotEmpty;
        if (song == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: AspectRatio(
              aspectRatio: 1,
              child: _ArtworkShadowContainer(
                border: border,
                child: _ArtworkPlaceholder(border: border, label: ''),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: AspectRatio(
            aspectRatio: 1,
            child: _ArtworkShadowContainer(
              border: border,
              child: hasCover
                  ? ClipRRect(
                      borderRadius: border,
                      child: Image.file(
                        File(cover),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stack) {
                          return _ArtworkPlaceholder(
                            border: border,
                            label: song.title,
                          );
                        },
                      ),
                    )
                  : _ArtworkPlaceholder(
                      border: border,
                      label: song.title,
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _ArtworkShadowContainer extends StatelessWidget {
  final BorderRadius border;
  final Widget child;

  const _ArtworkShadowContainer({
    required this.border,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: border,
        child: child,
      ),
    );
  }
}

class _ArtworkPlaceholder extends StatelessWidget {
  final BorderRadius border;
  final String label;

  const _ArtworkPlaceholder({
    required this.border,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = label.trim().isEmpty ? '?' : label.trim().substring(0, 1);
    return Container(
      decoration: BoxDecoration(
        borderRadius: border,
        color: scheme.primary.withValues(alpha: 0.12),
      ),
      child: Center(
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
