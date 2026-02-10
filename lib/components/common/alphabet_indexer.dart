import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';

class IndexUtils {
  static String leadingLetter(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '#';

    final firstChar = trimmed.substring(0, 1).toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(firstChar)) {
      return firstChar;
    }

    if (RegExp(r'[0-9]').hasMatch(firstChar)) {
      return '0';
    }

    final pinyin = PinyinHelper.getFirstWordPinyin(trimmed);
    if (pinyin.isNotEmpty) {
      final pinyinFirst = pinyin.substring(0, 1).toUpperCase();
      if (RegExp(r'[A-Z]').hasMatch(pinyinFirst)) {
        return pinyinFirst;
      }
    }

    return '#';
  }

  static List<String> defaultLetters() {
    final letters = <String>['0'];
    for (var i = 0; i < 26; i++) {
      letters.add(String.fromCharCode(65 + i));
    }
    letters.add('#');
    return letters;
  }

  static int? nearestIndexForLetter(
    String letter,
    List<String> letters,
    Map<String, int> indexMap,
  ) {
    final direct = indexMap[letter];
    if (direct != null) return direct;
    final start = letters.indexOf(letter);
    if (start == -1) return null;
    for (var i = start + 1; i < letters.length; i++) {
      final idx = indexMap[letters[i]];
      if (idx != null) return idx;
    }
    for (var i = start - 1; i >= 0; i--) {
      final idx = indexMap[letters[i]];
      if (idx != null) return idx;
    }
    return null;
  }
}

class AlphabetIndexBar extends StatelessWidget {
  final List<String> letters;
  final void Function(String letter) onLetterSelected;

  const AlphabetIndexBar({
    super.key,
    required this.letters,
    required this.onLetterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemHeight = letters.isEmpty
            ? constraints.maxHeight
            : (constraints.maxHeight / letters.length).clamp(12.0, 28.0);
        int indexFromDy(double dy) {
          return (dy / itemHeight).floor().clamp(0, letters.length - 1);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) {
            final idx = indexFromDy(details.localPosition.dy);
            onLetterSelected(letters[idx]);
          },
          onPanUpdate: (details) {
            final idx = indexFromDy(details.localPosition.dy);
            onLetterSelected(letters[idx]);
          },
          child: SizedBox(
            width: 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters
                  .map(
                    (letter) => SizedBox(
                      height: itemHeight,
                      child: Center(
                        child: Text(
                          letter,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class IndexPreview extends StatelessWidget {
  final String text;
  final bool visible;

  const IndexPreview({
    super.key,
    required this.text,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(right: 36),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DraggableScrollbar extends StatelessWidget {
  final ScrollController controller;
  final int itemCount;
  final double itemExtent;
  final String Function(int index) getLabel;
  final ValueChanged<String> onIndexChanged;
  final VoidCallback onDragEnd;
  final ValueChanged<int>? onScrollRequest;

  const DraggableScrollbar({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemExtent,
    required this.getLabel,
    required this.onIndexChanged,
    required this.onDragEnd,
    this.onScrollRequest,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (details) {},
          onVerticalDragUpdate: (details) {
            _handleDrag(details.localPosition.dy, totalHeight);
          },
          onVerticalDragEnd: (_) => onDragEnd(),
          onVerticalDragCancel: onDragEnd,
          child: SizedBox(
            width: 24,
            height: totalHeight,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                if (!controller.hasClients) return const SizedBox.shrink();

                final maxScroll = controller.position.maxScrollExtent;
                if (maxScroll <= 0) return const SizedBox.shrink();

                final currentScroll = controller.offset.clamp(0.0, maxScroll);
                final scrollFraction = currentScroll / maxScroll;

                final viewPort = controller.position.viewportDimension;
                final contentHeight = maxScroll + viewPort;
                final thumbHeight =
                    (viewPort / contentHeight * totalHeight).clamp(40.0, totalHeight);

                final availableSlide = totalHeight - thumbHeight;
                final thumbTop = scrollFraction * availableSlide;

                return Stack(
                  children: [
                    Positioned(
                      top: thumbTop,
                      right: 4,
                      child: Container(
                        width: 4,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _handleDrag(double dy, double totalHeight) {
    if (itemCount == 0) return;

    final clampedDy = dy.clamp(0.0, totalHeight);
    final fraction = clampedDy / totalHeight;

    final targetIndex = (fraction * (itemCount - 1)).floor();

    if (onScrollRequest != null) {
      onScrollRequest!(targetIndex);
    } else {
      final offset = (targetIndex * itemExtent).clamp(0.0, controller.position.maxScrollExtent);
      controller.jumpTo(offset);
    }

    final label = getLabel(targetIndex);
    onIndexChanged(label);
  }
}
