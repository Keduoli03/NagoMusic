import 'bili_api.dart';
import 'bili_models.dart';
import 'bili_music_service.dart';

/// 把 B 站的视频字幕转成 LRC，当作歌词用。
///
/// 思路和油猴脚本「B站字幕提取器」一致：`player/wbi/v2` 列出字幕轨道，轨道里的
/// `subtitle_url` 指向一份 `{body: [{from, to, content}]}` 的 JSON，逐句带时间戳，
/// 结构上和 LRC 是一一对应的。
class BiliSubtitleService {
  static final BiliSubtitleService instance = BiliSubtitleService._();

  BiliSubtitleService._();

  final BiliApi _api = BiliApi.instance;

  /// 挑一条最适合当歌词的轨道。
  ///
  /// 排序依据：AI 摘要排到最后（那是一整段总结，不是逐句字幕，做歌词毫无意义）；
  /// UP 主自己上传的优先于 AI 生成的；同等条件下中文优先。
  static BiliSubtitleTrack? pickBest(List<BiliSubtitleTrack> tracks) {
    if (tracks.isEmpty) return null;
    final sorted = [...tracks]
      ..sort((a, b) {
        if (a.isSummary != b.isSummary) return a.isSummary ? 1 : -1;
        if (a.isAiGenerated != b.isAiGenerated) return a.isAiGenerated ? 1 : -1;
        if (a.isChinese != b.isChinese) return a.isChinese ? -1 : 1;
        return 0;
      });
    // 全是摘要的话就没有能用的轨道了。
    final first = sorted.first;
    return first.isSummary ? null : first;
  }

  /// 把字幕逐句转成 LRC 文本。
  ///
  /// 结尾补一条空行标记最后一句的结束时间，否则最后一句会在播放器上一直高亮到
  /// 音频结束。
  static String toLrc(List<BiliSubtitleLine> lines) {
    if (lines.isEmpty) return '';
    final buffer = StringBuffer();
    for (final line in lines) {
      buffer.writeln('[${formatTimestamp(line.from)}]${line.content}');
    }
    final last = lines.last;
    if (last.to > last.from) {
      buffer.writeln('[${formatTimestamp(last.to)}]');
    }
    return buffer.toString();
  }

  /// 秒 → `mm:ss.xx`。
  ///
  /// 有声书动辄一小时以上，分钟数会超过 99 —— LRC 没有小时位，就让分钟继续往上加
  /// （`[123:45.60]`），这是各家播放器通行的处理方式。
  static String formatTimestamp(double seconds) {
    final total = seconds < 0 ? 0.0 : seconds;
    final minutes = total ~/ 60;
    final secs = (total % 60).floor();
    final hundredths = (((total - total.floor()) * 100).round()).clamp(0, 99);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}.'
        '${hundredths.toString().padLeft(2, '0')}';
  }

  /// 给一首 B 站曲目取字幕并转成 LRC。没有可用字幕时返回 null。
  Future<String?> fetchLrc(String songId) async {
    final parsed = BiliMusicService.parseSongId(songId);
    if (parsed == null) return null;
    final tracks = await _api.subtitleTracks(bvid: parsed.$1, cid: parsed.$2);
    final best = pickBest(tracks);
    if (best == null) return null;
    final lines = await _api.subtitleLines(best.url);
    if (lines.isEmpty) return null;
    return toLrc(lines);
  }

  /// 列出可选轨道，供「手动选字幕」的 UI 用。
  Future<List<BiliSubtitleTrack>> tracksFor(String songId) async {
    final parsed = BiliMusicService.parseSongId(songId);
    if (parsed == null) return const [];
    return _api.subtitleTracks(bvid: parsed.$1, cid: parsed.$2);
  }

  Future<String?> lrcForTrack(BiliSubtitleTrack track) async {
    final lines = await _api.subtitleLines(track.url);
    if (lines.isEmpty) return null;
    return toLrc(lines);
  }
}
