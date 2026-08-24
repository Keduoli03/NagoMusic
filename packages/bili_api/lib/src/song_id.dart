import 'models.dart';

/// B 站曲目 id 的编解码。
///
/// 从 `BiliMusicService` 拆出来是因为 [BiliSubtitleService]（同在本包里）也要用它 ——
/// 字幕服务和 API/模型层一起搬进了 `bili_api` 包，而 `BiliMusicService` 因为依赖
/// app 侧的 `SongEntity` / `SongDao` 必须留在 app 里。这个文件是纯 id 编解码，
/// 不碰任何 app 侧类型，可以安全地被两边共用（app 里保留同名 static 转发过来）。
class BiliSongId {
  const BiliSongId._();

  static const String _prefix = 'bili::';

  static String buildSongId(String bvid, int cid) => '$_prefix$bvid-$cid';

  /// 曲目 `uri` 里存的占位地址，例如 `bili://BV1xx411c7mD/123456`。
  ///
  /// 不能把真的直链存进去：它带时效签名，几十分钟就失效。但 `uri` 又不能为空 ——
  /// `PlayerService.playQueue` 会把 `uri` 为空的歌全部滤掉，队列直接变空、点了没反应。
  /// 占位地址同时充当音频缓存的键，它稳定，所以缓存不会因为换了直链就失效。
  static String placeholderUri(String songId) {
    final parsed = parseSongId(songId);
    if (parsed == null) return 'bili://$songId';
    return 'bili://${parsed.$1}/${parsed.$2}';
  }

  /// `bili::BV1xx411c7mD-123456` → `('BV1xx411c7mD', 123456)`。
  /// 解不出来返回 null（例如 id 格式被别的迁移改过）。
  static (String, int)? parseSongId(String id) {
    if (!id.startsWith(_prefix)) return null;
    final body = id.substring(_prefix.length);
    final dash = body.lastIndexOf('-');
    if (dash <= 0) return null;
    final bvid = body.substring(0, dash);
    final cid = int.tryParse(body.substring(dash + 1));
    if (bvid.isEmpty || cid == null) return null;
    return (bvid, cid);
  }

  /// 分 P 的显示名。
  ///
  /// 很多合集（有声书、课程）每个分 P 的 `part` 字段就是视频标题本身，直接拿来用
  /// 会得到一整列一模一样的长标题 —— 这种情况退回 `P1 / P2`。
  static String partLabel(String videoTitle, BiliPart part) {
    final raw = part.title.trim();
    if (raw.isEmpty || raw == videoTitle.trim()) return 'P${part.index}';
    return raw;
  }
}
