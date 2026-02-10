import 'dart:math' as math;
import 'package:flutter_lyric/core/lyric_model.dart' as flmodel;

class LyricLine {
  final Duration? time;
  final String text;
  final String? translation;
  LyricLine(this.time, this.text, {this.translation});
}

class LyricsParser {
  static bool _hasHan(String text) => RegExp(r'[\u4E00-\u9FFF]').hasMatch(text);
  static bool _hasKana(String text) =>
      RegExp(r'[\u3040-\u30FF]').hasMatch(text);
  static bool _hasHangul(String text) =>
      RegExp(r'[\uAC00-\uD7AF]').hasMatch(text);
  static bool _hasLatin(String text) => RegExp(r'[A-Za-z]').hasMatch(text);
  static bool _isHanOnly(String text) {
    if (!_hasHan(text)) return false;
    return !_hasLatin(text) && !_hasKana(text) && !_hasHangul(text);
  }

  static bool _isTranslationCandidate(String mainText, String nextText) {
    return _isHanOnly(nextText) && !_isHanOnly(mainText);
  }

  static MapEntry<String, String?> _splitTranslation(String fullText) {
    String mainText = fullText;
    String? transText;
    final splitReg = RegExp(r'\s+(?:/|\|)\s+');
    final match = splitReg.firstMatch(fullText);
    if (match != null) {
      mainText = fullText.substring(0, match.start).trim();
      transText = fullText.substring(match.end).trim();
    }
    if (transText == null) {
      final thinIdx = fullText.lastIndexOf('\u2009');
      final fullIdx = fullText.lastIndexOf('\u3000');
      int splitIdx = -1;
      if (thinIdx >= 0) {
        splitIdx = thinIdx;
      } else if (fullIdx >= 0) {
        splitIdx = fullIdx;
      } else {
        final multiSpaceReg = RegExp(r'\s{2,}');
        final all = multiSpaceReg.allMatches(fullText).toList();
        if (all.isNotEmpty) {
          splitIdx = all.last.start;
        }
      }
      if (splitIdx >= 0) {
        final left = fullText.substring(0, splitIdx).trim();
        final right = fullText.substring(splitIdx + 1).trim();
        final han = RegExp(r'[\u4E00-\u9FFF]');
        final kana = RegExp(r'[\u3040-\u30FF]');
        final latin = RegExp(r'[A-Za-z]');
        final leftOnlyHan =
            han.hasMatch(left) && !kana.hasMatch(left) && !latin.hasMatch(left);
        final rightOnlyHan = han.hasMatch(right) &&
            !kana.hasMatch(right) &&
            !latin.hasMatch(right);
        if (leftOnlyHan && rightOnlyHan) {
          mainText = fullText;
          transText = null;
        } else {
          mainText = left;
          transText = right;
        }
      }
    }
    return MapEntry(mainText, transText);
  }

  static Duration _parseTimeMatch(RegExpMatch m) {
    final mm = int.tryParse(m.group(1) ?? '0') ?? 0;
    final ss = int.tryParse(m.group(2) ?? '0') ?? 0;
    final frac = m.group(3);
    int ms = 0;
    if (frac != null) {
      final f = frac.padRight(3, '0');
      ms = int.tryParse(f) ?? 0;
    }
    return Duration(minutes: mm, seconds: ss, milliseconds: ms);
  }

  static String reconstructLrc(List<LyricLine> lines, {bool translation = false}) {
    final buf = StringBuffer();
    for (final line in lines) {
      if (line.time == null) continue;
      final content = translation ? line.translation : line.text;
      if (content == null || content.isEmpty) continue;

      final m = line.time!.inMinutes;
      final s = line.time!.inSeconds % 60;
      final ms = line.time!.inMilliseconds % 1000;
      final cs = (ms / 10).floor();

      final timeStr =
          '[${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}]';
      buf.writeln('$timeStr$content');
    }
    return buf.toString();
  }

  static List<LyricLine> parseLrc(String lrc) {
    final lines = <LyricLine>[];
    final rawLines =
        lrc.split(RegExp(r'\r?\n')).where((e) => e.trim().isNotEmpty);
    final timeReg = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');

    for (final raw in rawLines) {
      if (RegExp(r'^\[(ti|ar|al|by|offset):').hasMatch(raw.toLowerCase())) {
        continue;
      }
      final matches = timeReg.allMatches(raw).toList();
      final fullText = raw.replaceAll(timeReg, '').trim();

      if (fullText.startsWith('/*') ||
          fullText.startsWith('//') ||
          fullText.startsWith('<!')) {
        continue;
      }

      // Check for karaoke pattern (text between timestamps) to avoid duplication
      final validMatches = <RegExpMatch>[];
      if (matches.isNotEmpty) {
        bool hasInterleavedText = false;
        for (int i = 0; i < matches.length - 1; i++) {
          final start = matches[i].end;
          final end = matches[i + 1].start;
          if (end > start) {
            final textBetween = raw.substring(start, end);
            if (textBetween.trim().isNotEmpty) {
              hasInterleavedText = true;
              break;
            }
          }
        }

        if (hasInterleavedText) {
          // Karaoke mode: only use first timestamp
          validMatches.add(matches.first);
        } else {
          // Repetition mode: use all timestamps
          validMatches.addAll(matches);
        }
      }

      final split = _splitTranslation(fullText);
      final mainText = split.key;
      final transText = split.value;

      if (validMatches.isEmpty) {
        if (mainText.isNotEmpty) {
          // Check for duplicates before adding non-timestamped lines
          final isDuplicate = lines.any(
            (l) =>
                l.time == null &&
                l.text == mainText &&
                l.translation == transText,
          );
          if (!isDuplicate) {
            lines.add(LyricLine(null, mainText, translation: transText));
          }
        }
        continue;
      }
      for (final m in validMatches) {
        final mm = int.tryParse(m.group(1) ?? '0') ?? 0;
        final ss = int.tryParse(m.group(2) ?? '0') ?? 0;
        final frac = m.group(3);
        int ms = 0;
        if (frac != null) {
          final f = frac.padRight(3, '0');
          ms = int.tryParse(f) ?? 0;
        }
        final d = Duration(minutes: mm, seconds: ss, milliseconds: ms);
        if (mainText.isNotEmpty || (transText != null && transText.isNotEmpty)) {
          if (transText == null && lines.isNotEmpty) {
            final existingIndex =
                lines.lastIndexWhere((l) => l.time == d);
            if (existingIndex != -1) {
              final existing = lines[existingIndex];
              if (existing.translation == null &&
                  _isTranslationCandidate(existing.text, mainText)) {
                lines[existingIndex] =
                    LyricLine(d, existing.text, translation: mainText);
                continue;
              }
            }
          }
          // Check for duplicates before adding
          final isDuplicate = lines.any(
            (l) => l.time == d && l.text == mainText && l.translation == transText,
          );
          if (!isDuplicate) {
            lines.add(LyricLine(d, mainText, translation: transText));
          }
        }
      }
    }
    lines.sort((a, b) {
      final ta = a.time ?? Duration.zero;
      final tb = b.time ?? Duration.zero;
      return ta.compareTo(tb);
    });
    return lines;
  }

  static flmodel.LyricModel buildModelFromRaw(String lrc, {bool predictDuration = true}) {
    final modelLines = <flmodel.LyricLine>[];
    final rawLines =
        lrc.split(RegExp(r'\r?\n')).where((e) => e.trim().isNotEmpty);
    final timeReg = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
    final seenTimes = <int>{};
    for (final raw in rawLines) {
      if (RegExp(r'^\[(ti|ar|al|by|offset):').hasMatch(raw.toLowerCase())) {
        continue;
      }
      final matches = timeReg.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final fullText = raw.replaceAll(timeReg, '').trim();
      if (fullText.isEmpty) continue;
      if (fullText.startsWith('/*') ||
          fullText.startsWith('//') ||
          fullText.startsWith('<!')) {
        continue;
      }
      final split = _splitTranslation(fullText);
      final mainText = split.key;
      final transText = split.value;
      if (mainText.isEmpty) continue;
      bool hasInterleavedText = false;
      for (int i = 0; i < matches.length - 1; i++) {
        final start = matches[i].end;
        final end = matches[i + 1].start;
        if (end > start) {
          final textBetween = raw.substring(start, end);
          if (textBetween.trim().isNotEmpty) {
            hasInterleavedText = true;
            break;
          }
        }
      }
      if (hasInterleavedText) {
        final timestamps = matches.map(_parseTimeMatch).toList();
        final words = <flmodel.LyricWord>[];
        for (int i = 0; i < matches.length; i++) {
          final segmentStart = matches[i].end;
          final segmentEnd =
              i + 1 < matches.length ? matches[i + 1].start : raw.length;
          if (segmentEnd < segmentStart) continue;
          final segment = raw.substring(segmentStart, segmentEnd);
          if (segment.trim().isEmpty) {
            continue;
          }
          final wordStart = timestamps[i];
          final wordEnd = i + 1 < timestamps.length ? timestamps[i + 1] : null;
          words.add(
            flmodel.LyricWord(
              text: segment,
              start: wordStart,
              end: wordEnd,
            ),
          );
        }
        final lineStart = timestamps.first;
        if (seenTimes.add(lineStart.inMilliseconds)) {
          modelLines.add(
            flmodel.LyricLine(
              start: lineStart,
              end: words.isNotEmpty ? words.last.end : null,
              text: mainText,
              translation: transText,
              words: words.isNotEmpty ? words : null,
            ),
          );
        }
      } else {
        for (final m in matches) {
          final d = _parseTimeMatch(m);
          final existingIndex =
              modelLines.lastIndexWhere((l) => l.start == d);
          if (existingIndex != -1) {
            final existing = modelLines[existingIndex];
            if ((existing.translation == null ||
                    existing.translation!.isEmpty) &&
                transText == null &&
                _isTranslationCandidate(existing.text, mainText)) {
              modelLines[existingIndex] = flmodel.LyricLine(
                start: existing.start,
                end: existing.end,
                text: existing.text,
                translation: mainText,
                words: existing.words,
              );
            }
            continue;
          }
          if (!seenTimes.add(d.inMilliseconds)) {
            continue;
          }
          modelLines.add(
            flmodel.LyricLine(
              start: d,
              text: mainText,
              translation: transText,
            ),
          );
        }
      }
    }
    modelLines.sort((a, b) => a.start.compareTo(b.start));

    // Post-process to generate simulated words for lines without karaoke data
    if (predictDuration) {
      for (int i = 0; i < modelLines.length; i++) {
        final line = modelLines[i];
        if (line.words != null && line.words!.isNotEmpty) continue;

        final start = line.start;
        final nextStart = (i + 1 < modelLines.length) ? modelLines[i + 1].start : null;
        // Use existing end if valid, otherwise estimate from next line
        // Ensure effectiveEnd is strictly greater than start to allow word generation
        var effectiveEnd = (line.end != null && (nextStart == null || line.end! > start))
            ? line.end!
            : (nextStart ?? start + const Duration(seconds: 3));
        
        if (effectiveEnd <= start) {
          effectiveEnd = start + const Duration(seconds: 3);
        }

        final generatedWords = generateWords(line.text, start, effectiveEnd);
        if (generatedWords != null) {
          modelLines[i] = flmodel.LyricLine(
            start: start,
            end: effectiveEnd,
            text: line.text,
            translation: line.translation,
            words: generatedWords,
          );
        }
      }
    }

    return flmodel.LyricModel(lines: modelLines);
  }

  static List<flmodel.LyricWord>? generateWords(
      String text, Duration start, Duration end,) {
    final startMs = start.inMilliseconds;
    final endMs = end.inMilliseconds;
    final totalMs = math.max(1, endMs - startMs);
    final runes = text.runes.toList();
    final len = runes.length;
    
    if (len <= 0) return null;
    // Remove strict length limit or increase it significantly
    if (len > 5000) return null;

    final words = <flmodel.LyricWord>[];
    for (int k = 0; k < len; k++) {
      final ch = String.fromCharCode(runes[k]);
      final wordStartMs = startMs + ((totalMs * k) ~/ len);
      final wordEndMs =
          k == len - 1 ? endMs : startMs + ((totalMs * (k + 1)) ~/ len);
      final ws = Duration(milliseconds: wordStartMs);
      final we = Duration(milliseconds: math.max(wordEndMs, wordStartMs + 1));
      words.add(flmodel.LyricWord(text: ch, start: ws, end: we));
    }
    return words;
  }

  static String reconstructKaraoke(List<LyricLine> lines) {
    if (lines.isEmpty) return '';
    final buf = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.time == null) continue;
      final text = line.text;
      if (text.isEmpty) continue;
      Duration? end;
      for (int j = i + 1; j < lines.length; j++) {
        final t = lines[j].time;
        if (t != null) {
          end = t;
          break;
        }
      }
      final start = line.time!;
      if (end == null || end <= start) {
        final startMs = start.inMilliseconds;
        buf.writeln('[$startMs,0]$text');
        continue;
      }
      final startMs = start.inMilliseconds;
      final endMs = end.inMilliseconds;
      final totalMs = endMs - startMs;
      final runes = text.runes.toList();
      final len = runes.length;
      if (len == 0) {
        buf.writeln('[$startMs,$totalMs]$text');
        continue;
      }
      if (len > 120) {
        buf.writeln('[$startMs,$totalMs]$text');
        continue;
      }
      buf.write('[$startMs,$totalMs]');
      for (int k = 0; k < len; k++) {
        final ch = String.fromCharCode(runes[k]);
        final wordStart = startMs + ((totalMs * k) ~/ len);
        final wordEnd = startMs + ((totalMs * (k + 1)) ~/ len);
        final wordDur = math.max(1, wordEnd - wordStart);
        buf.write('($wordStart,$wordDur)');
        buf.write(ch);
        if (k != len - 1) buf.write(' ');
      }
      buf.writeln();
    }
    return buf.toString();
  }

  static flmodel.LyricModel buildModel(List<LyricLine> lines, {bool predictDuration = true}) {
    final modelLines = <flmodel.LyricLine>[];
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.time == null) continue;
      final text = line.text;
      if (text.isEmpty) continue;
      Duration? end;
      for (int j = i + 1; j < lines.length; j++) {
        final t = lines[j].time;
        if (t != null) {
          end = t;
          break;
        }
      }
      final start = line.time!;
      var effectiveEnd = (end != null && end > start) ? end : start + const Duration(seconds: 3);
      if (effectiveEnd <= start) {
        effectiveEnd = start + const Duration(seconds: 3);
      }
      
      final generatedWords = predictDuration ? generateWords(text, start, effectiveEnd) : null;

      modelLines.add(
        flmodel.LyricLine(
          start: start,
          end: effectiveEnd,
          text: text,
          translation: line.translation,
          words: generatedWords,
        ),
      );
    }
    return flmodel.LyricModel(lines: modelLines);
  }
}
