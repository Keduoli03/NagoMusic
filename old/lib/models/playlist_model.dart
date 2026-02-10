class Playlist {
  final int id;
  final String name;
  final int createdAt;
  final bool isFavorite;
  final int? songCount;
  final int? sortOrder;

  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.isFavorite = false,
    this.songCount,
    this.sortOrder,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as int,
      name: json['name'] as String,
      createdAt: json['created_at'] as int,
      isFavorite: (json['is_favorite'] as int?) == 1,
      songCount: json['song_count'] as int?,
      sortOrder: json['sort_order'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
      'is_favorite': isFavorite ? 1 : 0,
      'sort_order': sortOrder,
    };
  }
}
