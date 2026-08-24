import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/playlists_service.dart';
import '../../components/index.dart';
import 'playlist_name_dialog.dart';
import 'playlists_actions_controller.dart';

class PlaylistPickerSheet extends StatefulWidget {
  final List<String> songIds;

  const PlaylistPickerSheet({super.key, required this.songIds});

  @override
  State<PlaylistPickerSheet> createState() => _PlaylistPickerSheetState();
}

class _PlaylistPickerSheetState extends State<PlaylistPickerSheet>
    with SignalsMixin {
  final PlaylistsService _service = PlaylistsService.instance;
  final PlaylistsActionsController _actionsController =
      PlaylistsActionsController();

  late final _loading = createSignal(true);
  late final _playlists = createSignal<List<PlaylistEntity>>([]);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _loading.value = true;
    final playlists = await _service.loadAll();
    if (!mounted) return;
    _playlists.value = playlists;
    _loading.value = false;
  }

  Future<void> _createAndAdd() async {
    await showPlaylistNameDialog(
      context,
      title: '新建歌单',
      initial: '',
      confirmText: '创建',
      fallbackName: '新建歌单',
      onSubmit: (name) async {
        final created = await _actionsController.createPlaylist(name);
        await _actionsController.addSongs(created.id, widget.songIds);
        if (!mounted) return;
        AppToast.show(context, '已收藏到歌单');
        Future.delayed(const Duration(milliseconds: 80), () {
          if (!mounted) return;
          Navigator.of(context).pop(true);
        });
      },
    );
  }

  Future<void> _addToPlaylist(PlaylistEntity playlist) async {
    await _actionsController.addSongs(playlist.id, widget.songIds);
    if (!mounted) return;
    AppToast.show(context, '已收藏到歌单');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetPanel(
      title: '选择歌单',
      expand: true,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      child: Watch.builder(
        builder: (context) => _loading.value
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('新建歌单'),
                    onTap: _createAndAdd,
                  ),
                  const Divider(height: 1),
                  if (_playlists.value.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('暂无歌单')),
                    )
                  else
                    ..._playlists.value.map(
                      (p) => ListTile(
                        leading: Icon(
                          p.isFavorite
                              ? Icons.favorite
                              : Icons.queue_music_rounded,
                          color: p.isFavorite ? Colors.red : null,
                        ),
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${p.songIds.length} 首歌曲'),
                        onTap: () => _addToPlaylist(p),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

Future<bool> showAddToPlaylistDialog(
  BuildContext context, {
  required List<String> songIds,
}) async {
  final ids = songIds.where((e) => e.trim().isNotEmpty).toList();
  if (ids.isEmpty) return false;

  final service = PlaylistsService.instance;
  final actionsController = PlaylistsActionsController(service: service);
  final playlists = await service.loadAll();
  if (!context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AppDialog(
        title: '添加到歌单',
        confirmText: '新建歌单',
        onConfirm: () {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!context.mounted) return;
            showPlaylistNameDialog(
              context,
              title: '新建歌单',
              initial: '',
              confirmText: '创建',
              fallbackName: '新建歌单',
              onSubmit: (name) async {
                final created = await actionsController.createPlaylist(name);
                await actionsController.addSongs(created.id, ids);
                if (!context.mounted) return;
                AppToast.show(context, '已添加到歌单: ${created.name}');
              },
            );
          });
        },
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: playlists.isEmpty
              ? const Center(
                  child: Text('暂无歌单', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return AppListTile(
                      leading: Icon(
                        playlist.isFavorite
                            ? Icons.favorite
                            : Icons.queue_music,
                        color: playlist.isFavorite
                            ? Colors.red
                            : Theme.of(
                                context,
                              ).iconTheme.color?.withValues(alpha: 0.7),
                      ),
                      title: playlist.name,
                      subtitle: '${playlist.songIds.length} 首',
                      onTap: () async {
                        await actionsController.addSongs(playlist.id, ids);
                        if (!context.mounted) return;
                        Navigator.pop(dialogContext, true);
                        AppToast.show(context, '已添加到歌单: ${playlist.name}');
                      },
                    );
                  },
                ),
        ),
      );
    },
  );
  return result == true;
}
