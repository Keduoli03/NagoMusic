import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals.dart';

import '../../app/router/app_router.dart';
import '../../app/router/app_page_route.dart';
import '../../app/services/bili/bili_collection_service.dart';
import '../../app/services/bili/bili_music_service.dart';
import '../../app/services/player_service.dart';

import '../../app/state/song_state.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_radii.dart';
import '../../app/theme/app_spacing.dart';
import '../../components/index.dart';
import 'bili_fav_folder_page.dart';
import 'bili_playback.dart';
import 'bili_profile_page.dart';
import 'bili_recent_page.dart';
import 'widgets/bili_collection_poster_card.dart';

/// 底部导航第 3 项「B站」。
///
/// 版式对齐首页：透明顶栏 + 单层 ListView + 16px 页边距 + 28px 分节间距。
/// 主体依次是本地收藏、B站收藏夹和最近播放，搜索收进右上角，账号放左上角。
class BiliPage extends StatefulWidget {
  const BiliPage({super.key});

  @override
  State<BiliPage> createState() => _BiliPageState();
}

class _BiliPageState extends State<BiliPage> {
  final BiliApi _api = BiliApi.instance;
  final BiliMusicService _music = BiliMusicService.instance;
  final BiliCollectionService _collections = BiliCollectionService.instance;
  final PlayerService _player = PlayerService.instance;

  BiliAccount _account = const BiliAccount();
  List<SongEntity> _recent = const [];
  bool _loadingRecent = true;
  bool _loadingCollections = true;
  EffectCleanup? _songSub;

  List<BiliFavFolder> _folders = const [];
  Set<int> _visibleFolders = const {};
  bool _loadingFolders = false;
  String _folderError = '';

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _loadRecent();
    _loadVisibleFolders();
    _loadCollections();
    // 播到新的一首就刷新最近播放，否则播完回到这一页看到的还是旧列表。
    _songSub = _player.currentSongSignal.subscribe(_handleSongChanged);
  }

  @override
  void dispose() {
    _songSub?.call();
    super.dispose();
  }

  void _handleSongChanged(SongEntity? song) {
    if (song == null || !BiliMusicService.isBiliSong(song)) return;
    _loadRecent();
  }

  // ------------------------------------------------------------------ 数据

  Future<void> _loadAccount() async {
    final stored = await BiliCookieRepository.instance.load();
    if (mounted) setState(() => _account = stored);
    if (!stored.isLoggedIn) return;
    await _loadFolders();
    try {
      final refreshed = await _api.refreshAccount();
      if (mounted) setState(() => _account = refreshed);
    } catch (_) {
      // 网络不通时保留本地登录态，不要误判成掉线。
    }
  }

  Future<void> _loadRecent() async {
    final songs = await _music.recentlyPlayed(limit: 4);
    if (!mounted) return;
    setState(() {
      _recent = songs;
      _loadingRecent = false;
    });
  }

  Future<void> _loadCollections() async {
    await _collections.ensureLoaded();
    if (mounted) setState(() => _loadingCollections = false);
  }

  Future<void> _loadVisibleFolders() async {
    final visible = await BiliPrefs.visibleFolderIds();
    if (!mounted) return;
    setState(() => _visibleFolders = visible);
  }

  Future<void> _loadFolders() async {
    if (!_account.isLoggedIn) return;
    setState(() {
      _loadingFolders = true;
      _folderError = '';
    });
    try {
      final folders = await _api.favFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loadingFolders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFolders = false;
        _folderError = e is BiliApiException ? e.message : '加载失败：$e';
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadRecent(), if (_account.isLoggedIn) _loadFolders()]);
  }

  // ------------------------------------------------------------------ 动作

  Future<void> _login() async {
    final result = await Navigator.pushNamed(context, AppRoutes.biliLogin);
    if (result is BiliAccount && mounted) {
      setState(() {
        _account = result;
        _folders = const [];
        _folderError = '';
      });
      _loadFolders();
    }
  }

  void _openSearch() => Navigator.pushNamed(context, AppRoutes.biliSearch);

  void _openRecentHistory() =>
      Navigator.pushNamed(context, AppRoutes.biliRecent);

  void _openCollections() =>
      Navigator.pushNamed(context, AppRoutes.biliCollections);

  void _openFolder(BiliFavFolder folder) {
    Navigator.of(
      context,
    ).push(buildAppPageRoute((_) => BiliFavFolderPage(folder: folder)));
  }

  /// 进个人主页。回来时如果账号变了（登录/退出）就重新拉一遍。
  Future<void> _openProfile() async {
    final changed = await Navigator.pushNamed(context, AppRoutes.biliProfile);
    if (!mounted) return;
    if (changed == true) {
      setState(() {
        _folders = const [];
        _folderError = '';
      });
    }
    await _loadAccount();
    // 收藏夹的显示筛选可能被改过，无论账号是否变化都要重读。
    await _loadVisibleFolders();
  }

  Future<void> _playRecent(int index) async {
    await _player.playQueue(_recent, index);
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return AppNavigationModeBuilder(
      builder: (context, useBottomNavigation) {
        final bottomPadding = AppPageScaffold.scrollableBottomPadding(
          context,
          hasBottomNav: useBottomNavigation,
        );
        return AppPageScaffold(
          extendBodyBehindAppBar: true,
          appBar: AppTopBar(
            // 标题位直接放「头像 + 用户名」：顶栏已经写着 B站 tab 被选中了，
            // 再写一遍 “B站” 是重复信息，位置留给账号更有用。
            titleWidget: BiliAccountChip(
              account: _account,
              onTap: _openProfile,
            ),
            showBackButton: false,
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              IconButton(
                tooltip: '搜索',
                icon: const Icon(AppIcons.search),
                onPressed: _openSearch,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
              children: [
                _buildCollectionsSection(),
                AppSpacing.gapXl,
                _buildFoldersSection(),
                AppSpacing.gapXl,
                _buildRecentSection(),
              ],
            ),
          ),
          bottomNavIndex: useBottomNavigation ? 2 : null,
          onBottomNavTap: useBottomNavigation
              ? (index) => navigateToPrimaryDestination(context, index)
              : null,
        );
      },
    );
  }

  Widget _sectionHeader(String title, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '最近播放',
          trailing: TextButton(
            onPressed: _openRecentHistory,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('查看更多'),
          ),
        ),
        const SizedBox(height: 10),
        if (_loadingRecent)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_recent.isEmpty)
          _emptyPanel('还没有听过 B 站的内容，右上角搜一个试试')
        else
          Column(
            children: [
              for (var i = 0; i < _recent.length; i++)
                BiliSongRow(song: _recent[i], onTap: () => _playRecent(i)),
            ],
          ),
      ],
    );
  }

  Widget _buildFoldersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'B站收藏夹',
          trailing: !_account.isLoggedIn
              ? null
              : SoftIconButton(
                  icon: AppIcons.refresh,
                  tooltip: '刷新',
                  onTap: _loadFolders,
                  size: 34,
                  iconSize: 19,
                  radius: AppRadii.card,
                ),
        ),
        const SizedBox(height: 10),
        if (!_account.isLoggedIn)
          _emptyPanel('登录后可以直接查看 B 站收藏夹', action: ('登录', _login))
        else if (_loadingFolders)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_folderError.isNotEmpty)
          _emptyPanel(_folderError, action: ('重试', _loadFolders))
        else if (_folders.isEmpty)
          _emptyPanel('还没有收藏夹', action: ('刷新', _loadFolders))
        else
          AppSettingSection(
            children: [
              for (final folder in BiliPrefs.filterFolders(
                _folders,
                _visibleFolders,
                (f) => f.id,
              ))
                AppSettingTile(
                  title: folder.title,
                  subtitle: '${folder.mediaCount} 个视频',
                  leading: _folderIcon(),
                  trailing: const Icon(AppIcons.chevronRight),
                  onTap: () => _openFolder(folder),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildCollectionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          '最近收藏',
          trailing: TextButton(
            onPressed: _openCollections,
            child: const Text('查看全部'),
          ),
        ),
        AppSpacing.gapMd,
        ValueListenableBuilder<List<BiliVideoCollection>>(
          valueListenable: _collections.collections,
          builder: (context, collections, _) {
            if (_loadingCollections) {
              return SizedBox(
                height: BiliCollectionPosterCard.heightFor(context),
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            if (collections.isEmpty) {
              return _emptyPanel('还没有收藏视频，右上角搜索后点收藏即可添加');
            }
            return SizedBox(
              height: BiliCollectionPosterCard.heightFor(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: collections.length,
                separatorBuilder: (context, index) => AppSpacing.wGapSm,
                itemBuilder: (context, index) {
                  final collection = collections[index];
                  return BiliCollectionPosterCard(
                    key: ValueKey(collection.video.bvid),
                    collection: collection,
                    onTap: () =>
                        BiliPlayback.openCollection(context, collection),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _folderIcon() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Icon(AppIcons.folderFavorite, size: 20, color: scheme.primary),
    );
  }

  Widget _emptyPanel(String message, {(String, VoidCallback)? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.panel),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.of(context).muted),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            FilledButton.tonal(onPressed: action.$2, child: Text(action.$1)),
          ],
        ],
      ),
    );
  }
}
