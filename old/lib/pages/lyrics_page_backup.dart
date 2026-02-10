import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../viewmodels/player_viewmodel.dart';

class LyricsPageBackup extends StatefulWidget {
  const LyricsPageBackup({super.key});
  @override
  State<LyricsPageBackup> createState() => _LyricsPageBackupState();
}

class _LyricsPageBackupState extends State<LyricsPageBackup> {
  final ScrollController _controller = ScrollController();
  int _lastIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = PlayerViewModel();
      watchSignal(context, vm.playbackTick);
      watchSignal(context, vm.queueTick);
      watchSignal(context, vm.lyricsTick);
      watchSignal(context, vm.uiTick);
      final artwork = vm.artwork;
      final lines = vm.lyricsLines;
      final current = vm.currentLyricIndex;
      String lineAt(int index) {
        if (lines.isEmpty) return '';
        if (index < 0) return '';
        if (index >= lines.length) return '';
        return lines[index].text;
      }
      final hasLyrics = lines.isNotEmpty;
      final baseIndex = current >= 0 ? current : 0;
      final prevText = lineAt(baseIndex - 1);
      final currentText = lineAt(baseIndex);
      final nextText = lineAt(baseIndex + 1);
      final routeAnimation = ModalRoute.of(context)?.animation;
      final anim = routeAnimation == null
          ? const AlwaysStoppedAnimation(1.0)
          : CurvedAnimation(parent: routeAnimation, curve: Curves.easeOutCubic);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current != -1 && current != _lastIndex && _controller.hasClients) {
          _lastIndex = current;
          const itemExtent = 44.0;
          final viewport = MediaQuery.of(context).size.height;
          var target = current * itemExtent - viewport * 0.3;
          if (target < 0) target = 0;
          _controller.animateTo(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.grey[900],
                child: artwork != null
                    ? Image.memory(
                        artwork,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Container(color: Colors.grey[850]),
              ),
            ),
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                vm.title ?? '未知歌曲',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                vm.artist ?? '未知歌手',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.sensors, color: Colors.white),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: anim,
                      builder: (context, child) {
                        final width = MediaQuery.of(context).size.width;
                        final leftOffset = -width * 0.35 * anim.value;
                        final rightOffset = width * (1 - anim.value);
                        final leftOpacity = 1 - 0.7 * anim.value;
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: Transform.translate(
                                offset: Offset(leftOffset, 0),
                                child: Opacity(
                                  opacity: leftOpacity,
                                  child: Column(
                                    children: [
                                      const Spacer(flex: 2),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 32),
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: 0.4),
                                                  blurRadius: 20,
                                                  offset: const Offset(0, 10),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: artwork != null
                                                  ? Image.memory(artwork, fit: BoxFit.cover)
                                                  : Container(
                                                      color: Colors.grey[800],
                                                      child: const Icon(
                                                        Icons.music_note,
                                                        size: 80,
                                                        color: Colors.white24,
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Spacer(flex: 1),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 32),
                                        child: hasLyrics
                                            ? SizedBox(
                                                height: 110,
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      prevText.isEmpty ? ' ' : prevText,
                                                      style: TextStyle(
                                                        color: Colors.white.withValues(alpha: 0.5),
                                                        fontSize: 14,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      currentText.isEmpty ? ' ' : currentText,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      nextText.isEmpty ? ' ' : nextText,
                                                      style: TextStyle(
                                                        color: Colors.white.withValues(alpha: 0.5),
                                                        fontSize: 14,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : Column(
                                                children: [
                                                  Text(
                                                    '暂无歌词',
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.9),
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    '纯音乐或未匹配到歌词',
                                                    style: TextStyle(
                                                      color: Colors.white.withValues(alpha: 0.5),
                                                      fontSize: 14,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                      ),
                                      const Spacer(flex: 2),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Transform.translate(
                                offset: Offset(rightOffset, 0),
                                child: Opacity(
                                  opacity: anim.value,
                                  child: lines.isEmpty
                                      ? Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '暂无歌词',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.7),
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '纯音乐或未匹配到歌词',
                                                style: TextStyle(
                                                  color: Colors.white.withValues(alpha: 0.4),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ListView.builder(
                                          controller: _controller,
                                          itemExtent: 44,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                          itemCount: lines.length,
                                          itemBuilder: (context, index) {
                                            final isActive = index == current;
                                            final color = isActive
                                                ? Colors.white
                                                : Colors.white.withValues(alpha: 0.5);
                                            final weight =
                                                isActive ? FontWeight.w700 : FontWeight.w400;
                                            final size = isActive ? 18.0 : 16.0;
                                            return Align(
                                              alignment: Alignment.center,
                                              child: Text(
                                                lines[index].text,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: color,
                                                  fontSize: size,
                                                  fontWeight: weight,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },);
  }
}
