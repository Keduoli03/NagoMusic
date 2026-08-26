import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../log/log.dart';

/// api.vkeys.cn 的 QQ 音乐接口客户端（v2）。
///
/// 只包两个端点：
/// - `/v2/music/tencent`        关键词搜索，返回歌名 / 歌手 / 专辑 / 封面
/// - `/v2/music/tencent/lyric`  按 id 或 mid 取歌词
///
/// 刻意**不碰**点歌（`choose` / `id` 直接取 `url`）那条路径 —— 那返回的是带时效
/// vkey 的音频直链，属于下载音源，不是这个功能要的东西。这里只做元数据补全。
///
/// 文档：https://doc.vkeys.cn/v2/音乐模块/QQ音乐/1-tencent.html
class VkeysMusicApi {
  static const String _logTag = 'VkeysMusicApi';

  static const String baseUrl = 'https://api.vkeys.cn';
  static const String _searchPath = '/v2/music/tencent';
  static const String _lyricPath = '/v2/music/tencent/lyric';

  VkeysMusicApi._();

  static final VkeysMusicApi instance = VkeysMusicApi._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  );

  /// 按关键词搜索。[num] 上限 60（接口约束）。
  ///
  /// 网络错误和非 200 业务码都返回空列表并落日志 —— 调用方是搜索界面，"没搜到"
  /// 和"接口挂了"在 UI 上都是同一个空态，不值得往上抛。
  Future<List<VkeysSong>> search(
    String word, {
    int page = 1,
    int num = 20,
  }) async {
    final keyword = word.trim();
    if (keyword.isEmpty) return const [];

    try {
      final response = await _dio.get<dynamic>(
        _searchPath,
        queryParameters: {
          'word': keyword,
          'page': page < 1 ? 1 : page,
          'num': num.clamp(1, 60),
        },
      );
      final data = _unwrap(response.data, context: 'search');
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => VkeysSong.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.isUsable)
          .toList();
    } catch (e, s) {
      AppLog.instance.w(_logTag, '搜索失败 word=$keyword', e, s);
      return const [];
    }
  }

  /// 按 [id] 或 [mid] 取歌词，两者给一个即可。
  Future<VkeysLyrics?> fetchLyrics({int? id, String? mid}) async {
    final hasMid = (mid ?? '').trim().isNotEmpty;
    if (id == null && !hasMid) return null;

    try {
      final response = await _dio.get<dynamic>(
        _lyricPath,
        queryParameters: hasMid ? {'mid': mid!.trim()} : {'id': id},
      );
      final data = _unwrap(response.data, context: 'lyric');
      if (data is! Map) return null;
      final lyrics = VkeysLyrics.fromJson(data.cast<String, dynamic>());
      return lyrics.isEmpty ? null : lyrics;
    } catch (e, s) {
      AppLog.instance.w(_logTag, '获取歌词失败 id=$id mid=$mid', e, s);
      return null;
    }
  }

  /// 下载封面图原始字节。返回 null 表示这张封面拿不到，调用方跳过换封面即可。
  Future<Uint8List?> fetchCover(String url) async {
    final target = url.trim();
    if (target.isEmpty) return null;
    try {
      final response = await _dio.get<List<int>>(
        target,
        options: Options(
          responseType: ResponseType.bytes,
          // 封面是绝对 URL（y.qq.com），不能拼在 baseUrl 后面。
          followRedirects: true,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '下载封面失败 url=$target', e, s);
      return null;
    }
  }

  /// 校验统一响应壳（`code` / `message` / `data`）并取出 `data`。
  Object? _unwrap(dynamic body, {required String context}) {
    if (body is! Map) return null;
    final code = body['code'];
    if (code is int && code != 200) {
      AppLog.instance.w(
        _logTag,
        '$context 返回业务错误 code=$code message=${body['message']}',
      );
      return null;
    }
    return body['data'];
  }
}

/// 搜索结果里的一首歌。
class VkeysSong {
  final int? id;
  final String mid;
  final String song;
  final String singer;
  final String album;
  final String cover;

  /// 发行日期，如 `2010-06-21`。
  final String releaseDate;

  /// 时长文案，如 `3分36秒`。接口不给毫秒数，所以只当展示用，不写进歌曲时长。
  final String interval;

  /// 同名多版本（不同专辑 / 现场版等）。展开后当作平级结果展示。
  final List<VkeysSong> variants;

  const VkeysSong({
    required this.id,
    required this.mid,
    required this.song,
    required this.singer,
    required this.album,
    required this.cover,
    required this.releaseDate,
    required this.interval,
    this.variants = const [],
  });

  /// 没有歌名、或者 id/mid 都没有的条目取不了歌词，直接丢掉。
  bool get isUsable =>
      song.trim().isNotEmpty && (id != null || mid.trim().isNotEmpty);

  factory VkeysSong.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] ?? '').toString().trim();

    final rawVariants = json['grp'];
    return VkeysSong(
      id: json['id'] is int ? json['id'] as int : int.tryParse(text('id')),
      mid: text('mid'),
      song: text('song'),
      singer: text('singer'),
      album: text('album'),
      cover: text('cover'),
      releaseDate: text('time'),
      interval: text('interval'),
      variants: rawVariants is List
          ? rawVariants
                .whereType<Map>()
                .map((e) => VkeysSong.fromJson(e.cast<String, dynamic>()))
                .where((e) => e.isUsable)
                .toList()
          : const [],
    );
  }
}

/// 歌词接口返回的四种形态。
class VkeysLyrics {
  /// 逐行 LRC，`[mm:ss.xx]` 时间戳。
  final String lrc;

  /// 翻译，时间戳与 [lrc] 对齐。
  final String trans;

  /// 逐字歌词，`[起始,时长]字(偏移,时长)` 格式。
  final String yrc;

  /// 音译（罗马音），同样是逐字格式。
  final String roma;

  const VkeysLyrics({
    required this.lrc,
    required this.trans,
    required this.yrc,
    required this.roma,
  });

  bool get isEmpty => lrc.trim().isEmpty;
  bool get hasTranslation => trans.trim().isNotEmpty;

  factory VkeysLyrics.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] ?? '').toString();
    return VkeysLyrics(
      lrc: text('lrc'),
      trans: text('trans'),
      yrc: text('yrc'),
      roma: text('roma'),
    );
  }

  /// 拼成一份可直接交给 `LyricsParser` 的 LRC 文本。
  ///
  /// 翻译直接接在正文后面，不做配对 —— 解析器本来就会把**同一时间戳**的第二行
  /// 认成翻译并合并进同一行（见 `LyricsParser` 的 same-time 合并），而这个接口的
  /// trans 时间戳和 lrc 是对齐的，正好走那条路径。
  ///
  /// [includeTranslation] 为 false 时只返回正文，给"我只要原文"的场景。
  String toLrc({bool includeTranslation = true}) {
    final main = lrc.trim();
    if (!includeTranslation || trans.trim().isEmpty) return main;
    return '$main\n${trans.trim()}';
  }
}
