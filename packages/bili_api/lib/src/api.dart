import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'cookie_repository.dart';
import 'models.dart';
import 'playurl_parser.dart';

/// B 站 Web 接口封装。
///
/// 参考简音（qianqianhhh2/jianyin）的 `bili-api` 模块，但这里是从零用 Dart 重写的：
/// 只保留播放器需要的搜索 / 分 P / playurl / 收藏夹 / 扫码登录五条链路。
///
/// 两个绕不开的坑：
/// 1. **WBI 签名**：`search/type` 和 `player/playurl` 都在 wbi 网关后面，
///    请求参数必须按规则算出 `w_rid`，否则一律 -403。
/// 2. **风控 cookie**：即使不登录也得先取到 buvid3 并激活，否则搜索接口
///    会一直返回 `v_voucher` 挑战、结果恒为空。见 [ensureBuvid]。
class BiliApi {
  static final BiliApi instance = BiliApi._();

  BiliApi._();

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';
  static const String referer = 'https://www.bilibili.com';

  /// WBI mixin key 的字符重排表，来自 B 站前端脚本，写死即可。
  static const List<int> _mixinKeyEncTab = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, //
    27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
    22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
  ];

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 20),
      // 由调用方按 code 判断成功与否，HTTP 状态码一律放行以便读到 body。
      validateStatus: (_) => true,
      responseType: ResponseType.json,
    ),
  );

  final BiliCookieRepository _cookies = BiliCookieRepository.instance;

  String? _mixinKey;
  DateTime? _mixinKeyAt;

  // ---------------------------------------------------------------- 基础设施

  Future<Map<String, String>> _headers() async {
    final account = await _cookies.load();
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Referer': referer,
      'Origin': referer,
      'Accept': 'application/json, text/plain, */*',
    };
    final cookie = account.cookieHeader;
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  /// 播放音频流时要带的请求头。**必须**有 Referer，否则 CDN 返回 403。
  Future<Map<String, String>> streamHeaders() async {
    final account = await _cookies.load();
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Referer': referer,
      'Accept': '*/*',
    };
    final cookie = account.cookieHeader;
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  /// 解包 `{code, message, data}`，code != 0 时抛 [BiliApiException]。
  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final body = response.data;
    final map = body is Map<String, dynamic>
        ? body
        : (body is String ? jsonDecode(body) as Map<String, dynamic> : null);
    if (map == null) {
      throw BiliApiException(-1, '接口返回异常（HTTP ${response.statusCode}）');
    }
    final code = (map['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      final message = (map['message'] ?? '').toString();
      throw BiliApiException(code, message.isEmpty ? '请求失败（$code）' : message);
    }
    final data = map['data'];
    if (data is Map<String, dynamic>) return data;
    return {'data': data};
  }

  Future<Response<dynamic>> _get(
    String url, {
    Map<String, dynamic>? query,
  }) async {
    return _dio.get<dynamic>(
      url,
      queryParameters: query,
      options: Options(headers: await _headers()),
    );
  }

  // -------------------------------------------------------------- WBI 签名

  /// 拉取并缓存 mixin key。B 站每天换一次 key，这里按天失效。
  Future<String> _ensureMixinKey() async {
    final cached = _mixinKey;
    final at = _mixinKeyAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at).inHours < 6) {
      return cached;
    }
    final response = await _get('https://api.bilibili.com/x/web-interface/nav');
    // 未登录时 nav 会返回 code -101，但 wbi_img 照样在 data 里，所以不能用 _unwrap。
    final body = response.data;
    final map = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final data = map['data'];
    final wbi = data is Map ? data['wbi_img'] : null;
    if (wbi is! Map) {
      throw const BiliApiException(-1, '获取 WBI 密钥失败');
    }
    final imgKey = _keyFromUrl(wbi['img_url']);
    final subKey = _keyFromUrl(wbi['sub_url']);
    final raw = '$imgKey$subKey';
    final buffer = StringBuffer();
    for (final index in _mixinKeyEncTab) {
      if (index < raw.length) buffer.write(raw[index]);
      if (buffer.length == 32) break;
    }
    _mixinKey = buffer.toString();
    _mixinKeyAt = DateTime.now();
    return _mixinKey!;
  }

  /// `https://i0.hdslb.com/bfs/wbi/<key>.png` → `<key>`
  static String _keyFromUrl(Object? raw) {
    final url = (raw ?? '').toString();
    final slash = url.lastIndexOf('/');
    final name = slash >= 0 ? url.substring(slash + 1) : url;
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(0, dot) : name;
  }

  /// 给 [params] 补上 `wts` 和 `w_rid`。
  Future<Map<String, dynamic>> _signWbi(Map<String, dynamic> params) async {
    final mixinKey = await _ensureMixinKey();
    final wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signed = <String, dynamic>{...params, 'wts': wts};
    final keys = signed.keys.toList()..sort();
    final query = keys
        .map((key) {
          // 参数值里的 !'()* 必须先去掉，这是签名规则的一部分。
          final value = signed[key].toString().replaceAll(
            RegExp(r"[!'()*]"),
            '',
          );
          return '${Uri.encodeQueryComponent(key)}='
              '${Uri.encodeQueryComponent(value)}';
        })
        .join('&');
    signed['w_rid'] = md5.convert(utf8.encode('$query$mixinKey')).toString();
    return signed;
  }

  // ------------------------------------------------------------- 风控 / 账号

  /// 确保本地有整套匿名风控 cookie。
  ///
  /// 只调 `finger/spi` 拿 buvid3 是不够的 —— 搜索接口会返回
  /// `{code: 0, data: {v_voucher: ...}}`（风控挑战），结果恒为空。必须先像浏览器
  /// 那样访问一次主页，把 `buvid3` / `buvid4` / `b_nut` 一起收下，再调一次
  /// gaia 网关做激活。
  Future<void> ensureBuvid() async {
    final account = await _cookies.load();
    if (account.anon.containsKey('buvid3')) return;

    final anon = <String, String>{};
    try {
      final home = await _dio.get<dynamic>(
        'https://www.bilibili.com/',
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': userAgent,
            'Accept':
                'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        ),
      );
      anon.addAll(_parseSetCookie(home.headers.map['set-cookie']));
    } catch (_) {
      // 主页拿不到就退回指纹接口。
    }
    if (!anon.containsKey('buvid3')) {
      try {
        final data = _unwrap(
          await _get('https://api.bilibili.com/x/frontend/finger/spi'),
        );
        final b3 = (data['b_3'] ?? '').toString();
        final b4 = (data['b_4'] ?? '').toString();
        if (b3.isNotEmpty) anon['buvid3'] = b3;
        if (b4.isNotEmpty) anon['buvid4'] = b4;
      } catch (_) {
        // 两条路都失败就先放着，搜索会报错让用户重试。
      }
    }
    if (anon.isEmpty) return;
    // 只留风控真正看的几项，别把主页下发的一堆统计 cookie 都存下来。
    anon.removeWhere(
      (key, _) => !const {'buvid3', 'buvid4', 'b_nut', '_uuid'}.contains(key),
    );
    await _cookies.save(account.copyWith(anon: anon));
    await _activateBuvid();
  }

  /// gaia 网关的「激活」调用。B 站前端在首屏会打这一发，把 buvid 标成正常浏览器
  /// 产生的；不打的话新 buvid 在搜索接口上仍然会吃到 v_voucher 挑战。
  Future<void> _activateBuvid() async {
    try {
      await _dio.post<dynamic>(
        'https://api.bilibili.com/x/internal/gaia-gateway/ExClimbWuzhi',
        data: {
          '3064': 1,
          '5062': '${DateTime.now().millisecondsSinceEpoch}',
          '03bf': 'https://www.bilibili.com/',
          '39c8': '333.1007.fp.risk',
          '34f1': '',
          'd402': '',
          '654a': '',
          '6e7c': '1920x1080',
          '3c43': {'adca': 'Win32', 'bfe9': ''},
        },
        options: Options(
          headers: {...await _headers(), 'Content-Type': 'application/json'},
        ),
      );
    } catch (_) {
      // 激活失败不阻断流程。
    }
  }

  /// 校验当前 cookie 是否还有效，顺便刷新昵称 / 头像 / 大会员状态。
  Future<BiliAccount> refreshAccount() async {
    final account = await _cookies.load();
    if (!account.isLoggedIn) return account;
    final response = await _get('https://api.bilibili.com/x/web-interface/nav');
    final body = response.data;
    final map = body is Map<String, dynamic> ? body : <String, dynamic>{};
    final data = map['data'];
    if (data is! Map || data['isLogin'] != true) {
      // cookie 过期：清掉登录态但保留风控 cookie，免得又触发挑战。
      final cleared = BiliAccount(anon: account.anon);
      await _cookies.save(cleared);
      return cleared;
    }
    final vip = data['vipStatus'] ?? data['vip_status'];
    final updated = account.copyWith(
      uname: (data['uname'] ?? '').toString(),
      face: BiliVideo.normalizeCover(data['face']),
      mid: (data['mid'] ?? account.mid).toString(),
      vipStatus: (vip as num?)?.toInt() ?? 0,
    );
    await _cookies.save(updated);
    return updated;
  }

  // ---------------------------------------------------------------- 扫码登录

  /// 返回 `(二维码内容, qrcode_key)`。
  Future<(String, String)> generateQrCode() async {
    final response = await _get(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
    );
    final data = _unwrap(response);
    return (
      (data['url'] ?? '').toString(),
      (data['qrcode_key'] ?? '').toString(),
    );
  }

  Future<BiliQrPollResult> pollQrCode(String qrcodeKey) async {
    final response = await _get(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
      query: {'qrcode_key': qrcodeKey},
    );
    final data = _unwrap(response);
    final code = (data['code'] as num?)?.toInt() ?? -1;
    switch (code) {
      case 86101:
        return const BiliQrPollResult(
          status: BiliQrStatus.waiting,
          message: '请使用哔哩哔哩客户端扫码',
        );
      case 86090:
        return const BiliQrPollResult(
          status: BiliQrStatus.scanned,
          message: '已扫码，请在手机上确认',
        );
      case 86038:
        return const BiliQrPollResult(
          status: BiliQrStatus.expired,
          message: '二维码已失效，请刷新',
        );
      case 0:
        return BiliQrPollResult(
          status: BiliQrStatus.confirmed,
          message: '登录成功',
          cookies: _parseSetCookie(response.headers.map['set-cookie']),
        );
      default:
        return BiliQrPollResult(
          status: BiliQrStatus.expired,
          message: (data['message'] ?? '登录失败（$code）').toString(),
        );
    }
  }

  static Map<String, String> _parseSetCookie(List<String>? raw) {
    final result = <String, String>{};
    for (final line in raw ?? const <String>[]) {
      final pair = line.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      result[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return result;
  }

  /// 把扫码拿到的 cookie 落盘，并立刻拉一次用户资料。
  Future<BiliAccount> saveLoginCookies(Map<String, String> cookies) async {
    final account = await _cookies.load();
    final updated = account.copyWith(
      sessData: cookies['SESSDATA'] ?? account.sessData,
      biliJct: cookies['bili_jct'] ?? account.biliJct,
      mid: cookies['DedeUserID'] ?? account.mid,
    );
    await _cookies.save(updated);
    return refreshAccount();
  }

  Future<void> logout() => _cookies.clear();

  // ------------------------------------------------------------------ 搜索

  /// 搜索每页条数。调用方靠「返回条数 < 这个值」判断到底了，所以它必须是公开的，
  /// 不能只写在 query 里。
  static const int searchPageSize = 30;

  Future<List<BiliVideo>> searchVideos(String keyword, {int page = 1}) async {
    await ensureBuvid();
    // 新拿到的 buvid 头几次请求会被风控挑一下：返回 `{code: 0, data: {v_voucher}}`，
    // result 字段整个缺失。挑过之后就正常了，所以必须重试 —— 不然用户看到的是
    // 「搜不到任何东西」。中间留点间隔，紧挨着重试仍然会吃挑战。
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
      }
      final query = await _signWbi({
        'search_type': 'video',
        'keyword': keyword,
        'page': page,
        'page_size': searchPageSize,
      });
      final data = _unwrap(
        await _get(
          'https://api.bilibili.com/x/web-interface/wbi/search/type',
          query: query,
        ),
      );
      final result = data['result'];
      if (result is List) {
        return result
            .whereType<Map<String, dynamic>>()
            .map(BiliVideo.fromSearchJson)
            .where((video) => video.bvid.isNotEmpty)
            .toList();
      }
      if (data['v_voucher'] == null) return const [];
    }
    throw const BiliApiException(-412, '请求被 B 站风控拦截，请稍后重试');
  }

  // -------------------------------------------------------------- 视频 / 分 P

  Future<BiliVideoDetail> videoDetail(String bvid) async {
    final response = await _get(
      'https://api.bilibili.com/x/web-interface/view',
      query: {'bvid': bvid},
    );
    final data = _unwrap(response);
    final owner = data['owner'];
    final video = BiliVideo(
      bvid: (data['bvid'] ?? bvid).toString(),
      aid: (data['aid'] as num?)?.toInt() ?? 0,
      title: BiliVideo.stripHighlight(data['title']),
      author: owner is Map ? (owner['name'] ?? '').toString() : '',
      cover: BiliVideo.normalizeCover(data['pic']),
      durationSec: (data['duration'] as num?)?.toInt() ?? 0,
    );
    final rawPages = data['pages'];
    final parts = rawPages is List
        ? rawPages
              .whereType<Map<String, dynamic>>()
              .map(BiliPart.fromJson)
              .where((part) => part.cid != 0)
              .toList()
        : <BiliPart>[];
    return BiliVideoDetail(video: video, parts: parts);
  }

  /// 取某个分 P 的全部音频流，已按「越靠前越好」排好序。
  Future<List<BiliAudioStream>> audioStreams({
    required String bvid,
    required int cid,
  }) async {
    await ensureBuvid();
    // fnval=4048 一次性要 dash + 杜比 + 无损；fourk 不影响音频但缺了会降级。
    final query = await _signWbi({
      'bvid': bvid,
      'cid': cid,
      'fnval': 4048,
      'fourk': 1,
    });
    final response = await _get(
      'https://api.bilibili.com/x/player/wbi/playurl',
      query: query,
    );
    // 解析在 playurl_parser.dart 里，纯函数、可测。DASH 与 durl 两种响应形态
    // 的处理都在那边，包括老视频只给合流 durl 的情况。
    return parsePlayurlAudioStreams(_unwrap(response));
  }

  // ------------------------------------------------------------------- 字幕

  /// 列出某个分 P 的全部字幕轨道。
  ///
  /// **必须登录**：`player/wbi/v2` 对未登录请求返回的 subtitles 恒为空数组，
  /// 不会报错，所以调用方拿到空列表时要提示去登录，而不是「这个视频没字幕」。
  Future<List<BiliSubtitleTrack>> subtitleTracks({
    required String bvid,
    required int cid,
  }) async {
    await ensureBuvid();
    final query = await _signWbi({'bvid': bvid, 'cid': cid});
    final data = _unwrap(
      await _get('https://api.bilibili.com/x/player/wbi/v2', query: query),
    );
    final subtitle = data['subtitle'];
    final list = subtitle is Map ? subtitle['subtitles'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BiliSubtitleTrack.fromJson)
        .where((track) => track.url.isNotEmpty)
        .toList();
  }

  /// 拉取一条字幕轨道的正文。
  Future<List<BiliSubtitleLine>> subtitleLines(String url) async {
    if (url.isEmpty) return const [];
    final response = await _dio.get<dynamic>(
      url,
      options: Options(
        // 字幕 JSON 在 aisubtitle.hdslb.com 上，跟 API 网关不同源，
        // 带上 API 的 Cookie 没用，但 Referer 仍然要。
        headers: {'User-Agent': userAgent, 'Referer': referer},
      ),
    );
    final body = response.data;
    final map = body is Map
        ? body
        : (body is String ? jsonDecode(body) as Map : const {});
    final lines = map['body'];
    if (lines is! List) return const [];
    return lines
        .whereType<Map<String, dynamic>>()
        .map(BiliSubtitleLine.fromJson)
        .where((line) => line.content.isNotEmpty)
        .toList();
  }

  // ----------------------------------------------------------------- 收藏夹

  Future<List<BiliFavFolder>> favFolders() async {
    final account = await _cookies.load();
    if (!account.isLoggedIn || account.mid.isEmpty) {
      throw const BiliApiException(-101, '请先登录 B 站账号');
    }
    final response = await _get(
      'https://api.bilibili.com/x/v3/fav/folder/created/list-all',
      query: {'up_mid': account.mid},
    );
    final data = _unwrap(response);
    final list = data['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BiliFavFolder.fromJson)
        .toList();
  }

  /// 拉一整个收藏夹的内容，自动翻页。
  Future<List<BiliVideo>> favResources(int mediaId, {int maxPages = 50}) async {
    final result = <BiliVideo>[];
    for (var page = 1; page <= maxPages; page++) {
      final response = await _get(
        'https://api.bilibili.com/x/v3/fav/resource/list',
        query: {'media_id': mediaId, 'pn': page, 'ps': 20, 'platform': 'web'},
      );
      final data = _unwrap(response);
      final medias = data['medias'];
      if (medias is! List || medias.isEmpty) break;
      result.addAll(
        medias
            .whereType<Map<String, dynamic>>()
            // attr 非 0 表示已失效 / 已被 UP 删除，同步进来也播不了。
            .where((json) => ((json['attr'] as num?)?.toInt() ?? 0) == 0)
            .map(BiliVideo.fromFavJson)
            .where((video) => video.bvid.isNotEmpty),
      );
      if (data['has_more'] != true) break;
    }
    return result;
  }
}
