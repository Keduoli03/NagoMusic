import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:signals/signals_flutter.dart';

import '../../../app/services/block_list_service.dart';
import '../../../app/services/db/dao/song_dao.dart';
import '../../../app/services/webdav/webdav_source_repository.dart';
import '../../../components/common/blocked_management_sheet.dart';
import '../../../components/index.dart';
import '../folder_info.dart';
import '../folder_songs_page.dart';
import 'webdav_edit_page.dart';

class WebDavFolderBrowser extends StatefulWidget {
  final String sourceId;
  final String sourceName;

  const WebDavFolderBrowser({
    super.key,
    required this.sourceId,
    required this.sourceName,
  });

  @override
  State<WebDavFolderBrowser> createState() => _WebDavFolderBrowserState();
}

class _WebDavFolderBrowserState extends State<WebDavFolderBrowser> with SignalsMixin {
  final SongDao _songDao = SongDao();
  final WebDavSourceRepository _repo = WebDavSourceRepository.instance;
  
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
    final songs = await _songDao.fetchAll(sourceId: widget.sourceId);
    final blockedKey = 'blocked_folders_${widget.sourceId}';
    final blocked = await BlockListService.instance.load(blockedKey);
    
    if (mounted) {
      _blockedFolders.value = blocked;
    }
    
    final Map<String, int> folderCounts = {};
    
    for (final song in songs) {
      if (song.uri == null) continue;
      // WebDAV paths might be URLs or absolute paths.
      // We group by parent directory.
      var dir = p.dirname(song.uri!).replaceAll('\\', '/');
      
      // Basic normalization to avoid trailing slashes if any (dirname usually handles it)
      if (dir.endsWith('/') && dir.length > 1) {
        dir = dir.substring(0, dir.length - 1);
      }

      if (blocked.contains(dir)) continue;
      
      folderCounts[dir] = (folderCounts[dir] ?? 0) + 1;
    }

    final List<FolderInfo> list = folderCounts.entries.map((e) {
      final path = e.key;
      // Use basename for display, or full path if it's root
      var name = p.basename(path);
      if (name.isEmpty) name = path;
      if (name.isEmpty) name = '/';
      
      // If it looks like a URL, we might want to decode it
      try {
        name = Uri.decodeComponent(name);
      } catch (_) {}

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

  Future<void> _openSettings() async {
    final sources = await _repo.loadSources();
    try {
      final source = sources.firstWhere((s) => s.id == widget.sourceId);
      if (!mounted) return;
      
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => WebDavEditPage(source: source),
        ),
      );
      if (!mounted) return;
      if (changed == true) {
        _loadFolders();
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '无法加载设置');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: widget.sourceName,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
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
            return const Center(child: Text('此源没有歌曲或文件夹'));
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
                                final blockedKey = 'blocked_folders_${widget.sourceId}';
                                await BlockListService.instance.remove(blockedKey, item);
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
                icon: Icons.folder_open, // Different icon for WebDAV maybe?
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
                                final blockedKey = 'blocked_folders_${widget.sourceId}';
                                await BlockListService.instance.add(blockedKey, folder.id);
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
                        sourceId: widget.sourceId,
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
