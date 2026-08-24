/// B 站接口返回值的最小建模 —— 只留播放器真正用得上的字段。
library;

/// 搜索结果 / 收藏夹条目共用的「一个视频」。
class BiliVideo {
  final String bvid;
  final int aid;
  final String title;
  final String author;
  final String cover;

  /// 视频总时长（秒）。搜索接口给的是 "mm:ss" 字符串，这里统一成秒。
  final int durationSec;

  /// 分 P 数量。收藏夹接口直接给，搜索接口给不了，取 0 表示未知。
  final int partCount;

  const BiliVideo({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.author,
    required this.cover,
    this.durationSec = 0,
    this.partCount = 0,
  });

  static int parseDuration(Object? raw) {
    if (raw is num) return raw.toInt();
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return 0;
    final parts = text.split(':');
    var seconds = 0;
    for (final part in parts) {
      seconds = seconds * 60 + (int.tryParse(part.trim()) ?? 0);
    }
    return seconds;
  }

  /// 搜索接口的 title 带 `<em class="keyword">` 高亮标签，得剥掉。
  static String stripHighlight(Object? raw) {
    return (raw ?? '')
        .toString()
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  /// B 站的图片地址经常是 `//i2.hdslb.com/...`，补上协议才能直接加载。
  static String normalizeCover(Object? raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return '';
    if (text.startsWith('//')) return 'https:$text';
    return text;
  }

  factory BiliVideo.fromSearchJson(Map<String, dynamic> json) {
    return BiliVideo(
      bvid: (json['bvid'] ?? '').toString(),
      aid: (json['aid'] as num?)?.toInt() ?? 0,
      title: stripHighlight(json['title']),
      author: (json['author'] ?? '').toString(),
      cover: normalizeCover(json['pic']),
      durationSec: parseDuration(json['duration']),
    );
  }

  factory BiliVideo.fromFavJson(Map<String, dynamic> json) {
    final upper = json['upper'];
    return BiliVideo(
      bvid: (json['bvid'] ?? '').toString(),
      aid: (json['id'] as num?)?.toInt() ?? 0,
      title: stripHighlight(json['title']),
      author: upper is Map ? (upper['name'] ?? '').toString() : '',
      cover: normalizeCover(json['cover']),
      durationSec: parseDuration(json['duration']),
      partCount: (json['page'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一个分 P。单 P 视频也会有一条，`part` 通常等于视频标题。
class BiliPart {
  final int cid;
  final int index;
  final String title;
  final int durationSec;

  const BiliPart({
    required this.cid,
    required this.index,
    required this.title,
    required this.durationSec,
  });

  factory BiliPart.fromJson(Map<String, dynamic> json) {
    return BiliPart(
      cid: (json['cid'] as num?)?.toInt() ?? 0,
      index: (json['page'] as num?)?.toInt() ?? 1,
      title: (json['part'] ?? '').toString(),
      durationSec: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 视频详情：标题 / UP 主 / 封面 + 分 P 列表。
class BiliVideoDetail {
  final BiliVideo video;
  final List<BiliPart> parts;

  const BiliVideoDetail({required this.video, required this.parts});
}

/// dash 里的一路音频流。
class BiliAudioStream {
  final int id;
  final String url;
  final List<String> backupUrls;
  final int bandwidth;
  final String codecs;

  const BiliAudioStream({
    required this.id,
    required this.url,
    required this.backupUrls,
    required this.bandwidth,
    required this.codecs,
  });

  factory BiliAudioStream.fromJson(Map<String, dynamic> json) {
    final backup = json['backupUrl'] ?? json['backup_url'];
    return BiliAudioStream(
      id: (json['id'] as num?)?.toInt() ?? 0,
      url: (json['baseUrl'] ?? json['base_url'] ?? '').toString(),
      backupUrls: backup is List
          ? backup.map((e) => e.toString()).toList()
          : const <String>[],
      bandwidth: (json['bandwidth'] as num?)?.toInt() ?? 0,
      codecs: (json['codecs'] ?? '').toString(),
    );
  }

  /// 码率标签，用来在 UI 上标「无损」「杜比」等。
  String get qualityLabel => switch (id) {
    30251 => 'Hi-Res',
    30250 => '杜比全景声',
    30280 => '192K',
    30232 => '132K',
    30216 => '64K',
    _ => bandwidth > 0 ? '${(bandwidth / 1000).round()}K' : '',
  };
}

/// 收藏夹。
class BiliFavFolder {
  final int id;
  final String title;
  final int mediaCount;

  const BiliFavFolder({
    required this.id,
    required this.title,
    required this.mediaCount,
  });

  factory BiliFavFolder.fromJson(Map<String, dynamic> json) {
    return BiliFavFolder(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      mediaCount: (json['media_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 一条字幕轨道。B 站一个视频可能同时有 UP 上传的字幕、AI 生成的字幕和 AI 摘要。
class BiliSubtitleTrack {
  final int id;

  /// 语言代码，例如 `zh-CN` / `ai-zh`。
  final String lan;

  /// 给人看的语言名，例如「中文（自动生成）」。
  final String label;

  /// 字幕 JSON 地址。接口给的常是 `//aisubtitle.hdslb.com/...`，已补好协议。
  final String url;

  const BiliSubtitleTrack({
    required this.id,
    required this.lan,
    required this.label,
    required this.url,
  });

  /// AI 摘要不是逐句字幕，拿来当歌词会很怪，得能识别出来排到最后。
  bool get isSummary => label.contains('摘要') || lan.contains('summary');

  bool get isAiGenerated => label.contains('AI') || lan.startsWith('ai-');

  bool get isChinese => lan.contains('zh') || label.contains('中文');

  factory BiliSubtitleTrack.fromJson(Map<String, dynamic> json) {
    final rawUrl =
        json['subtitle_url'] ??
        json['url'] ??
        json['content_url'] ??
        json['caption_url'] ??
        '';
    return BiliSubtitleTrack(
      id: (json['id'] as num?)?.toInt() ?? 0,
      lan: (json['lan'] ?? '').toString(),
      label: (json['lan_doc'] ?? json['lan'] ?? '').toString(),
      url: BiliVideo.normalizeCover(rawUrl),
    );
  }
}

/// 字幕里的一句：`from`/`to` 是秒（带小数）。
class BiliSubtitleLine {
  final double from;
  final double to;
  final String content;

  const BiliSubtitleLine({
    required this.from,
    required this.to,
    required this.content,
  });

  factory BiliSubtitleLine.fromJson(Map<String, dynamic> json) {
    return BiliSubtitleLine(
      from: (json['from'] as num?)?.toDouble() ?? 0,
      to: (json['to'] as num?)?.toDouble() ?? 0,
      content: (json['content'] ?? '').toString().trim(),
    );
  }
}

/// 二维码轮询的四种状态。
enum BiliQrStatus { waiting, scanned, confirmed, expired }

class BiliQrPollResult {
  final BiliQrStatus status;
  final String message;

  /// 仅 [BiliQrStatus.confirmed] 时非空。
  final Map<String, String> cookies;

  const BiliQrPollResult({
    required this.status,
    this.message = '',
    this.cookies = const {},
  });
}

/// 接口返回 code != 0 时抛这个，UI 直接展示 [message]。
class BiliApiException implements Exception {
  final int code;
  final String message;

  const BiliApiException(this.code, this.message);

  @override
  String toString() => 'BiliApiException($code): $message';
}
