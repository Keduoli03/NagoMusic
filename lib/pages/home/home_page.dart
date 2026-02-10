import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/router/app_router.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../components/index.dart';
import '../library/albums_page.dart';
import '../library/artists_page.dart';
import '../library/playlists_page.dart';

enum _HomeFilter { all, local, webdav }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SignalsMixin {
  static const String _prefsHomeFilter = 'home_filter';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SongDao _songDao = SongDao();

  late final _filter = createSignal(_HomeFilter.all);
  late final _loading = createSignal(true);
  late final _countAll = createSignal(0);
  late final _countLocal = createSignal(0);
  late final _countRemote = createSignal(0);

  late final _filterTitle = computed<String>(() {
    return switch (_filter.value) {
      _HomeFilter.local => '本地音乐',
      _HomeFilter.webdav => 'WebDAV',
      _ => '全部',
    };
  });

  late final _filterCount = computed<int>(() {
    return switch (_filter.value) {
      _HomeFilter.local => _countLocal.value,
      _HomeFilter.webdav => _countRemote.value,
      _ => _countAll.value,
    };
  });

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsHomeFilter) ?? 'all';
    final filter = switch (raw) {
      'local' => _HomeFilter.local,
      'webdav' => _HomeFilter.webdav,
      _ => _HomeFilter.all,
    };

    final counts = await Future.wait<int>([
      _songDao.countAll(),
      _songDao.countLocal(),
      _songDao.countRemote(),
    ]);
    if (!mounted) return;
    _filter.value = filter;
    _countAll.value = counts[0];
    _countLocal.value = counts[1];
    _countRemote.value = counts[2];
    _loading.value = false;
  }

  Future<void> _setFilter(_HomeFilter next) async {
    _filter.value = next;
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (next) {
      _HomeFilter.local => 'local',
      _HomeFilter.webdav => 'webdav',
      _ => 'all',
    };
    await prefs.setString(_prefsHomeFilter, raw);
  }

  void _handleBottomNavTap(int index) {
    if (index == 0) return;
    final target = index == 1 ? AppRoutes.songs : AppRoutes.source;
    Navigator.pushNamedAndRemoveUntil(context, target, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      scaffoldKey: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '首页',
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Watch.builder(
            builder: (context) => PopupMenuButton<_HomeFilter>(
              icon: const Icon(Icons.filter_list),
              initialValue: _filter.value,
              tooltip: '筛选',
              onSelected: _setFilter,
              itemBuilder: (context) => const [
                PopupMenuItem(value: _HomeFilter.all, child: Text('全部')),
                PopupMenuItem(value: _HomeFilter.local, child: Text('本地音乐')),
                PopupMenuItem(value: _HomeFilter.webdav, child: Text('WebDAV')),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: const SideMenu(),
      body: Watch.builder(
        builder: (context) => RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
            children: [
              Text(
                '音乐库',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              _HomeStatsRow(
                loading: _loading.value,
                filterLabel: _filterTitle.value,
                songCount: _filterCount.value,
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final itemWidth = (width - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _HomeEntryCard(
                          icon: Icons.people_rounded,
                          label: '艺术家',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ArtistsPage()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _HomeEntryCard(
                          icon: Icons.album_rounded,
                          label: '专辑',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AlbumsPage()),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _HomeEntryCard(
                          icon: Icons.queue_music_rounded,
                          label: '歌单',
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PlaylistsPage()),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavIndex: 0,
      onBottomNavTap: _handleBottomNavTap,
    );
  }
}

class _HomeStatsRow extends StatelessWidget {
  final bool loading;
  final String filterLabel;
  final int songCount;

  const _HomeStatsRow({
    required this.loading,
    required this.filterLabel,
    required this.songCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor = isDark ? const Color.fromARGB(28, 0, 0, 0) : const Color.fromARGB(15, 0, 0, 0);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.library_music_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              filterLabel,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (loading)
            Text(
              '--',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withAlpha(204),
              ),
            )
          else
            Text(
              '$songCount 首',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withAlpha(204),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeEntryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HomeEntryCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor =
        isDark ? const Color.fromARGB(28, 0, 0, 0) : const Color.fromARGB(15, 0, 0, 0);
    final iconColor = isDark ? Colors.white70 : const Color.fromARGB(255, 40, 40, 40);
    final textColor = isDark ? Colors.white : const Color.fromARGB(255, 45, 45, 45);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
