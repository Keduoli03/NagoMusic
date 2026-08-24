import 'package:flutter/material.dart';

import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../app/state/song_state.dart';

enum DiscoveryKind { daily, recommended, heart }

/// 一张发现卡的静态配置 + 它对应的歌单，从 build 里拆出来只是为了让三张卡走同一
/// 条渲染路径，不用把 itemBuilder 写成三段 if。
class DiscoverySpec {
  final DiscoveryKind kind;
  final String eyebrow;
  final String title;
  final IconData? icon;
  final Color accent;
  final SongEntity? cover;
  final List<SongEntity> songs;

  const DiscoverySpec({
    required this.kind,
    required this.eyebrow,
    required this.title,
    required this.icon,
    required this.accent,
    required this.cover,
    required this.songs,
  });
}

class QuickLibraryData {
  final String label;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const QuickLibraryData({
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
  });
}

class HomeCountsCache {
  final int countAll;
  final int countLocal;
  final int countRemote;
  final List<WebDavSource> webDavSources;
  final Map<String, int> webDavCounts;
  final List<NavidromeSource> navidromeSources;
  final Map<String, int> navidromeCounts;

  const HomeCountsCache({
    required this.countAll,
    required this.countLocal,
    required this.countRemote,
    required this.webDavSources,
    required this.webDavCounts,
    this.navidromeSources = const [],
    this.navidromeCounts = const {},
  });

  HomeCountsCache copyWith({
    int? countAll,
    int? countLocal,
    int? countRemote,
    List<WebDavSource>? webDavSources,
    Map<String, int>? webDavCounts,
    List<NavidromeSource>? navidromeSources,
    Map<String, int>? navidromeCounts,
  }) {
    return HomeCountsCache(
      countAll: countAll ?? this.countAll,
      countLocal: countLocal ?? this.countLocal,
      countRemote: countRemote ?? this.countRemote,
      webDavSources: webDavSources ?? this.webDavSources,
      webDavCounts: webDavCounts ?? this.webDavCounts,
      navidromeSources: navidromeSources ?? this.navidromeSources,
      navidromeCounts: navidromeCounts ?? this.navidromeCounts,
    );
  }
}

class RecentAlbumItem {
  final String name;
  final SongEntity representative;

  const RecentAlbumItem({required this.name, required this.representative});
}

class HomeSourceItem {
  final String label;
  final String value;

  const HomeSourceItem({required this.label, required this.value});
}
