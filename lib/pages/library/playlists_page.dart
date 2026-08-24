import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/app_icons.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/playlists_service.dart';
import '../../app/router/app_page_route.dart';
import '../../app/utils/deferred_page_init_mixin.dart';
import '../../components/index.dart';
import 'playlist_detail_page.dart';
import 'playlist_name_dialog.dart';
import 'playlists_actions_controller.dart';
import 'playlists_sort_controller.dart';

class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage>
    with SignalsMixin, DeferredPageInitMixin {
  final PlaylistsActionsController _actionsController =
      PlaylistsActionsController();
  final PlaylistsSortController _sortController = PlaylistsSortController();
  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();

  late final _loading = createSignal(true);
  late final _playlists = createSignal<List<PlaylistEntity>>([]);
  late final _sortMode = createSignal('custom');
  late final _ascending = createSignal(true);
  List<PlaylistEntity> _allPlaylists = [];

  @override
  void initState() {
    super.initState();
    scheduleDeferredInit();
  }

  @override
  Future<void> runDeferredInit() async {
    await _init();
  }

  Future<void> _init() async {
    await _loadPrefs();
    await _load();
  }

  Future<void> _loadPrefs() async {
    final prefs = await _sortController.loadPrefs();
    _sortMode.value = prefs.sortMode;
    _ascending.value = prefs.ascending;
  }

  Future<void> _savePrefs() async {
    await _sortController.savePrefs(
      sortMode: _sortMode.value,
      ascending: _ascending.value,
    );
  }

  Future<void> _load() async {
    _loading.value = true;
    final playlists = await _sortController.loadPlaylists();
    if (!mounted) return;
    _allPlaylists = playlists;
    _applySortFromBase();
    _loading.value = false;
  }

  void _applySortFromBase() {
    _playlists.value = PlaylistsSortController.sortPlaylists(
      playlists: _allPlaylists,
      sortMode: _sortMode.value,
      ascending: _ascending.value,
    );
  }

  Future<void> _createPlaylist() async {
    await showPlaylistNameDialog(
      context,
      title: '新建歌单',
      initial: '',
      confirmText: '创建',
      fallbackName: '新建歌单',
      onSubmit: (name) async {
        await _actionsController.createPlaylist(name);
        if (!mounted) return;
        AppToast.show(context, '已创建歌单');
        await _load();
      },
    );
  }

  Future<void> _renamePlaylist(PlaylistEntity playlist) async {
    await showPlaylistNameDialog(
      context,
      title: '重命名歌单',
      initial: playlist.name,
      confirmText: '保存',
      fallbackName: null,
      onSubmit: (name) async {
        await _actionsController.renamePlaylist(playlist.id, name);
        if (!mounted) return;
        AppToast.show(context, '已重命名');
        await _load();
      },
    );
  }

  Future<void> _deletePlaylist(PlaylistEntity playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: '删除歌单',
        contentText: '确定删除「${playlist.name}」吗？',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (confirmed != true) return;
    await _actionsController.deletePlaylist(playlist.id);
    if (!mounted) return;
    AppToast.show(context, '已删除');
    await _load();
  }

  void _showPlaylistSheet(PlaylistEntity playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return AppSheetPanel(
          title: playlist.name,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!playlist.isFavorite)
                AppListTile(
                  leading: const Icon(AppIcons.arrowUp),
                  title: '置顶',
                  onTap: () {
                    Navigator.of(context).pop();
                    _pinPlaylist(playlist);
                  },
                ),
              AppListTile(
                leading: const Icon(AppIcons.pencil),
                title: '重命名',
                onTap: () {
                  Navigator.of(context).pop();
                  _renamePlaylist(playlist);
                },
              ),
              if (!playlist.isFavorite)
                AppListTile(
                  leading: const Icon(AppIcons.trash, color: Colors.red),
                  title: '删除',
                  titleColor: Colors.red,
                  onTap: () {
                    Navigator.of(context).pop();
                    _deletePlaylist(playlist);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pinPlaylist(PlaylistEntity playlist) async {
    await _actionsController.pinToTop(playlist.id);
    if (!mounted) return;
    _sortMode.value = 'custom';
    await _savePrefs();
    await _load();
  }

  Future<void> _reorderPlaylists(int oldIndex, int newIndex) async {
    if (_sortMode.value != 'custom') {
      AppToast.show(context, '切换到自定义排序后可拖拽');
      return;
    }
    final list = PlaylistsActionsController.reorderList(
      current: _allPlaylists,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
    if (list == null) return;
    _allPlaylists = list;
    _playlists.value = list;
    await _actionsController.reorderPlaylists(list);
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SortSheet(
          title: '歌单排序',
          options: const [
            SortOption(
              key: 'custom',
              label: '自定义拖拽',
              icon: AppIcons.dragHandle,
            ),
            SortOption(key: 'recent', label: '创建时间', icon: AppIcons.clock),
            SortOption(key: 'name', label: '名称', icon: AppIcons.sort),
            SortOption(key: 'count', label: '歌曲数量', icon: AppIcons.queue),
          ],
          currentKey: _sortMode.value,
          ascending: _ascending.value,
          onSelectKey: (value) {
            _sortMode.value = value;
            _applySortFromBase();
            _savePrefs();
          },
          onSelectAscending: (value) {
            _ascending.value = value;
            _applySortFromBase();
            _savePrefs();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) => AppPageScaffold(
        key: _scaffoldKey,
        extendBodyBehindAppBar: true,
        appBar: AppTopBar(
          title: '歌单',
          // 歌单不再是底栏一级页（那一格换成了 B站），现在统一由「我的」推进来，
          // 所以底栏模式下也要有返回键。侧栏模式仍然用汉堡键打开抽屉。
          showBackButton: true,
          leading: useBottomNavigation
              ? null
              : IconButton(
                  icon: const Icon(AppIcons.menu),
                  onPressed: _openDrawer,
                ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            SortActionButton(onTap: _showSortSheet),
            IconButton(
              tooltip: '新建歌单',
              icon: const Icon(AppIcons.add),
              onPressed: _createPlaylist,
            ),
            const SizedBox(width: 8),
          ],
        ),
        drawer: useBottomNavigation
            ? null
            : SideMenu(
                onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
              ),
        // 歌单从底栏一级页降级成「我的」里的入口后，跟专辑 / 艺术家一样保留底栏，
        // 只是选中项归 0 —— 它自己已经不占底栏的格子了。
        bottomNavIndex: useBottomNavigation ? 0 : null,
        onBottomNavTap: useBottomNavigation
            ? (index) => navigateToPrimaryDestination(context, index)
            : null,
        body: Watch.builder(
          builder: (context) => RefreshIndicator(
            onRefresh: _load,
            child: _loading.value
                ? const Center(child: CircularProgressIndicator())
                : _playlists.value.isEmpty
                ? const Center(child: Text('暂无歌单'))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 160),
                    itemCount: _playlists.value.length,
                    buildDefaultDragHandles: false,
                    onReorder: _reorderPlaylists,
                    itemBuilder: (context, index) {
                      final p = _playlists.value[index];
                      final isFavorite = p.isFavorite;
                      final canReorder =
                          _sortMode.value == 'custom' && !isFavorite;
                      return Column(
                        key: ValueKey(p.id),
                        children: [
                          ListTile(
                            leading: Icon(
                              isFavorite
                                  ? AppIconsFilled.heart
                                  : AppIcons.queue,
                              color: isFavorite ? Colors.red : null,
                            ),
                            title: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('${p.songIds.length} 首歌曲'),
                            trailing: canReorder
                                ? ReorderableDragStartListener(
                                    index: index,
                                    child: const Icon(AppIcons.dragHandle),
                                  )
                                : null,
                            onTap: () async {
                              await Navigator.of(context).push(
                                buildAppPageRoute(
                                  (_) => PlaylistDetailPage(playlistId: p.id),
                                ),
                              );
                              if (!mounted) return;
                              await _load();
                            },
                            onLongPress: () => _showPlaylistSheet(p),
                          ),
                          if (index != _playlists.value.length - 1)
                            const Divider(height: 1),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
