/// WebDAV 地址的拆解与拼装。
///
/// 存储层里 `WebDavSource.endpoint` 始终是一条完整 URL（`https://host:port/path`）
/// —— 备份、备用地址、歌曲 URI 都依赖它，所以模型不拆字段。协议 / 地址 / 端口 /
/// 路径的分栏只是**编辑页的一层视图**：进页面时把 endpoint 拆开填进各个输入框，
/// 保存时再拼回去。这个文件就是那两个方向的转换。
///
/// 用户只填 `ol.example.com/dav` 时 [WebDavEndpointParts.scheme] 为 null，表示
/// 「协议待定」，由 `WebDavMusicService.resolveEndpoint` 按 [schemeProbeOrder]
/// 逐个试连、把第一个连得通的写回去。
library;

/// 自动探测协议时的尝试顺序。先 https：公网域名基本都上了证书，先试 http 会在
/// 很多反代上吃一个 301 再跳回来，白跑一轮。
const List<String> schemeProbeOrder = ['https', 'http'];

const Map<String, int> _defaultPorts = {'http': 80, 'https': 443};

/// [scheme] 的默认端口；未知协议按 https 算。
int defaultWebDavPort(String scheme) =>
    _defaultPorts[scheme.toLowerCase()] ?? 443;

/// 一条 WebDAV 地址拆成的四段。
class WebDavEndpointParts {
  /// `http` / `https`；null 表示用户没写协议，需要自动探测。
  final String? scheme;

  /// 主机名或 IP，不含端口。IPv6 保留方括号。
  final String host;

  /// null 表示跟随协议默认端口。
  final int? port;

  /// 基础路径，`''` 或以 `/` 开头且不以 `/` 结尾（如 `/dav`）。
  final String path;

  /// URL 里内联的账号密码（`https://user:pass@host`），粘贴整条链接时用得上。
  final String? username;
  final String? password;

  const WebDavEndpointParts({
    this.scheme,
    required this.host,
    this.port,
    this.path = '',
    this.username,
    this.password,
  });

  bool get isEmpty => host.trim().isEmpty;

  /// 端口输入框里要显示的值：没显式写端口时留空，让 hint 提示默认值。
  String get portText => port == null ? '' : '$port';
}

/// 把用户输入的任意形态地址拆成四段。
///
/// 接受 `ol.example.com/dav`、`https://ol.example.com:8443/dav`、
/// `http://user:pass@10.0.0.2:5244/dav/` 等；无法解析时返回 host 为原文的结果，
/// 让上层自己判空。
WebDavEndpointParts parseWebDavEndpoint(String raw) {
  var text = raw.trim();
  // 从别处粘贴常常带上换行和零宽字符，先清掉再解析。
  text = text.replaceAll(RegExp(r'[\s\u200b-\u200f\ufeff]'), '');
  if (text.isEmpty) return const WebDavEndpointParts(host: '');

  String? scheme;
  final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*)://').firstMatch(text);
  if (schemeMatch != null) {
    final found = schemeMatch.group(1)!.toLowerCase();
    // dav:// / davs:// 是某些客户端的写法，映射到实际走的 http(s)。
    scheme = switch (found) {
      'dav' => 'http',
      'davs' => 'https',
      _ => found,
    };
    if (scheme != 'http' && scheme != 'https') scheme = null;
    text = text.substring(schemeMatch.end);
  }

  // userInfo
  String? username;
  String? password;
  final atIndex = text.indexOf('@');
  final firstSlash = text.indexOf('/');
  if (atIndex > 0 && (firstSlash < 0 || atIndex < firstSlash)) {
    final userInfo = text.substring(0, atIndex);
    text = text.substring(atIndex + 1);
    final colon = userInfo.indexOf(':');
    if (colon >= 0) {
      username = Uri.decodeComponent(userInfo.substring(0, colon));
      password = Uri.decodeComponent(userInfo.substring(colon + 1));
    } else {
      username = Uri.decodeComponent(userInfo);
    }
  }

  // host[:port] / path
  var authority = text;
  var path = '';
  final slash = text.indexOf('/');
  if (slash >= 0) {
    authority = text.substring(0, slash);
    path = text.substring(slash);
  }

  String host = authority;
  int? port;
  if (authority.startsWith('[')) {
    // IPv6：`[::1]:8080`
    final close = authority.indexOf(']');
    if (close >= 0) {
      host = authority.substring(0, close + 1);
      final rest = authority.substring(close + 1);
      if (rest.startsWith(':')) port = int.tryParse(rest.substring(1));
    }
  } else {
    final colon = authority.lastIndexOf(':');
    if (colon >= 0) {
      final maybePort = int.tryParse(authority.substring(colon + 1));
      if (maybePort != null) {
        host = authority.substring(0, colon);
        port = maybePort;
      }
    }
  }

  return WebDavEndpointParts(
    scheme: scheme,
    host: host,
    port: port,
    path: normalizeWebDavBasePath(path),
    username: username,
    password: password,
  );
}

/// 基础路径归一：空 → `''`，否则补前导 `/`、去掉结尾 `/`。
///
/// 结尾不留 `/` 是因为拼接时一律写成 `$path/xxx`，两边都带斜杠会拼出 `//`，
/// 部分 WebDAV 服务端（含 OpenList）会对双斜杠返回 404。
String normalizeWebDavBasePath(String raw) {
  var t = raw.trim().replaceAll('\\', '/');
  if (t.isEmpty || t == '/') return '';
  if (!t.startsWith('/')) t = '/$t';
  while (t.length > 1 && t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// 把四段拼回一条完整 URL。端口等于协议默认值时省略不写。
String buildWebDavEndpoint({
  required String scheme,
  required String host,
  int? port,
  String path = '',
}) {
  final h = host.trim();
  if (h.isEmpty) return '';
  final s = scheme.trim().toLowerCase();
  final buffer = StringBuffer('$s://$h');
  if (port != null && port != defaultWebDavPort(s)) {
    buffer.write(':$port');
  }
  buffer.write(normalizeWebDavBasePath(path));
  return buffer.toString();
}

/// 给运行期用的兜底归一：保证返回的地址一定带协议。
///
/// 历史配置、备用地址输入框、备份还原都可能塞进来一条没有协议的地址。真正的
/// 协议探测发生在保存时；这里只是让 Dio 不至于因为缺 scheme 直接抛错。
String normalizeWebDavEndpoint(String raw) {
  final parts = parseWebDavEndpoint(raw);
  if (parts.isEmpty) return '';
  return buildWebDavEndpoint(
    scheme: parts.scheme ?? 'https',
    host: parts.host,
    port: parts.port,
    path: parts.path,
  );
}

/// 一条待探测地址要尝试的候选 URL，按优先级排列。
///
/// 用户写了协议就只有一个候选（尊重用户的选择，连不上就报连不上，不要偷偷换成
/// 另一个协议——内网 http 地址被悄悄换成 https 只会更难排查）。没写协议时按
/// [schemeProbeOrder] 展开。
List<String> webDavEndpointCandidates(String raw, {String? forcedScheme}) {
  final parts = parseWebDavEndpoint(raw);
  if (parts.isEmpty) return const [];

  String build(String scheme) => buildWebDavEndpoint(
    scheme: scheme,
    host: parts.host,
    port: parts.port,
    path: parts.path,
  );

  final scheme = forcedScheme ?? parts.scheme;
  if (scheme != null) return [build(scheme)];
  return schemeProbeOrder.map(build).toList();
}

/// 「智能粘贴」解析出来的字段，未识别到的为 null。
class WebDavPasteResult {
  final String? name;
  final String? endpoint;
  final String? username;
  final String? password;

  const WebDavPasteResult({
    this.name,
    this.endpoint,
    this.username,
    this.password,
  });

  bool get isEmpty =>
      name == null && endpoint == null && username == null && password == null;
}

const _pasteKeys = <String, List<String>>{
  'endpoint': [
    'url',
    'uri',
    'link',
    'host',
    'server',
    'address',
    'addr',
    'endpoint',
    'webdav',
    'dav',
    '地址',
    '服务器',
    '服务地址',
    '链接',
    '网址',
  ],
  'username': [
    'user',
    'username',
    'account',
    'login',
    'name',
    '用户',
    '用户名',
    '账号',
    '帐号',
    '账户',
  ],
  'password': ['pass', 'password', 'pwd', 'secret', '密码', '口令'],
  'name': ['title', 'label', 'alias', 'remark', '名称', '备注', '别名'],
};

/// 从一坨自由文本里认出 WebDAV 的地址 / 账号 / 密码。
///
/// 分享出来的配置基本都是 `key: value` 的行（`url:...` / `账号：...`），冒号可能
/// 是中文的，也可能整段就是一条裸链接。识别不出来的行直接忽略。
WebDavPasteResult parseWebDavPaste(String text) {
  if (text.trim().isEmpty) return const WebDavPasteResult();

  String? name;
  String? endpoint;
  String? username;
  String? password;

  String? keyOf(String rawKey) {
    final k = rawKey.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    for (final entry in _pasteKeys.entries) {
      if (entry.value.contains(k)) return entry.key;
    }
    return null;
  }

  for (final line in text.split(RegExp(r'[\r\n]+'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final sep = RegExp(r'[:：=]').firstMatch(trimmed);
    // `https://…` 里的冒号会被当成分隔符，所以先把裸链接摘出去。
    final looksLikeUrl =
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        (sep == null && trimmed.contains('.') && !trimmed.contains(' '));

    if (looksLikeUrl) {
      endpoint ??= trimmed;
      continue;
    }
    if (sep == null) continue;

    final field = keyOf(trimmed.substring(0, sep.start));
    final value = trimmed.substring(sep.end).trim();
    if (field == null || value.isEmpty) continue;

    switch (field) {
      case 'endpoint':
        endpoint ??= value;
      case 'username':
        username ??= value;
      case 'password':
        password ??= value;
      case 'name':
        name ??= value;
    }
  }

  // 链接里内联的账号密码优先级低于显式写出来的那两行。
  if (endpoint != null) {
    final parts = parseWebDavEndpoint(endpoint);
    if ((parts.username ?? '').isNotEmpty) username ??= parts.username;
    if ((parts.password ?? '').isNotEmpty) password ??= parts.password;
    if (parts.username != null) {
      endpoint = buildWebDavEndpoint(
        scheme: parts.scheme ?? 'https',
        host: parts.host,
        port: parts.port,
        path: parts.path,
      );
      if (parts.scheme == null) {
        // 协议还是未知，别把探测用的 https 固化进输入框。
        endpoint = endpoint.replaceFirst('https://', '');
      }
    }
  }

  return WebDavPasteResult(
    name: name,
    endpoint: endpoint,
    username: username,
    password: password,
  );
}
