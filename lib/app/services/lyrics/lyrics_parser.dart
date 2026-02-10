import 'dart:math' as math;

import 'package:flutter_lyric/core/lyric_model.dart' as fl;

class ParsedLyricLine {
  final Duration? time;
  final String text;
  final String? translation;

  const ParsedLyricLine(this.time, this.text, {this.translation});
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
        final rightOnlyHan =
            han.hasMatch(right) && !kana.hasMatch(right) && !latin.hasMatch(right);
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

  static List<ParsedLyricLine> parseLrc(String lrc) {
    final lines = <ParsedLyricLine>[];
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
          validMatches.add(matches.first);
        } else {
          validMatches.addAll(matches);
        }
      }

      final split = _splitTranslation(fullText);
      final mainText = split.key;
      final transText = split.value;

      if (validMatches.isEmpty) {
        if (mainText.isNotEmpty) {
          final isDuplicate = lines.any(
            (l) => l.time == null && l.text == mainText && l.translation == transText,
          );
          if (!isDuplicate) {
            lines.add(ParsedLyricLine(null, mainText, translation: transText));
          }
        }
        continue;
      }

      for (final m in validMatches) {
        final d = _parseTimeMatch(m);
        if (mainText.isNotEmpty || (transText != null && transText.isNotEmpty)) {
          if (transText == null && lines.isNotEmpty) {
            final existingIndex = lines.lastIndexWhere((l) => l.time == d);
            if (existingIndex != -1) {
              final existing = lines[existingIndex];
              if (existing.translation == null &&
                  _isTranslationCandidate(existing.text, mainText)) {
                lines[existingIndex] = ParsedLyricLine(
                  d,
                  existing.text,
                  translation: mainText,
                );
                continue;
              }
            }
          }
          final isDuplicate = lines.any(
            (l) => l.time == d && l.text == mainText && l.translation == transText,
          );
          if (!isDuplicate) {
            lines.add(ParsedLyricLine(d, mainText, translation: transText));
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

  static List<fl.LyricWord>? _generateWords(
    String text,
    Duration start,
    Duration end,
  ) {
    final startMs = start.inMilliseconds;
    final endMs = end.inMilliseconds;
    final totalMs = math.max(1, endMs - startMs);
    final tokens = _tokenizeForKaraoke(text);
    final count = tokens.length;
    if (count <= 0) return null;
    if (count > 5000) return null;

    final weights = tokens.map((t) => t.weight).toList();
    final weightSum =
        weights.fold<double>(0.0, (sum, w) => sum + (w.isFinite ? w : 0.0));
    if (weightSum <= 0) {
      return _fallbackEvenWords(text, start, end);
    }

    final minMs = (totalMs / (count * 3)).floor().clamp(20, 80);
    final maxMs =
        math.min(1600, math.max(minMs, (totalMs * 0.45).round().clamp(120, 1600)));

    final durations = List<int>.generate(count, (i) {
      final d = (totalMs * (weights[i] / weightSum)).round();
      return d.clamp(minMs, maxMs);
    });

    var sumMs = durations.fold<int>(0, (s, v) => s + v);
    var diff = totalMs - sumMs;
    if (diff != 0) {
      for (int iter = 0; iter < 8 && diff != 0; iter++) {
        if (diff > 0) {
          final candidates = <int>[];
          for (int i = 0; i < count; i++) {
            if (durations[i] < maxMs) candidates.add(i);
          }
          if (candidates.isEmpty) break;
          final candWeightSum = candidates.fold<double>(
            0.0,
            (s, i) => s + weights[i],
          );
          if (candWeightSum <= 0) break;
          for (final i in candidates) {
            if (diff <= 0) break;
            final share = (diff * (weights[i] / candWeightSum)).floor();
            final add = math.max(1, share);
            final room = maxMs - durations[i];
            final applied = math.min(add, room);
            durations[i] += applied;
            diff -= applied;
          }
        } else {
          final candidates = <int>[];
          for (int i = 0; i < count; i++) {
            if (durations[i] > minMs) candidates.add(i);
          }
          if (candidates.isEmpty) break;
          final candWeightSum = candidates.fold<double>(
            0.0,
            (s, i) => s + weights[i],
          );
          if (candWeightSum <= 0) break;
          for (final i in candidates) {
            if (diff >= 0) break;
            final share = ((-diff) * (weights[i] / candWeightSum)).floor();
            final sub = math.max(1, share);
            final room = durations[i] - minMs;
            final applied = math.min(sub, room);
            durations[i] -= applied;
            diff += applied;
          }
        }
      }

      if (diff != 0) {
        for (int i = 0; i < count && diff != 0; i++) {
          if (diff > 0 && durations[i] < maxMs) {
            durations[i]++;
            diff--;
          } else if (diff < 0 && durations[i] > minMs) {
            durations[i]--;
            diff++;
          }
        }
      }
    }

    final words = <fl.LyricWord>[];
    var accMs = 0;
    for (int i = 0; i < count; i++) {
      final ws = Duration(milliseconds: startMs + accMs);
      accMs += durations[i];
      final isLast = i == count - 1;
      final we = isLast
          ? Duration(milliseconds: endMs)
          : Duration(milliseconds: math.min(endMs, startMs + accMs));
      if (we <= ws) continue;
      words.add(fl.LyricWord(text: tokens[i].text, start: ws, end: we));
    }
    return words.isEmpty ? null : words;
  }

  static List<fl.LyricWord>? _fallbackEvenWords(
    String text,
    Duration start,
    Duration end,
  ) {
    final startMs = start.inMilliseconds;
    final endMs = end.inMilliseconds;
    final totalMs = math.max(1, endMs - startMs);
    final runes = text.runes.toList();
    final len = runes.length;
    if (len <= 0) return null;
    if (len > 5000) return null;
    final words = <fl.LyricWord>[];
    for (int k = 0; k < len; k++) {
      final ch = String.fromCharCode(runes[k]);
      final wordStartMs = startMs + ((totalMs * k) ~/ len);
      final wordEndMs =
          k == len - 1 ? endMs : startMs + ((totalMs * (k + 1)) ~/ len);
      final ws = Duration(milliseconds: wordStartMs);
      final we = Duration(milliseconds: math.max(wordEndMs, wordStartMs + 1));
      words.add(fl.LyricWord(text: ch, start: ws, end: we));
    }
    return words;
  }

  static bool _isHanCode(int code) =>
      (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF);
  static bool _isKanaCode(int code) => code >= 0x3040 && code <= 0x30FF;
  static bool _isHangulCode(int code) => code >= 0xAC00 && code <= 0xD7AF;
  static bool _isAsciiAlphaNum(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A);
  static bool _isWhitespace(int code) =>
      code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x3000;

  static bool _isPunctuation(int code) {
    const ascii = ",.!?:;'\"()[]{}-";
    if (code <= 0x7F && ascii.contains(String.fromCharCode(code))) {
      return true;
    }
    switch (code) {
      case 0x3001: // 、
      case 0x3002: // 。
      case 0xFF0C: // ，
      case 0xFF0E: // ．
      case 0xFF01: // ！
      case 0xFF1F: // ？
      case 0xFF1A: // ：
      case 0xFF1B: // ；
      case 0x2026: // …
      case 0x2014: // —
        return true;
    }
    return false;
  }

  static double _punctPauseWeight(String s) {
    if (s.isEmpty) return 0.0;
    final c = s.runes.first;
    if (c == 0x3002 || c == 0xFF01 || c == 0xFF1F || c == 0x21 || c == 0x3F) {
      return 0.9;
    }
    if (c == 0x3001 ||
        c == 0xFF0C ||
        c == 0x2C ||
        c == 0x2E ||
        c == 0xFF1B ||
        c == 0xFF1A ||
        c == 0x3B ||
        c == 0x3A) {
      return 0.55;
    }
    if (c == 0x2026 || c == 0x2014) {
      return 0.8;
    }
    return 0.35;
  }

  static double _latinTokenWeight(int length) {
    if (length <= 0) return 0.6;
    final w = 0.55 + 0.14 * length;
    return w.clamp(0.6, 2.8);
  }

  static double _charTokenWeight(int code) {
    if (_isHanCode(code) || _isKanaCode(code) || _isHangulCode(code)) {
      return 1.0;
    }
    if (_isAsciiAlphaNum(code)) {
      return 0.55;
    }
    return 0.9;
  }

  static List<_KaraokeToken> _tokenizeForKaraoke(String text) {
    final runes = text.runes.toList();
    final rawTokens = <_KaraokeToken>[];
    for (int i = 0; i < runes.length;) {
      final code = runes[i];
      if (_isWhitespace(code)) {
        rawTokens.add(_KaraokeToken(String.fromCharCode(code), 0.0));
        i++;
        continue;
      }
      if (_isAsciiAlphaNum(code)) {
        final sb = StringBuffer();
        int j = i;
        while (j < runes.length) {
          final c = runes[j];
          if (_isAsciiAlphaNum(c) || c == 0x27 || c == 0x2019) {
            sb.writeCharCode(c);
            j++;
            continue;
          }
          break;
        }
        final word = sb.toString();
        rawTokens.add(_KaraokeToken(word, _latinTokenWeight(word.length)));
        i = j;
        continue;
      }
      final ch = String.fromCharCode(code);
      rawTokens.add(_KaraokeToken(ch, _charTokenWeight(code)));
      i++;
    }

    final tokens = <_KaraokeToken>[];
    for (final t in rawTokens) {
      if (t.text.isEmpty) continue;
      final code = t.text.runes.first;
      if (_isWhitespace(code)) {
        if (tokens.isEmpty) continue;
        tokens[tokens.length - 1] = tokens.last.copyWith(
          text: tokens.last.text + t.text,
        );
        continue;
      }
      if (_isPunctuation(code)) {
        if (tokens.isEmpty) {
          tokens.add(_KaraokeToken(t.text, math.max(0.2, t.weight)));
        } else {
          tokens[tokens.length - 1] = tokens.last.copyWith(
            text: tokens.last.text + t.text,
            weight: tokens.last.weight + _punctPauseWeight(t.text),
          );
        }
        continue;
      }
      tokens.add(t);
    }

    if (tokens.isEmpty) return const [];
    return tokens;
  }

  static fl.LyricModel buildModelFromRaw(
    String lrc, {
    Duration? songDuration,
    bool predictDuration = true,
    bool forceKaraoke = false,
  }) {
    final modelLines = <fl.LyricLine>[];
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
        final segStart = matches[i].end;
        final segEnd = matches[i + 1].start;
        if (segEnd > segStart) {
          final textBetween = raw.substring(segStart, segEnd);
          if (textBetween.trim().isNotEmpty) {
            hasInterleavedText = true;
            break;
          }
        }
      }

      if (hasInterleavedText) {
        final timestamps = matches.map(_parseTimeMatch).toList();
        final words = <fl.LyricWord>[];
        for (int i = 0; i < matches.length; i++) {
          final segStart = matches[i].end;
          final segEnd = i + 1 < matches.length ? matches[i + 1].start : raw.length;
          if (segEnd < segStart) continue;
          final segment = raw.substring(segStart, segEnd);
          if (segment.trim().isEmpty) continue;

          final wordStart = timestamps[i];
          final wordEnd = i + 1 < timestamps.length ? timestamps[i + 1] : null;
          words.add(
            fl.LyricWord(
              text: segment,
              start: wordStart,
              end: wordEnd,
            ),
          );
        }

        final lineStart = timestamps.first;
        if (!seenTimes.add(lineStart.inMilliseconds)) continue;
        final lastStart = timestamps.last;
        var tailDuration = timestamps.length >= 2
            ? (lastStart - timestamps[timestamps.length - 2])
            : const Duration(milliseconds: 250);
        if (tailDuration <= Duration.zero) {
          tailDuration = const Duration(milliseconds: 120);
        }
        tailDuration = Duration(
          milliseconds: tailDuration.inMilliseconds.clamp(120, 1200),
        );
        final lineEndCandidate = lastStart + tailDuration;
        final lineEnd = lineEndCandidate > lineStart ? lineEndCandidate : null;

        modelLines.add(
          fl.LyricLine(
            start: lineStart,
            end: lineEnd,
            text: mainText,
            translation: transText,
            words: words.isNotEmpty ? words : null,
          ),
        );
      } else {
        for (final m in matches) {
          final d = _parseTimeMatch(m);
          final existingIndex = modelLines.lastIndexWhere((l) => l.start == d);
          if (existingIndex != -1) {
            final existing = modelLines[existingIndex];
            if ((existing.translation == null || existing.translation!.isEmpty) &&
                transText == null &&
                _isTranslationCandidate(existing.text, mainText)) {
              modelLines[existingIndex] = fl.LyricLine(
                start: existing.start,
                end: existing.end,
                text: existing.text,
                translation: mainText,
                words: existing.words,
              );
            }
            continue;
          }
          if (!seenTimes.add(d.inMilliseconds)) continue;
          modelLines.add(
            fl.LyricLine(
              start: d,
              text: mainText,
              translation: transText,
            ),
          );
        }
      }
    }

    modelLines.sort((a, b) => a.start.compareTo(b.start));

    if (modelLines.isEmpty) {
      final parsed = parseLrc(lrc);
      final textOnly = parsed.where((e) => e.time == null).toList();
      final count = textOnly.length;
      if (count > 0) {
        final totalMs = (songDuration?.inMilliseconds ?? (count * 3000));
        final rawStepMs = totalMs ~/ count;
        final stepMs = rawStepMs.clamp(1500, 6000);
        for (int i = 0; i < count; i++) {
          final start = Duration(milliseconds: stepMs * i);
          var end = Duration(milliseconds: stepMs * (i + 1));
          if (songDuration != null && i == count - 1) {
            end = songDuration;
          }
          if (end <= start) {
            end = start + const Duration(seconds: 3);
          }
          final line = textOnly[i];
          final text = line.text;
          if (text.isEmpty) continue;
          final words = (forceKaraoke || predictDuration)
              ? _generateWords(text, start, end)
              : null;
          modelLines.add(
            fl.LyricLine(
              start: start,
              end: end,
              text: text,
              translation: line.translation,
              words: words,
            ),
          );
        }
      }
      modelLines.sort((a, b) => a.start.compareTo(b.start));
    }

    final fixedLines = <fl.LyricLine>[];
    for (int i = 0; i < modelLines.length; i++) {
      final line = modelLines[i];
      final start = line.start;
      final nextStart = (i + 1 < modelLines.length) ? modelLines[i + 1].start : null;
      final currentEnd = line.end;
      var effectiveEnd = (currentEnd != null &&
              currentEnd > start &&
              (nextStart == null || currentEnd <= nextStart))
          ? currentEnd
          : (nextStart ?? songDuration ?? start + const Duration(seconds: 3));
      if (effectiveEnd <= start) {
        effectiveEnd = start + const Duration(seconds: 3);
      }
      final lineMs = (effectiveEnd - start).inMilliseconds;
      final karaokeEndBufferMs = (lineMs * 0.08).round().clamp(60, 220);
      final safeEndForWords = nextStart == null
          ? effectiveEnd
          : Duration(
              milliseconds: (effectiveEnd.inMilliseconds - karaokeEndBufferMs)
                  .clamp(start.inMilliseconds + 1, effectiveEnd.inMilliseconds),
            );

      List<fl.LyricWord>? words = line.words;
      if (words != null && words.isNotEmpty) {
        final fixedWords = <fl.LyricWord>[];
        for (int w = 0; w < words.length; w++) {
          final word = words[w];
          Duration wordEnd = word.end ??
              ((w + 1 < words.length) ? words[w + 1].start : effectiveEnd);
          if (wordEnd <= word.start) {
            wordEnd = word.start + const Duration(milliseconds: 1);
          }
          fixedWords.add(
            fl.LyricWord(
              text: word.text,
              start: word.start,
              end: wordEnd,
            ),
          );
        }
        words = fixedWords;
      } else if (forceKaraoke || predictDuration) {
        words = _generateWords(line.text, start, safeEndForWords);
      }

      fixedLines.add(
        fl.LyricLine(
          start: start,
          end: effectiveEnd,
          text: line.text,
          translation: line.translation,
          words: words,
        ),
      );
    }

    return fl.LyricModel(lines: fixedLines);
  }
}

class _KaraokeToken {
  final String text;
  final double weight;

  const _KaraokeToken(this.text, this.weight);

  _KaraokeToken copyWith({String? text, double? weight}) {
    return _KaraokeToken(
      text ?? this.text,
      weight ?? this.weight,
    );
  }
}
