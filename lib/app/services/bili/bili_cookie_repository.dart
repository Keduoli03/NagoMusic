import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// B 站登录态。cookie 里真正有用的就这几项：
/// - `SESSDATA` 决定能不能拿到高码率音频（未登录只有 64k/132k）
/// - `bili_jct` 是写操作的 csrf token
/// - `DedeUserID` 是 mid，拉收藏夹要用
/// - [anon] 是**没登录也必须带**的风控 cookie（buvid3 / buvid4 / b_nut）。
///   只带 buvid3 不够：搜索接口会返回一个 `v_voucher` 挑战、结果为空。
class BiliAccount {
  final String sessData;
  final String biliJct;
  final String mid;
  final Map<String, String> anon;
  final String uname;
  final String face;
  final int vipStatus;

  const BiliAccount({
    this.sessData = '',
    this.biliJct = '',
    this.mid = '',
    this.anon = const {},
    this.uname = '',
    this.face = '',
    this.vipStatus = 0,
  });

  bool get isLoggedIn => sessData.isNotEmpty;

  bool get isVip => vipStatus > 0;

  /// 拼成可以直接塞进 `Cookie:` 请求头的字符串。
  String get cookieHeader {
    final parts = <String>[];
    if (sessData.isNotEmpty) parts.add('SESSDATA=$sessData');
    if (biliJct.isNotEmpty) parts.add('bili_jct=$biliJct');
    if (mid.isNotEmpty) parts.add('DedeUserID=$mid');
    anon.forEach((key, value) => parts.add('$key=$value'));
    return parts.join('; ');
  }

  BiliAccount copyWith({
    String? sessData,
    String? biliJct,
    String? mid,
    Map<String, String>? anon,
    String? uname,
    String? face,
    int? vipStatus,
  }) {
    return BiliAccount(
      sessData: sessData ?? this.sessData,
      biliJct: biliJct ?? this.biliJct,
      mid: mid ?? this.mid,
      anon: anon ?? this.anon,
      uname: uname ?? this.uname,
      face: face ?? this.face,
      vipStatus: vipStatus ?? this.vipStatus,
    );
  }

  Map<String, dynamic> toJson() => {
    'sessData': sessData,
    'biliJct': biliJct,
    'mid': mid,
    'anon': anon,
    'uname': uname,
    'face': face,
    'vipStatus': vipStatus,
  };

  factory BiliAccount.fromJson(Map<String, dynamic> json) {
    final rawAnon = json['anon'];
    return BiliAccount(
      sessData: (json['sessData'] ?? '').toString(),
      biliJct: (json['biliJct'] ?? '').toString(),
      mid: (json['mid'] ?? '').toString(),
      anon: rawAnon is Map
          ? rawAnon.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      uname: (json['uname'] ?? '').toString(),
      face: (json['face'] ?? '').toString(),
      vipStatus: (json['vipStatus'] as num?)?.toInt() ?? 0,
    );
  }
}

class BiliCookieRepository {
  static final BiliCookieRepository instance = BiliCookieRepository._();

  BiliCookieRepository._();

  static const String _prefsKey = 'bili_account_v1';

  BiliAccount? _cached;

  Future<BiliAccount> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return _cached = const BiliAccount();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _cached = BiliAccount.fromJson(decoded);
      }
    } catch (_) {
      // 存坏了就当没登录，下一次登录会覆盖掉。
    }
    return _cached = const BiliAccount();
  }

  /// 同步读当前登录态。仅供已经 [load] 过之后的 UI 快速取值使用。
  BiliAccount get current => _cached ?? const BiliAccount();

  Future<void> save(BiliAccount account) async {
    _cached = account;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(account.toJson()));
  }

  Future<void> clear() async {
    _cached = const BiliAccount();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
