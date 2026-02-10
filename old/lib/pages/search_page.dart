import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals/signals_flutter.dart';

import '../models/music_entity.dart';
import '../viewmodels/library_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import '../widgets/artwork_widget.dart';
import '../widgets/song_detail_sheet.dart';

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
  SearchCategory _category = SearchCategory.all;
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _glow({
    required Alignment alignment,
    required double size,
    required List<Color> colors,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  List<MusicEntity> _filterSongs(List<MusicEntity> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      return [];
    }
    bool contains(String? value) {
      return value != null && value.toLowerCase().contains(q);
    }

    return all.where((song) {
      switch (_category) {
        case SearchCategory.all:
          return contains(song.title) ||
              contains(song.artist) ||
              contains(song.album) ||
              contains(song.lyrics);
        case SearchCategory.song:
          return contains(song.title);
        case SearchCategory.album:
          return contains(song.album);
        case SearchCategory.artist:
          return contains(song.artist);
        case SearchCategory.lyric:
          return contains(song.lyrics);
      }
    }).toList();
  }

  Widget _buildCategoryChip(SearchCategory category, String label) {
    final selected = _category == category;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedColor =
        isDark ? theme.colorScheme.primary : theme.colorScheme.primary;
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
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.scanTick);
      final playerVM = PlayerViewModel();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final background = isDark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1C1F24),
                Color(0xFF22262C),
                Color(0xFF1B1D22),
              ],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF6F7FB),
                Color(0xFFF7F3E8),
                Color(0xFFF1F7F4),
              ],
            );

      final results = _filterSongs(vm.songs);

      return Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        extendBody: true,
        bottomNavigationBar: null,
        appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      body: Container(
        decoration: BoxDecoration(gradient: background),
        child: Stack(
          children: [
            if (!isDark)
              _glow(
                alignment: Alignment.topRight,
                size: 260,
                colors: const [
                  Color(0x66FDE2A7),
                  Color(0x00FDE2A7),
                ],
              ),
            if (!isDark)
              _glow(
                alignment: Alignment.bottomLeft,
                size: 240,
                colors: const [
                  Color(0x66CBE8FF),
                  Color(0x00CBE8FF),
                ],
              ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (value) {
                        setState(() {
                          _query = value;
                        });
                        vm.enqueueLocalSearchMetadata(_query);
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
                                  vm.enqueueLocalSearchMetadata('');
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
                      onSubmitted: (value) {
                        vm.enqueueLocalSearchMetadata(value);
                      },
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    child: results.isEmpty
                        ? Center(
                            child: Text(
                              _query.trim().isEmpty
                                  ? '请输入关键字进行搜索'
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
                              bottom: MediaQuery.of(context).viewInsets.bottom + 80,
                            ),
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final song = results[index];
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
                                  final list = results;
                                  if (song.uri == null) {
                                    return;
                                  }
                                  playerVM.playList(list, initialIndex: index);
                                },
                                onLongPress: () {
                                  SongDetailSheet.show(context, song);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    },);
  }
}
