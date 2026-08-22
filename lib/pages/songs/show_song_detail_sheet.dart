import 'package:flutter/material.dart';

import '../../app/router/app_page_route.dart';
import '../../app/router/app_router.dart';
import '../../app/state/song_state.dart';
import '../library/library_detail_pages.dart';
import 'song_detail_sheet.dart';

/// 打开歌曲详情面板，并统一接好「跳转艺术家 / 专辑」的导航。
///
/// 各调用点此前都要自己重复写一遍 `onOpenArtist` / `onOpenAlbum` 的
/// `Navigator.push`，这里集中处理；页面相关的回调仍可按需传入。
Future<void> showSongDetailSheet(
  BuildContext context, {
  required SongEntity song,
  ValueChanged<SongEntity>? onUpdated,
  ValueChanged<String>? onDeleted,
  bool enablePlayerAppearanceEntry = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => SongDetailSheet(
      song: song,
      onUpdated: onUpdated,
      onDeleted: onDeleted,
      onOpenPlayerAppearanceSettings: enablePlayerAppearanceEntry
          ? () => Navigator.of(context).pushNamed(AppRoutes.playerSettings)
          : null,
      onOpenArtist: (artistName) {
        Navigator.of(context).push(
          buildAppPageRoute((_) => ArtistDetailPage(artistName: artistName)),
        );
      },
      onOpenAlbum: (albumName) {
        Navigator.of(
          context,
        ).push(buildAppPageRoute((_) => AlbumDetailPage(albumName: albumName)));
      },
    ),
  );
}
