import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:path/path.dart' as p;
import 'package:signals_flutter/signals_flutter.dart';

import '../../app/router/app_page_route.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/index.dart';
import '../source/folder_songs_page.dart';

/// A folder group: all audio sharing the same parent directory within one
/// source. Designed for audiobook libraries where "one folder = one book".
class _FolderGroup {
  final String sourceId;
  final String path; // dirname of the songs' uri (normalized with '/')
  final String name; // display name (basename of path)
  final bool isLocal;
  final int count;
  final SongEntity representative;

  const _FolderGroup({
    required this.sourceId,
    required this.path,
    required this.name,
    required this.isLocal,
    required this.count,
    required this.representative,
  });
}

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> with SignalsMixin {
  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();
  final SongDao _songDao = SongDao();

  late final _folders = createSignal<List<_FolderGroup>>([]);
  late final _loading = createSignal(true);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final songs = await _songDao.fetchAllCached();
    final map = <String, List<SongEntity>>{};
    for (final song in songs) {
      final uri = (song.uri ?? '').trim();
      if (uri.isEmpty) continue;
      // Must match FolderSongsPage's folder derivation exactly so the detail
      // page can filter correctly.
      final folder = p.dirname(uri).replaceAll('\\', '/');
      final key = '${song.sourceId ?? ''}|$folder';
      map.putIfAbsent(key, () => []).add(song);
    }

    final groups = <_FolderGroup>[];
    for (final entry in map.entries) {
      final first = entry.value.first;
      final folder = entry.key.substring(entry.key.indexOf('|') + 1);
      final name = p.basename(folder).trim();
      groups.add(
        _FolderGroup(
          sourceId: first.sourceId ?? '',
          path: folder,
          name: name.isEmpty ? '根目录' : name,
          isLocal: first.isLocal,
          count: entry.value.length,
          representative: first,
        ),
      );
    }
    groups.sort((a, b) => naturalCompare(a.name, b.name));

    if (!mounted) return;
    _folders.value = groups;
    _loading.value = false;
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _openFolder(_FolderGroup folder) {
    Navigator.of(context).push(
      buildAppPageRoute<void>(
        (_) => FolderSongsPage(
          title: folder.name,
          sourceId: folder.sourceId,
          folderPath: folder.path,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        key: _scaffoldKey,
        extendBodyBehindAppBar: true,
        appBar: AppTopBar(
          title: '文件夹',
          leading: IconButton(
            icon: Icon(
              useBottomNavigation ? AppIcons.arrowLeft : AppIcons.menu,
            ),
            onPressed: useBottomNavigation
                ? () => Navigator.of(context).maybePop()
                : _openDrawer,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        drawer: useBottomNavigation
            ? null
            : SideMenu(
                onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
        bottomNavIndex: useBottomNavigation ? 0 : null,
        onBottomNavTap: useBottomNavigation
            ? (index) => navigateToPrimaryDestination(context, index)
            : null,
        body: Watch.builder(
          builder: (context) {
            if (_loading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            final folders = _folders.value;
            if (folders.isEmpty) {
              return const Center(child: Text('还没有可显示的文件夹'));
            }
            final bottomPadding = AppPageScaffold.scrollableBottomPadding(
              context,
            );
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
              itemCount: folders.length,
              itemBuilder: (context, index) {
                return _FolderTile(
                  folder: folders[index],
                  onTap: () => _openFolder(folders[index]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final _FolderGroup folder;
  final VoidCallback onTap;

  const _FolderTile({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ArtworkWidget(
                        song: folder.representative,
                        size: 52,
                        borderRadius: 10,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        AppIcons.folder,
                        size: 14,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${folder.isLocal ? '本地' : '云端'} · ${folder.count} 个音频',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  AppIcons.chevronRight,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
