import 'package:flutter/material.dart';

import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../app/theme/app_surfaces.dart';
import '../../app/theme/tokens.dart';
import '../../components/index.dart';
import '../songs/song_detail_sheet.dart';

enum SearchCategory {
  all('综合'),
  song('歌曲'),
  album('专辑'),
  artist('歌手'),
  lyric('歌词');

  const SearchCategory(this.label);

  final String label;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final SongDao _songDao = SongDao();
  final LyricsRepository _lyricsRepo = LyricsRepository();
  final PlayerService _player = PlayerService.instance;
  SearchCategory _category = SearchCategory.all;
  String _query = '';
  List<SongEntity> _allSongs = [];
  List<SongEntity> _results = [];
  bool _loading = true;
  bool _searchingLyrics = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    final list = await _songDao.fetchAllCached();
    if (!mounted) return;
    setState(() {
      _allSongs = list;
      _loading = false;
    });
    _runSearch();
  }

  void _runSearch() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searchingLyrics = false;
      });
      return;
    }
    if (_category == SearchCategory.lyric || _category == SearchCategory.all) {
      _searchWithLyrics(q);
    } else {
      final list = _filterSimple(q);
      setState(() {
        _results = list;
        _searchingLyrics = false;
      });
    }
  }

  List<SongEntity> _filterSimple(String q) {
    bool contains(String? value) {
      return value != null && value.toLowerCase().contains(q);
    }

    return _allSongs.where((song) {
      switch (_category) {
        case SearchCategory.all:
          return contains(song.title) ||
              contains(song.artist) ||
              contains(song.album);
        case SearchCategory.song:
          return contains(song.title);
        case SearchCategory.album:
          return contains(song.album);
        case SearchCategory.artist:
          return contains(song.artist);
        case SearchCategory.lyric:
          return false;
      }
    }).toList();
  }

  Future<void> _searchWithLyrics(String q) async {
    final token = ++_searchToken;
    setState(() {
      _searchingLyrics = true;
    });
    final base = _category == SearchCategory.all
        ? _filterSimple(q)
        : <SongEntity>[];
    final baseIds = base.map((e) => e.id).toSet();
    final lyricMatches = <SongEntity>[];
    for (final song in _allSongs) {
      if (token != _searchToken) return;
      if (baseIds.contains(song.id)) continue;
      final lrc = await _lyricsRepo.loadCachedLrc(song.id);
      if (lrc == null || lrc.isEmpty) continue;
      if (lrc.toLowerCase().contains(q)) {
        lyricMatches.add(song);
      }
    }
    if (!mounted || token != _searchToken) return;
    setState(() {
      _results = _category == SearchCategory.all
          ? [...base, ...lyricMatches]
          : lyricMatches;
      _searchingLyrics = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      // 不再 extendBodyBehindAppBar：搜索框现在就在顶栏里，内容从顶栏下面开始，
      // 省掉原来那个写死的 48px 顶部补偿。背景由 AppBackground 在更外层铺满，
      // 不开这个也不会露白。
      resizeToAvoidBottomInset: false,
      appBar: AppTopBar(
        // 搜索框直接当标题用，省掉「顶栏 + 下面再一条输入框」的两行占位。
        titleWidget: AppSearchField(
          controller: _controller,
          hintText: '搜索歌曲、歌手、专辑、歌词',
          onChanged: (value) {
            setState(() => _query = value);
            _runSearch();
          },
          onClear: () {
            setState(() => _query = '');
            _runSearch();
          },
          onSubmitted: (_) => _submit(),
        ),
        // 0 而不是默认的 16：返回箭头本身已经占了 56 宽，再加缩进搜索框就被挤窄了。
        titleSpacing: 0,
        actions: [_buildSubmitButton(context)],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategoryBar(context),
                Expanded(child: _buildResults(context)),
              ],
            ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    _runSearch();
  }

  Widget _buildSubmitButton(BuildContext context) {
    return TextButton(
      onPressed: _submit,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        padding: AppSpacing.hMd,
      ),
      child: Text(
        '搜索',
        style: AppTypography.bodyLg.on(Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _buildCategoryBar(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: AppSpacing.page,
      child: Row(
        children: [
          for (final category in SearchCategory.values)
            _CategoryChip(
              label: category.label,
              selected: _category == category,
              onTap: () {
                setState(() => _category = category);
                _runSearch();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _query.trim().isEmpty
              ? '请输入关键字进行搜索'
              : _searchingLyrics
              ? '正在搜索歌词...'
              : '没有匹配的结果',
          style: AppTypography.body.on(AppColors.of(context).muted),
        ),
      );
    }
    return ListView.builder(
      padding: AppSpacing.listBottom(
        AppPageScaffold.scrollableBottomPadding(context),
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final song = _results[index];
        return ListTile(
          leading: ArtworkWidget(
            song: song,
            size: 44,
            borderRadius: AppRadii.chip,
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLg,
          ),
          subtitle: Text(
            '${song.artist}'
            '${song.album != null && song.album!.isNotEmpty ? ' · ${song.album}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption,
          ),
          onTap: () {
            if ((song.uri ?? '').trim().isEmpty) return;
            _player.playQueue(_results, index);
          },
          onLongPress: () {
            showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => SongDetailSheet(song: song),
            );
          },
        );
      },
    );
  }
}

/// 分类筛选胶囊。
///
/// 原来用的是 [ChoiceChip]，它自带的内边距和 48 高触摸目标让这一排比结果列表
/// 的行还高。这里用裸 InkWell 手搓，高度压到 30。
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = AppColors.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: selected ? scheme.primary : theme.appPanelColor,
        borderRadius: AppRadii.rPill,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.rPill,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            child: Text(
              label,
              style: AppTypography.meta
                  .on(selected ? scheme.onPrimary : c.muted)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}
