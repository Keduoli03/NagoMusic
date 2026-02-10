import 'music_entity.dart';

class AlbumInfo {
  final String name;
  final int count;
  final String artistLabel;
  final MusicEntity representative;

  const AlbumInfo({
    required this.name,
    required this.count,
    required this.artistLabel,
    required this.representative,
  });
}
