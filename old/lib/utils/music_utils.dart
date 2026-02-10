import '../models/music_entity.dart';

List<String> splitArtists(String raw) {
  final normalized = raw.replaceAll('、', '/').replaceAll('＆', '&');
  final parts = normalized.split(RegExp(r'[\/&]'));
  final results = <String>[];
  for (final part in parts) {
    final name = part.trim();
    if (name.isEmpty) continue;
    results.add(name);
  }
  return results;
}

String primaryArtistLabel(String raw) {
  final names = splitArtists(raw);
  if (names.isEmpty) return '未知艺术家';
  return names.first;
}

String albumYearFromSongs(List<MusicEntity> songs) {
  for (final song in songs) {
    final ms = song.fileModifiedMs;
    if (ms == null) continue;
    try {
      return DateTime.fromMillisecondsSinceEpoch(ms).year.toString();
    } catch (_) {}
  }
  return '';
}
