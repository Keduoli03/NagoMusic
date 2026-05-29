import 'package:flutter/material.dart';

import '../../../app/services/db/dao/song_dao.dart';
import '../../../app/services/navidrome/navidrome_music_service.dart';
import '../../../app/services/navidrome/navidrome_source_repository.dart';
import '../../../components/index.dart';

class NavidromeEditPage extends StatefulWidget {
  final NavidromeSource source;
  final bool isAdd;

  const NavidromeEditPage({
    super.key,
    required this.source,
    this.isAdd = false,
  });

  @override
  State<NavidromeEditPage> createState() => _NavidromeEditPageState();
}

class _NavidromeEditPageState extends State<NavidromeEditPage> {
  final NavidromeSourceRepository _repo = NavidromeSourceRepository.instance;
  final NavidromeMusicService _service = NavidromeMusicService();
  final SongDao _songDao = SongDao();

  late NavidromeSource _source;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _endpointCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _showPassword = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _nameCtrl.text = _source.name;
    _endpointCtrl.text = _source.endpoint;
    _usernameCtrl.text = _source.username;
    _passwordCtrl.text = _source.password;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _endpointCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  NavidromeSource _draftSource() {
    final name = _nameCtrl.text.trim();
    return _source.copyWith(
      name: name.isEmpty ? 'Navidrome' : name,
      endpoint: _endpointCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text,
      salt: _source.salt.trim().isEmpty ? _repo.newSalt() : _source.salt,
    );
  }

  Future<void> _save({required bool testFirst}) async {
    final name = _nameCtrl.text.trim();
    final endpoint = _endpointCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (name.isEmpty) {
      AppToast.show(context, '请输入名称', type: ToastType.error);
      return;
    }
    if (endpoint.isEmpty) {
      AppToast.show(context, '请输入服务地址', type: ToastType.error);
      return;
    }
    if (username.isEmpty) {
      AppToast.show(context, '请输入用户名', type: ToastType.error);
      return;
    }
    if (password.isEmpty) {
      AppToast.show(context, '请输入密码', type: ToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final draft = _draftSource();
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
        title: '删除 Navidrome',
        contentText:
            '确认删除 ${_source.name.trim().isNotEmpty ? _source.name.trim() : 'Navidrome'} 吗？',
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
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: widget.isAdd ? '添加 Navidrome' : 'Navidrome 设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '连接信息',
            children: [
              _TextFieldTile(
                label: '名称',
                controller: _nameCtrl,
                hintText: 'Navidrome',
                enabled: !_saving,
              ),
              _TextFieldTile(
                label: '服务地址',
                controller: _endpointCtrl,
                hintText: 'https://music.example.com',
                enabled: !_saving,
              ),
              _TextFieldTile(
                label: '用户名',
                controller: _usernameCtrl,
                enabled: !_saving,
              ),
              _TextFieldTile(
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
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : () => _save(testFirst: true),
              child: Text(widget.isAdd ? '测试并添加' : '测试并保存'),
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

class _TextFieldTile extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hintText;
  final bool enabled;
  final bool obscureText;
  final Widget? suffix;

  const _TextFieldTile({
    required this.label,
    required this.controller,
    this.hintText,
    required this.enabled,
    this.obscureText = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          border: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}
