import 'package:flutter/material.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/lyrics/lyrics_repository.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/index.dart';
import '../songs/song_detail_sheet.dart';

enum SearchCategory {
  all,
  song,
  album,
  artist,
  lyric,
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
    final base = _category == SearchCategory.all ? _filterSimple(q) : <SongEntity>[];
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
      _results = _category == SearchCategory.all ? [...base, ...lyricMatches] : lyricMatches;
      _searchingLyrics = false;
    });
  }

  Widget _buildCategoryChip(SearchCategory category, String label) {
    final selected = _category == category;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedColor = theme.colorScheme.primary;
    final selectedTextColor = Colors.white;
    final unselectedBg =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(230, 255, 255, 255);
    final unselectedText =
        isDark ? Colors.white70 : const Color.fromARGB(255, 80, 80, 80);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? selectedTextColor : unselectedText,
          ),
        ),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _category = category;
          });
          _runSearch();
        },
        showCheckmark: false,
        selectedColor: selectedColor,
        backgroundColor: unselectedBg,
        pressElevation: 0,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const topBarHeight = 48.0;
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      keepBottomOverlayFixed: true,
      ignoreKeyboardInsets: true,
      appBar: AppTopBar(
        title: '搜索',
        backgroundColor: Colors.transparent,
        elevation: 0,
        showBackButton: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(top: topBarHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _controller,
                      autofocus: false,
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                        });
                        _runSearch();
                      },
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '搜索',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _query = '';
                                    _controller.clear();
                                  });
                                  _runSearch();
                                },
                              ),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1F2329)
                            : const Color.fromARGB(242, 255, 255, 255),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(20)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _runSearch(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildCategoryChip(SearchCategory.all, '综合'),
                          _buildCategoryChip(SearchCategory.song, '歌曲'),
                          _buildCategoryChip(SearchCategory.album, '专辑'),
                          _buildCategoryChip(SearchCategory.artist, '歌手'),
                          _buildCategoryChip(SearchCategory.lyric, '歌词'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: _results.isEmpty
                        ? Center(
                            child: Text(
                              _query.trim().isEmpty
                                  ? '请输入关键字进行搜索'
                                  : _searchingLyrics
                                      ? '正在搜索歌词...'
                                      : '没有匹配的结果',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white70
                                    : const Color.fromARGB(255, 110, 110, 110),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: EdgeInsets.only(
                              bottom: AppPageScaffold.scrollableBottomPadding(
                                context,
                                showMiniPlayer: true,
                              ),
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final song = _results[index];
                              return ListTile(
                                leading: ArtworkWidget(
                                  song: song,
                                  size: 48,
                                  borderRadius: 6,
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${song.artist}'
                                  '${song.album != null && song.album!.isNotEmpty ? ' · ${song.album}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
