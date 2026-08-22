import 'package:flutter/material.dart';

import '../../../app/router/app_page_route.dart';
import '../../../app/services/db/dao/song_dao.dart';
import '../../../app/services/webdav/webdav_music_service.dart';
import '../../../app/services/webdav/webdav_source_repository.dart';
import '../../../components/index.dart';
import 'webdav_folder_picker_page.dart';

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
  final TextEditingController _endpointCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final List<TextEditingController> _altEndpointCtrls = [];

  bool _showPassword = false;
  bool _saving = false;
  bool _testingAll = false;
  Map<String, bool>? _testResults;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _nameCtrl.text = _source.name;
    _endpointCtrl.text = _source.endpoint;
    _usernameCtrl.text = _source.username;
    _passwordCtrl.text = _source.password;
    for (final endpoint in _source.altEndpoints) {
      _altEndpointCtrls.add(TextEditingController(text: endpoint));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    for (final ctrl in _altEndpointCtrls) {
      ctrl.dispose();
    }
    super.dispose();
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

  List<String> _altEndpointValues() => _altEndpointCtrls
      .map((c) => c.text.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _testAllEndpoints() async {
    final draft = _draftSource().copyWith(
      includeFolders: _source.includeFolders,
      excludeFolders: _source.excludeFolders,
    );
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

  WebDavSource _draftSource() {
    final name = _nameCtrl.text.trim();
    final endpoint = _endpointCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    final path = _source.includeFolders.isNotEmpty
        ? _normalizePath(_source.includeFolders.first)
        : _normalizePath(_source.path);

    return _source.copyWith(
      name: name.isEmpty ? _source.name : name,
      endpoint: endpoint,
      altEndpoints: _altEndpointValues(),
      username: username,
      password: password,
      path: path,
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

  Future<void> _pickFolder() async {
    final endpoint = _endpointCtrl.text.trim();
    if (endpoint.isEmpty) {
      AppToast.show(context, '请先填写 WebDAV 地址', type: ToastType.error);
      return;
    }

    final selected = await Navigator.push<List<String>>(
      context,
      buildAppPageRoute(
        (_) => WebDavFolderPickerPage(
          source: _draftSource(),
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
    final name = _nameCtrl.text.trim();
    final endpoint = _endpointCtrl.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, '请输入名称', type: ToastType.error);
      return;
    }
    if (endpoint.isEmpty) {
      AppToast.show(context, '请输入服务地址', type: ToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final draft = _draftSource().copyWith(
        includeFolders: _source.includeFolders,
        excludeFolders: _source.excludeFolders,
      );

      if (testFirst) {
        final ok = await _service.testConnection(draft);
        if (!mounted) return;
        if (!ok) {
          AppToast.show(context, '连接失败，请检查地址或账号密码', type: ToastType.error);
          return;
        }
      }

      await _repo.upsert(draft);
      _source = draft;

      if (!mounted) return;
      AppToast.show(
        context,
        widget.isAdd ? '连接成功，已添加' : '已保存',
        type: ToastType.success,
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final folders = _source.includeFolders;
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);

    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: widget.isAdd ? '添加 WebDAV' : 'WebDAV 设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '连接信息',
            children: [
              AppTextFieldTile(
                label: '名称',
                controller: _nameCtrl,
                hintText: '自定义名称',
                enabled: !_saving,
              ),
              AppTextFieldTile(
                label: '地址',
                controller: _endpointCtrl,
                hintText: 'https://example.com/dav',
                enabled: !_saving,
              ),
              AppTextFieldTile(
                label: '用户名',
                controller: _usernameCtrl,
                enabled: !_saving,
              ),
              AppTextFieldTile(
                label: '密码',
                controller: _passwordCtrl,
                enabled: !_saving,
                obscureText: !_showPassword,
                suffix: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: _saving
                      ? null
                      : () => setState(() => _showPassword = !_showPassword),
                ),
              ),
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
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            title: '备用地址',
            children: [
              for (var i = 0; i < _altEndpointCtrls.length; i++)
                AppTextFieldTile(
                  label: '备用地址 ${i + 1}',
                  controller: _altEndpointCtrls[i],
                  hintText: 'https://alt.example.com/dav',
                  enabled: !_saving,
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_testResults != null)
                        Builder(
                          builder: (context) {
                            final ok =
                                _testResults![_altEndpointCtrls[i].text
                                    .trim()] ??
                                false;
                            return Icon(
                              ok ? Icons.check_circle : Icons.error_outline,
                              color: ok ? Colors.green : Colors.red,
                              size: 18,
                            );
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
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
                leading: const Icon(Icons.add_link),
                onTap: _saving ? null : _addAltEndpoint,
              ),
              if (_altEndpointCtrls.isNotEmpty)
                AppSettingTile(
                  title: _testingAll ? '测试中...' : '测试全部地址',
                  leading: const Icon(Icons.wifi_tethering),
                  onTap: _saving || _testingAll ? null : _testAllEndpoints,
                ),
            ],
          ),
          if (!widget.isAdd) ...[
            const SizedBox(height: 16),
            AppSettingSection(
              title: '扫描文件夹',
              children: [
                if (folders.isNotEmpty)
                  ...folders.map(
                    (path) => AppSettingTile(
                      title: path,
                      leading: const Icon(Icons.folder_outlined),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _saving ? null : () => _removeFolder(path),
                      ),
                    ),
                  ),
                AppSettingTile(
                  title: '选择文件夹（可多选）',
                  leading: const Icon(Icons.create_new_folder_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _saving ? null : _pickFolder,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : () => _save(testFirst: widget.isAdd),
              child: Text(widget.isAdd ? '确定' : '保存'),
            ),
          ),
          if (!widget.isAdd) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _delete,
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                child: const Text('删除'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
