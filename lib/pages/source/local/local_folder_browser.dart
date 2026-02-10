import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

import '../../../app/services/block_list_service.dart';
import '../../../app/services/db/dao/song_dao.dart';
import '../../../components/common/blocked_management_sheet.dart';
import '../../../components/index.dart';
import '../folder_info.dart';
import '../folder_songs_page.dart';
import '../local_source_settings_page.dart';

class LocalFolderBrowser extends StatefulWidget {
  const LocalFolderBrowser({super.key});

  @override
  State<LocalFolderBrowser> createState() => _LocalFolderBrowserState();
}

class _LocalFolderBrowserState extends State<LocalFolderBrowser> with SignalsMixin {
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
      return FolderInfo(
        id: path,
        name: name,
        count: e.value,
      );
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
                MaterialPageRoute(builder: (_) => const LocalSourceSettingsPage()),
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
                final theme = Theme.of(context);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: 64,
                    child: Material(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => BlockedManagementSheet(
                              title: '已屏蔽文件夹',
                              items: blocked.toList(),
                              onUnblock: (item) async {
                                await BlockListService.instance.remove('blocked_folders', item);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  _loadFolders();
                                }
                              },
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            const SizedBox(width: 16),
                            Icon(Icons.folder_off, color: theme.colorScheme.error),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('已屏蔽的文件夹')),
                            Text('${blocked.length} 个'),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right_rounded),
                            const SizedBox(width: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }
              
              final folder = folders[index - headerCount];
              return SourceTile(
                icon: Icons.folder,
                title: folder.name,
                subtitle: '${folder.count} 首歌曲',
                actions: [],
                onLongPress: () {
                  final pageContext = context;
                  showModalBottomSheet(
                    context: pageContext,
                    backgroundColor: Colors.transparent,
                    builder: (sheetContext) {
                      return AppSheetPanel(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.folder_off, color: Colors.red),
                              title: const Text('屏蔽此文件夹'),
                              titleTextStyle: TextStyle(
                                color: Theme.of(sheetContext).colorScheme.error,
                              ),
                              onTap: () async {
                                Navigator.pop(sheetContext);
                                await BlockListService.instance.add('blocked_folders', folder.id);
                                if (!pageContext.mounted) return;
                                AppToast.show(pageContext, '已屏蔽: ${folder.name}');
                                _loadFolders();
                              },
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  );
                },
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FolderSongsPage(
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
