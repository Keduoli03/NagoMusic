import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PlaylistEntity {
  final String id;
  final String name;
  final List<String> songIds;
  final int createdAtMs;
  final bool isFavorite;

  const PlaylistEntity({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAtMs,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songIds': songIds,
        'createdAtMs': createdAtMs,
        'isFavorite': isFavorite,
      };

  factory PlaylistEntity.fromJson(Map<String, dynamic> json) {
    final rawSongIds = json['songIds'];
    final songIds = rawSongIds is List
        ? rawSongIds.map((e) => e?.toString() ?? '').where((e) => e.isNotEmpty).toList()
        : const <String>[];
    return PlaylistEntity(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      songIds: songIds,
      createdAtMs: int.tryParse((json['createdAtMs'] ?? '').toString()) ?? 0,
      isFavorite: json['isFavorite'] == true,
    );
  }

  PlaylistEntity copyWith({
    String? id,
    String? name,
    List<String>? songIds,
    int? createdAtMs,
    bool? isFavorite,
  }) {
    return PlaylistEntity(
      id: id ?? this.id,
      name: name ?? this.name,
      songIds: songIds ?? this.songIds,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class PlaylistsService {
  static final PlaylistsService instance = PlaylistsService._internal();

  static const String _prefsKey = 'playlists_v1';
  static const String favoritePlaylistId = '__favorite__';
  static const String favoritePlaylistName = '我喜欢';

  PlaylistsService._internal();

  Future<List<PlaylistEntity>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      final favorite = PlaylistEntity(
        id: favoritePlaylistId,
        name: favoritePlaylistName,
        songIds: const [],
        createdAtMs: 0,
        isFavorite: true,
      );
      await _save([favorite]);
      return [favorite];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final playlists = decoded
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .map(PlaylistEntity.fromJson)
          .where((p) => p.id.isNotEmpty && p.name.trim().isNotEmpty)
          .toList();
      final favIndex = playlists.indexWhere(
        (p) => p.isFavorite || p.id == favoritePlaylistId,
      );
      if (favIndex == -1) {
        playlists.insert(
          0,
          const PlaylistEntity(
            id: favoritePlaylistId,
            name: favoritePlaylistName,
            songIds: [],
            createdAtMs: 0,
            isFavorite: true,
          ),
        );
        await _save(playlists);
      } else {
        final existing = playlists[favIndex];
        if (!existing.isFavorite || existing.name != favoritePlaylistName) {
          playlists[favIndex] = existing.copyWith(
            isFavorite: true,
            name: favoritePlaylistName,
            id: favoritePlaylistId,
          );
          await _save(playlists);
        }
      }
      playlists.sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.createdAtMs.compareTo(a.createdAtMs);
      });
      return playlists;
    } catch (_) {
      final favorite = PlaylistEntity(
        id: favoritePlaylistId,
        name: favoritePlaylistName,
        songIds: const [],
        createdAtMs: 0,
        isFavorite: true,
      );
      await _save([favorite]);
      return [favorite];
    }
  }

  Future<PlaylistEntity> createPlaylist(String name) async {
    final trimmed = name.trim().isEmpty ? '新建歌单' : name.trim();
    final now = DateTime.now().millisecondsSinceEpoch;
    final playlist = PlaylistEntity(
      id: now.toString(),
      name: trimmed,
      songIds: const [],
      createdAtMs: now,
      isFavorite: false,
    );
    final all = (await loadAll()).toList();
    final insertAt = all.indexWhere((p) => !p.isFavorite);
    all.insert(insertAt < 0 ? all.length : insertAt, playlist);
    await _save(all);
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final trimmed = name.trim();
    if (id.isEmpty || trimmed.isEmpty) return;
    if (id == favoritePlaylistId) return;
    final all = (await loadAll()).toList();
    final idx = all.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    all[idx] = all[idx].copyWith(name: trimmed);
    await _save(all);
  }

  Future<void> deletePlaylist(String id) async {
    if (id.isEmpty) return;
    if (id == favoritePlaylistId) return;
    final all = (await loadAll()).where((p) => p.id != id).toList();
    await _save(all);
  }

  Future<void> addSongs(String playlistId, List<String> songIds) async {
    if (playlistId.isEmpty || songIds.isEmpty) return;
    final toAdd = songIds.where((e) => e.trim().isNotEmpty).toList();
    if (toAdd.isEmpty) return;
    final all = (await loadAll()).toList();
    final idx = all.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final existing = all[idx].songIds.toSet();
    existing.addAll(toAdd);
    all[idx] = all[idx].copyWith(songIds: existing.toList());
    await _save(all);
  }

  Future<void> removeSongs(String playlistId, List<String> songIds) async {
    if (playlistId.isEmpty || songIds.isEmpty) return;
    final toRemove = songIds.where((e) => e.trim().isNotEmpty).toSet();
    if (toRemove.isEmpty) return;
    final all = (await loadAll()).toList();
    final idx = all.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final next = all[idx].songIds.where((id) => !toRemove.contains(id)).toList();
    all[idx] = all[idx].copyWith(songIds: next);
    await _save(all);
  }

  Future<void> reorderSongs(String playlistId, List<String> orderedSongIds) async {
    if (playlistId.isEmpty) return;
    final ids = orderedSongIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final all = (await loadAll()).toList();
    final idx = all.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final existing = all[idx].songIds.toSet();
    final next = <String>[];
    for (final id in ids) {
      if (!existing.contains(id)) continue;
      if (next.contains(id)) continue;
      next.add(id);
    }
    for (final id in all[idx].songIds) {
      if (next.contains(id)) continue;
      next.add(id);
    }
    all[idx] = all[idx].copyWith(songIds: next);
    await _save(all);
  }

  Future<void> _save(List<PlaylistEntity> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(playlists.map((p) => p.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }
}
