import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nagomusic/app/theme/app_icons.dart';

import '../../../app/router/app_page_route.dart';
import '../../../app/services/db/dao/song_dao.dart';
import '../../../app/services/webdav/webdav_music_service.dart';
import '../../../app/services/webdav/webdav_source_repository.dart';
import '../../../app/services/webdav/webdav_url.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radii.dart';
import '../../../components/index.dart';
import 'webdav_folder_picker_page.dart';

/// 协议下拉里的三个选项。[auto] 不写死协议，保存时按 https → http 顺序试连。
enum _ProtocolChoice {
  auto('自动识别', null),
  https('HTTPS', 'https'),
  http('HTTP', 'http');

  final String label;
  final String? scheme;

  const _ProtocolChoice(this.label, this.scheme);

  static _ProtocolChoice fromScheme(String? scheme) {
    return switch (scheme) {
      'https' => _ProtocolChoice.https,
      'http' => _ProtocolChoice.http,
      _ => _ProtocolChoice.auto,
    };
  }
}

class WebDavEditPage extends StatefulWidget {
  final WebDavSource source;
  final bool isAdd;

  const WebDavEditPage({super.key, required this.source, this.isAdd = false});

  @override
  State<WebDavEditPage> createState() => _WebDavEditPageState();
}

class _WebDavEditPageState extends State<WebDavEditPage> {
  final WebDavSourceRepository _repo = WebDavSourceRepository.instance;
  final WebDavMusicService _service = WebDavMusicService();
  final SongDao _songDao = SongDao();

  late WebDavSource _source;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _portCtrl = TextEditingController();
  final TextEditingController _basePathCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _pasteCtrl = TextEditingController();
  final List<TextEditingController> _altEndpointCtrls = [];

  _ProtocolChoice _protocol = _ProtocolChoice.auto;
  bool _showPassword = false;
  bool _showPaste = false;
  bool _saving = false;
  bool _testingAll = false;
  Map<String, bool>? _testResults;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _nameCtrl.text = _source.name;
    _usernameCtrl.text = _source.username;
    _passwordCtrl.text = _source.password;

    // endpoint 是存储层的单一真相，编辑页只是把它拆成四个框；保存时再拼回去。
    final parts = parseWebDavEndpoint(_source.endpoint);
    _protocol = _ProtocolChoice.fromScheme(parts.scheme);
    _hostCtrl.text = parts.host;
    _portCtrl.text = parts.portText;
    _basePathCtrl.text = parts.path;

    for (final endpoint in _source.altEndpoints) {
      _altEndpointCtrls.add(TextEditingController(text: endpoint));
    }
    _hostCtrl.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _hostCtrl.removeListener(_onFormChanged);
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _basePathCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _pasteCtrl.dispose();
    for (final ctrl in _altEndpointCtrls) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onFormChanged() {
    // 提交按钮的可用态跟着地址走，需要一次重建。
    if (mounted) setState(() {});
  }

  bool get _canSubmit => _hostCtrl.text.trim().isNotEmpty && !_saving;

  // ------------------------------------------------------------------ 地址拼装

  /// 把四个输入框拼成一条 endpoint。协议为「自动识别」时返回不带协议的裸地址，
  /// 交给 [_resolveEndpoint] 去探测。
  String _composeEndpoint({String? scheme}) {
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return '';
    final port = int.tryParse(_portCtrl.text.trim());
    final path = normalizeWebDavBasePath(_basePathCtrl.text);
    final effective = scheme ?? _protocol.scheme;
    if (effective == null) {
      final buffer = StringBuffer(host);
      if (port != null) buffer.write(':$port');
      buffer.write(path);
      return buffer.toString();
    }
    return buildWebDavEndpoint(
      scheme: effective,
      host: host,
      port: port,
      path: path,
    );
  }

  /// 得到一条**确定能连上**的完整地址。
  ///
  /// 协议选了具体值时只试那一个；选「自动识别」时 https / http 轮着试，第一个连
  /// 得通的就是它。全都不通返回 null，由调用方提示。
  Future<String?> _resolveEndpoint(WebDavSource draft) {
    return _service.resolveEndpoint(
      draft,
      rawEndpoint: _composeEndpoint(),
      forcedScheme: _protocol.scheme,
    );
  }

  WebDavSource _draftSource({String? endpoint}) {
    final name = _nameCtrl.text.trim();
    final path = _source.includeFolders.isNotEmpty
        ? _normalizePath(_source.includeFolders.first)
        : _normalizePath(_source.path);

    return _source.copyWith(
      name: name.isEmpty ? _source.name : name,
      endpoint: endpoint ?? _composeEndpoint(),
      altEndpoints: _altEndpointValues(),
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      path: path,
      includeFolders: _source.includeFolders,
      excludeFolders: _source.excludeFolders,
    );
  }

  String _normalizePath(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return '/';
    t = t.replaceAll('\\', '/');
    if (!t.startsWith('/')) t = '/$t';
    if (t.length > 1 && t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  List<String> _altEndpointValues() => _altEndpointCtrls
      .map((c) => c.text.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  // ------------------------------------------------------------------ 智能粘贴

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!mounted) return;
    if (text.trim().isEmpty) {
      AppToast.show(context, '剪贴板是空的', type: ToastType.error);
      return;
    }
    _pasteCtrl.text = text;
    _applyPaste();
  }

  void _applyPaste() {
    final result = parseWebDavPaste(_pasteCtrl.text);
    if (result.isEmpty) {
      AppToast.show(context, '没能从这段文本里认出地址或账号', type: ToastType.error);
      return;
    }

    setState(() {
      if (result.endpoint != null) {
        final parts = parseWebDavEndpoint(result.endpoint!);
        _protocol = _ProtocolChoice.fromScheme(parts.scheme);
        _hostCtrl.text = parts.host;
        _portCtrl.text = parts.portText;
        _basePathCtrl.text = parts.path;
      }
      if (result.username != null) _usernameCtrl.text = result.username!;
      if (result.password != null) _passwordCtrl.text = result.password!;
      if (result.name != null) _nameCtrl.text = result.name!;
      _showPaste = false;
      _pasteCtrl.clear();
    });
    AppToast.show(context, '已填入', type: ToastType.success);
  }

  // -------------------------------------------------------------------- 交互

  Future<void> _pickProtocol() async {
    final picked = await showModalBottomSheet<_ProtocolChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = AppColors.of(sheetContext);
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            // Material 而不是 Container 上色：里面是 ListTile，背景/涟漪要画在
            // 最近的 Material 上，中间夹一个有底色的 DecoratedBox 会被盖住。
            child: Material(
              color: c.surface,
              borderRadius: AppRadii.rDialog,
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in _ProtocolChoice.values)
                    ListTile(
                      title: Text(choice.label),
                      subtitle: choice == _ProtocolChoice.auto
                          ? const Text('先试 HTTPS，不通再试 HTTP')
                          : null,
                      trailing: choice == _protocol
                          ? Icon(
                              AppIcons.check,
                              color: Theme.of(sheetContext).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(sheetContext, choice),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _protocol = picked;
      // 端口留空时靠 hint 显示协议默认端口，切协议要重画。
      _testResults = null;
    });
  }

  void _addAltEndpoint() {
    setState(() {
      _altEndpointCtrls.add(TextEditingController());
      _testResults = null;
    });
  }

  void _removeAltEndpoint(int index) {
    setState(() {
      final ctrl = _altEndpointCtrls.removeAt(index);
      ctrl.dispose();
      _testResults = null;
    });
  }

  Future<void> _testAllEndpoints() async {
    final draft = _draftSource();
    if (draft.allEndpoints.isEmpty) {
      AppToast.show(context, '请先填写至少一个地址', type: ToastType.error);
      return;
    }
    setState(() {
      _testingAll = true;
      _testResults = null;
    });
    try {
      final result = await _service.testConnections(draft);
      if (!mounted) return;
      final okCount = result.values.where((ok) => ok).length;
      setState(() => _testResults = result);
      AppToast.show(
        context,
        '$okCount/${result.length} 个地址可连接',
        type: okCount > 0 ? ToastType.success : ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _testingAll = false);
    }
  }

  Future<void> _pickFolder() async {
    if (_hostCtrl.text.trim().isEmpty) {
      AppToast.show(context, '请先填写 WebDAV 地址', type: ToastType.error);
      return;
    }

    final selected = await Navigator.push<List<String>>(
      context,
      buildAppPageRoute(
        (_) => WebDavFolderPickerPage(
          source: _draftSource(
            endpoint: normalizeWebDavEndpoint(_composeEndpoint()),
          ),
          initialPath: _normalizePath(_source.path),
          initialSelected: _source.includeFolders,
        ),
      ),
    );
    if (!mounted) return;
    if (selected == null) return;
    final nextFolders = selected.map(_normalizePath).toList();

    setState(() {
      _source = _source.copyWith(
        includeFolders: nextFolders,
        path: nextFolders.isNotEmpty ? nextFolders.first : _source.path,
      );
    });
  }

  Future<void> _removeFolder(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '移除文件夹',
        contentText: '确认不再扫描该文件夹吗？\n$path',
        confirmText: '移除',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (ok != true) return;

    final next = _source.includeFolders.toList()..remove(path);
    setState(() {
      _source = _source.copyWith(
        includeFolders: next,
        path: next.isNotEmpty ? next.first : _source.path,
      );
    });
  }

  Future<void> _save({required bool testFirst}) async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppToast.show(context, '请输入名称', type: ToastType.error);
      return;
    }
    if (_hostCtrl.text.trim().isEmpty) {
      AppToast.show(context, '请输入服务地址', type: ToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      var draft = _draftSource();

      // 协议探测本身就是一次真实连接，所以先探测、再按结果决定要不要另外测一次。
      final needsProbe = testFirst || _protocol == _ProtocolChoice.auto;
      if (needsProbe) {
        final resolved = await _resolveEndpoint(draft);
        if (!mounted) return;
        if (resolved == null) {
          AppToast.show(
            context,
            _protocol == _ProtocolChoice.auto
                ? 'HTTPS 和 HTTP 都连不上，请检查地址或账号密码'
                : '连接失败，请检查地址或账号密码',
            type: ToastType.error,
          );
          return;
        }
        draft = draft.copyWith(endpoint: resolved);
        // 探测结果回填到协议行，用户下次进来能看到实际用的是哪个。
        _protocol = _ProtocolChoice.fromScheme(
          parseWebDavEndpoint(resolved).scheme,
        );
      } else {
        draft = draft.copyWith(
          endpoint: normalizeWebDavEndpoint(draft.endpoint),
        );
      }

      await _repo.upsert(draft);
      _source = draft;

      if (!mounted) return;
      AppToast.show(
        context,
        widget.isAdd ? '连接成功，已添加' : '已保存',
        type: ToastType.success,
      );

      // 新建时直接把用户送进文件夹选择页。连接刚验证过，这时候正是列目录的时机；
      // 否则用户得先回列表、再进设置、再点「选择文件夹」，才能真正把歌导进来。
      if (widget.isAdd) {
        await _pickFoldersAfterAdd(draft);
        if (!mounted) return;
      }

      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 添加成功后的文件夹选择。返回时把选中的目录并进刚存下的音源。
  ///
  /// 用户直接返回（没点「导入」）也无所谓 —— 音源本身已经存好了，只是没限定扫描
  /// 范围，之后从设置页补选即可。
  Future<void> _pickFoldersAfterAdd(WebDavSource saved) async {
    final selected = await Navigator.push<List<String>>(
      context,
      buildAppPageRoute(
        (_) => WebDavFolderPickerPage(
          source: saved,
          initialPath: _normalizePath(saved.path),
          confirmLabel: '导入',
        ),
      ),
    );
    if (!mounted || selected == null) return;

    final folders = selected.map(_normalizePath).toList();
    final withFolders = saved.copyWith(
      includeFolders: folders,
      path: folders.isNotEmpty ? folders.first : saved.path,
    );
    await _repo.upsert(withFolders);
    if (!mounted) return;
    setState(() => _source = withFolders);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '删除 WebDAV',
        contentText:
            '确认删除 ${_source.name.trim().isNotEmpty ? _source.name.trim() : 'WebDAV'} 吗？',
        confirmText: '删除',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      await _repo.removeById(_source.id);
      await _songDao.deleteBySource(_source.id);
      if (!mounted) return;
      AppToast.show(context, '已删除', type: ToastType.success);
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final folders = _source.includeFolders;
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    final portHint = _protocol.scheme == null
        ? '自动'
        : '${defaultWebDavPort(_protocol.scheme!)}';

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: widget.isAdd ? '添加 WebDAV' : 'WebDAV 设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
              children: [
                AppSettingSection(
                  showDividers: false,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    AppFormFieldRow(
                      label: '名称',
                      controller: _nameCtrl,
                      hintText: '我的 WebDAV',
                      enabled: !_saving,
                    ),
                    AppFormValueRow(
                      label: '协议',
                      value: _protocol.label,
                      enabled: !_saving,
                      onTap: _pickProtocol,
                    ),
                    AppFormFieldRow(
                      label: '地址',
                      required: true,
                      controller: _hostCtrl,
                      hintText: '请输入 IP 或域名',
                      enabled: !_saving,
                      keyboardType: TextInputType.url,
                    ),
                    AppFormFieldRow(
                      label: '端口',
                      controller: _portCtrl,
                      hintText: portHint,
                      enabled: !_saving,
                      keyboardType: TextInputType.number,
                    ),
                    AppFormFieldRow(
                      label: '用户名',
                      controller: _usernameCtrl,
                      hintText: '选填',
                      enabled: !_saving,
                    ),
                    AppFormFieldRow(
                      label: '密码',
                      controller: _passwordCtrl,
                      hintText: '选填',
                      enabled: !_saving,
                      obscureText: !_showPassword,
                      suffix: IconButton(
                        iconSize: 20,
                        color: c.muted,
                        icon: Icon(
                          _showPassword
                              ? AppIcons.visibility
                              : AppIcons.visibilityOff,
                        ),
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                      ),
                    ),
                    AppFormFieldRow(
                      label: '路径',
                      controller: _basePathCtrl,
                      hintText: '选填，例如：/dav',
                      enabled: !_saving,
                      suffix: IconButton(
                        iconSize: 20,
                        color: c.muted,
                        icon: const Icon(AppIcons.closeCircle),
                        onPressed: _saving
                            ? null
                            : () => setState(_basePathCtrl.clear),
                      ),
                    ),
                    _SmartPasteRow(
                      expanded: _showPaste,
                      controller: _pasteCtrl,
                      enabled: !_saving,
                      onToggle: () => setState(() => _showPaste = !_showPaste),
                      onPasteClipboard: _pasteFromClipboard,
                      onApply: _applyPaste,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                AppSettingSection(
                  title: '扫描',
                  children: [
                    AppSettingSwitchTile(
                      title: '扫描时自动刮削标签',
                      subtitle: '默认关闭；开启后扫描会额外读取内置标签',
                      value: _source.scrapeTagsOnScan,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() {
                              _source = _source.copyWith(scrapeTagsOnScan: v);
                            }),
                    ),
                    if (!widget.isAdd) ...[
                      ...folders.map(
                        (path) => AppSettingTile(
                          title: path,
                          leading: const Icon(AppIcons.folder),
                          trailing: IconButton(
                            icon: const Icon(AppIcons.trash),
                            onPressed: _saving
                                ? null
                                : () => _removeFolder(path),
                          ),
                        ),
                      ),
                      AppSettingTile(
                        title: '选择文件夹（可多选）',
                        subtitle: folders.isEmpty ? '不选则扫描整个根目录' : null,
                        leading: const Icon(AppIcons.folderAdd),
                        trailing: const Icon(AppIcons.chevronRight),
                        onTap: _saving ? null : _pickFolder,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                AppSettingSection(
                  title: '备用地址',
                  children: [
                    for (var i = 0; i < _altEndpointCtrls.length; i++)
                      AppFormFieldRow(
                        label: '备用 ${i + 1}',
                        controller: _altEndpointCtrls[i],
                        hintText: 'alt.example.com/dav',
                        enabled: !_saving,
                        suffix: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_testResults != null)
                              _TestResultDot(
                                ok:
                                    _testResults![normalizeWebDavEndpoint(
                                      _altEndpointCtrls[i].text,
                                    )] ??
                                    false,
                              ),
                            IconButton(
                              iconSize: 20,
                              color: c.muted,
                              icon: const Icon(AppIcons.trash),
                              onPressed: _saving
                                  ? null
                                  : () => _removeAltEndpoint(i),
                            ),
                          ],
                        ),
                      ),
                    AppSettingTile(
                      title: '添加备用地址',
                      subtitle: '例如内网穿透/DDNS 地址，需指向同一台服务器',
                      leading: const Icon(AppIcons.addLink),
                      onTap: _saving ? null : _addAltEndpoint,
                    ),
                    if (_altEndpointCtrls.isNotEmpty)
                      AppSettingTile(
                        title: _testingAll ? '测试中...' : '测试全部地址',
                        leading: const Icon(AppIcons.wifi),
                        onTap: _saving || _testingAll
                            ? null
                            : _testAllEndpoints,
                      ),
                  ],
                ),
                if (!widget.isAdd) ...[
                  const SizedBox(height: 16),
                  AppSettingSection(
                    children: [
                      AppSettingTile(
                        title: '删除该音源',
                        leading: const Icon(AppIcons.trash),
                        destructive: true,
                        onTap: _saving ? null : _delete,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          _SubmitBar(
            label: widget.isAdd ? '添加' : '保存',
            busy: _saving,
            onPressed: _canSubmit ? () => _save(testFirst: widget.isAdd) : null,
          ),
        ],
      ),
    );
  }
}

/// 表单最后一行：折叠着的时候只是一个「智能粘贴 ⌄」的入口。
///
/// 展开后是一个多行输入框，把分享出来的那种
/// `url: ... / account: ... / password: ...` 整段贴进去就能拆开填表，省得在七个
/// 输入框之间来回切。
class _SmartPasteRow extends StatelessWidget {
  final bool expanded;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onPasteClipboard;
  final VoidCallback onApply;

  const _SmartPasteRow({
    required this.expanded,
    required this.controller,
    required this.enabled,
    required this.onToggle,
    required this.onPasteClipboard,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      children: [
        InkWell(
          onTap: enabled ? onToggle : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '智能粘贴',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                  size: 18,
                  color: c.text,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  enabled: enabled,
                  maxLines: 5,
                  minLines: 3,
                  style: TextStyle(fontSize: 14, color: c.text),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.mediaBg,
                    hintText: 'url: dav.example.com/dav\n账号: xxx\n密码: xxx',
                    hintStyle: TextStyle(fontSize: 14, color: c.muted),
                    contentPadding: const EdgeInsets.all(14),
                    border: const OutlineInputBorder(
                      borderRadius: AppRadii.rPanel,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: enabled ? onPasteClipboard : null,
                        child: const Text('读取剪贴板'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: enabled ? onApply : null,
                        child: const Text('解析填入'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 底部固定的提交条，跟着安全区走。
class _SubmitBar extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  const _SubmitBar({required this.label, required this.busy, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      ),
    );
  }
}

class _TestResultDot extends StatelessWidget {
  final bool ok;

  const _TestResultDot({required this.ok});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Icon(
      ok ? AppIcons.checkCircle : AppIcons.error,
      color: ok ? Colors.green : c.danger,
      size: 18,
    );
  }
}
