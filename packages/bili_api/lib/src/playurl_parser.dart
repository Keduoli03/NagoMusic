import 'models.dart';

/// 把 `x/player/wbi/playurl` 的响应体解析成可播放的音频流列表。
///
/// 抽成纯函数是为了能测：真正的 [BiliApi.audioStreams] 要签 WBI、要发网络请求，
/// 没法在单元测试里覆盖各种响应形态，而这里正是最容易出错的地方。
///
/// B 站的 playurl 有**两种互斥的返回形态**：
///
/// - **DASH**（`data.dash`）：音视频分轨，`dash.audio` 是纯音频流列表，另外
///   Hi-Res 在 `dash.flac.audio`、杜比在 `dash.dolby.audio`，这两个不在
///   `dash.audio` 里，必须单独取。这是绝大多数视频走的路。
/// - **durl**（`data.durl`）：音视频**合流**的 FLV/MP4 整段文件。老视频（以及部分
///   番剧 / 课程）没有 DASH 版本，接口就只给这个，`data.dash` 整个字段都不存在。
///
/// 以前这里碰到没有 `dash` 就直接返回空列表，表现是「取流失败，候选数=0」——
/// 视频明明能在网页上放，App 里却一声不响地放不出来。现在退化到用 durl：
/// ExoPlayer 能从合流文件里解出音轨，代价是会把视频数据一起下下来。
List<BiliAudioStream> parsePlayurlAudioStreams(Map<String, dynamic> data) {
  final dash = data['dash'];
  if (dash is! Map) {
    return _fromDurl(data);
  }

  final streams = <BiliAudioStream>[];

  // Hi-Res 和杜比是独立字段，不在 dash.audio 里，必须单独取。
  final flac = dash['flac'];
  if (flac is Map && flac['audio'] is Map) {
    streams.add(
      BiliAudioStream.fromJson(Map<String, dynamic>.from(flac['audio'] as Map)),
    );
  }
  final dolby = dash['dolby'];
  if (dolby is Map && dolby['audio'] is List) {
    for (final item in dolby['audio'] as List) {
      if (item is Map) {
        streams.add(BiliAudioStream.fromJson(Map<String, dynamic>.from(item)));
      }
    }
  }
  final audio = dash['audio'];
  if (audio is List) {
    for (final item in audio) {
      if (item is Map) {
        streams.add(BiliAudioStream.fromJson(Map<String, dynamic>.from(item)));
      }
    }
  }

  final usable = streams.where((s) => s.url.isNotEmpty).toList();
  // DASH 存在但一路可用音频都没有（分段异常、字段为空）时也退回 durl，
  // 有的放总比放不出来强。
  return usable.isEmpty ? _fromDurl(data) : usable;
}

List<BiliAudioStream> _fromDurl(Map<String, dynamic> data) {
  final durl = data['durl'];
  if (durl is! List || durl.isEmpty) return const [];
  final first = durl.first;
  if (first is! Map) return const [];

  final url = (first['url'] ?? '').toString();
  if (url.isEmpty) return const [];

  final backup = first['backup_url'] ?? first['backupUrl'];
  return [
    BiliAudioStream(
      // durl 没有音质档位的概念。给 0 让它落到 BiliAudioSelector 的兜底权重，
      // 同时 qualityLabel 会算出空串——**这是故意的**：合流文件的码率里混着视频，
      // 拿它当"音质"显示是在骗人，宁可不显示。
      id: 0,
      url: url,
      backupUrls: backup is List
          ? backup.map((e) => e.toString()).toList()
          : const <String>[],
      bandwidth: 0,
      codecs: (data['format'] ?? '').toString(),
    ),
  ];
}
