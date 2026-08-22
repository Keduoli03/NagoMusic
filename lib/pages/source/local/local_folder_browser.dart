import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

import '../../../app/router/app_page_route.dart';
import '../../../app/services/block_list_service.dart';
import '../../../app/services/db/dao/song_dao.dart';
import '../../../components/index.dart';
import '../folder_info.dart';
import '../folder_songs_page.dart';
import '../local_source_settings_page.dart';

class LocalFolderBrowser extends StatefulWidget {
  const LocalFolderBrowser({super.key});

  @override
  State<LocalFolderBrowser> createState() => _LocalFolderBrowserState();
}

class _LocalFolderBrowserState extends State<LocalFolderBrowser>
    with SignalsMixin {
  final SongDao _songDao = SongDao();
  late final _folders = createSignal<List<FolderInfo>>([]);
  late final _isLoading = createSignal(true);
  late final _blockedFolders = createSignal<Set<String>>({});

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    _isLoading.value = true;
    final songs = await _songDao.fetchAll(sourceId: 'local');
    final blocked = await BlockListService.instance.load('blocked_folders');

    if (mounted) {
      _blockedFolders.value = blocked;
    }

    final Map<String, int> folderCounts = {};

    for (final song in songs) {
      if (song.uri == null) continue;
      final dir = p.dirname(song.uri!).replaceAll('\\', '/');
      if (blocked.contains(dir)) continue;
      folderCounts[dir] = (folderCounts[dir] ?? 0) + 1;
    }

    final List<FolderInfo> list = folderCounts.entries.map((e) {
      final path = e.key;
      final name = p.basename(path);
      return FolderInfo(id: path, name: name, count: e.value);
    }).toList();

    // Sort by name
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (mounted) {
      _folders.value = list;
      _isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '本地音乐',
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () {
              Navigator.push(
                context,
                buildAppPageRoute((_) => const LocalSourceSettingsPage()),
              ).then((_) => _loadFolders());
            },
          ),
        ],
      ),
      body: Watch.builder(
        builder: (context) {
          if (_isLoading.value) {
            return const Center(child: CircularProgressIndicator());
          }

          final folders = _folders.value;
          final blocked = _blockedFolders.value;
          final hasBlocked = blocked.isNotEmpty;
          final headerCount = hasBlocked ? 1 : 0;
          final itemCount = folders.length + headerCount;

          if (itemCount == 0) {
            return const Center(child: Text('没有本地音乐文件夹'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 160),
            itemCount: itemCount,
            separatorBuilder: (context, index) {
              if (hasBlocked && index == 0) return const SizedBox.shrink();
              return const Divider(height: 1);
            },
            itemBuilder: (context, index) {
              if (hasBlocked && index == 0) {
                return BlockedFoldersEntryCard(
                  blockListKey: 'blocked_folders',
                  blocked: blocked.toList(),
                  onChanged: _loadFolders,
                );
              }

              final folder = folders[index - headerCount];
              return SourceTile(
                icon: Icons.folder,
                title: folder.name,
                subtitle: '${folder.count} 首歌曲',
                actions: [],
                onLongPress: () {
                  showBlockFolderSheet(
                    context,
                    blockListKey: 'blocked_folders',
                    folderId: folder.id,
                    folderName: folder.name,
                    onBlocked: _loadFolders,
                  );
                },
                onTap: () {
                  Navigator.push(
                    context,
                    buildAppPageRoute(
                      (_) => FolderSongsPage(
                        title: folder.name,
                        sourceId: 'local',
                        folderPath: folder.id,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
