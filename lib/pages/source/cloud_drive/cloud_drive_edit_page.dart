import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/router/app_page_route.dart';
import '../../../app/services/cloud_drive/cloud_drive_music_service.dart';
import '../../../app/services/cloud_drive/cloud_drive_source_repository.dart';
import '../../../app/services/cloud_drive/cloud_drive_types.dart';
import '../../../app/services/log/log.dart';
import '../../../app/services/source_deletion_service.dart';
import '../../../app/theme/tokens.dart';
import '../../../components/index.dart';

class CloudDriveEditPage extends StatefulWidget {
  final CloudDriveSource source;
  final bool isAdd;

  const CloudDriveEditPage({
    super.key,
    required this.source,
    this.isAdd = false,
  });

  @override
  State<CloudDriveEditPage> createState() => _CloudDriveEditPageState();
}

class _CloudDriveEditPageState extends State<CloudDriveEditPage> {
  static const String _logTag = 'CloudDriveEditPage';

  final CloudDriveSourceRepository _repo = CloudDriveSourceRepository.instance;
  final CloudDriveMusicService _service = CloudDriveMusicService.instance;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _appKeyController = TextEditingController();
  final TextEditingController _appSecretController = TextEditingController();
  final TextEditingController _baiduRootController = TextEditingController();

  late CloudDriveSource _source;
  bool _authenticated = false;
  bool _busy = false;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source;
    _nameController.text = _source.name;
    _appKeyController.text = _source.appKey;
    _baiduRootController.text = _source.root;
    unawaited(_loadAuthenticationState());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _appKeyController.dispose();
    _appSecretController.dispose();
    _baiduRootController.dispose();
    super.dispose();
  }

  Future<void> _loadAuthenticationState() async {
    try {
      final authenticated = await _service.isAuthenticated(_source);
      if (!mounted) return;
      setState(() => _authenticated = authenticated);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '读取网盘登录状态失败', e, s);
    }
  }

  CloudDriveSource _draft() {
    final name = _nameController.text.trim();
    final baiduRoot = _baiduRootController.text.trim();
    return _source.copyWith(
      name: name.isEmpty ? _source.provider.displayName : name,
      appKey: _appKeyController.text.trim(),
      root: _source.provider == CloudDriveProvider.baidu
          ? (baiduRoot.isEmpty ? '/' : baiduRoot)
          : _source.root,
      rootLabel: _source.provider == CloudDriveProvider.baidu
          ? (baiduRoot.isEmpty ? '/' : baiduRoot)
          : _source.rootLabel,
    );
  }

  Future<void> _login() async {
    final draft = _draft();
    if (draft.provider == CloudDriveProvider.baidu && draft.appKey.isEmpty) {
      AppToast.show(context, '请先填写 App Key', type: ToastType.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final challenge = await _service.beginLogin(
        draft,
        baiduAppSecret: _appSecretController.text,
      );
      if (!mounted) return;
      final success = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CloudDriveLoginDialog(
          source: draft,
          challenge: challenge,
          service: _service,
        ),
      );
      if (!mounted || success != true) return;
      _source = draft;
      setState(() => _authenticated = true);
      AppToast.show(context, '登录成功', type: ToastType.success);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '${draft.provider.displayName}登录失败', e, s);
      if (!mounted) return;
      AppToast.show(
        context,
        e is CloudDriveException ? e.message : '登录失败，请稍后重试',
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseQuarkFolder() async {
    if (!_authenticated) {
      AppToast.show(context, '请先扫码登录夸克网盘');
      return;
    }
    final draft = _draft();
    final selected = await Navigator.push<({String id, String path})>(
      context,
      buildAppPageRoute(
        (_) => CloudDriveFolderPickerPage(
          source: draft,
          initialId: draft.root,
          initialPath: draft.rootLabel,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _source = draft.copyWith(root: selected.id, rootLabel: selected.path);
    });
  }

  Future<void> _save() async {
    final draft = _draft();
    if (_nameController.text.trim().isEmpty) {
      AppToast.show(context, '请输入名称', type: ToastType.error);
      return;
    }
    if (!_authenticated) {
      AppToast.show(context, '请先完成网盘登录', type: ToastType.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await _service.testConnection(draft);
      if (!mounted) return;
      if (!ok) {
        AppToast.show(context, '连接失败，请检查登录状态和目录', type: ToastType.error);
        return;
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
    } catch (e, s) {
      AppLog.instance.w(_logTag, '保存网盘来源失败 sourceId=${draft.id}', e, s);
      if (!mounted) return;
      AppToast.show(
        context,
        e is CloudDriveException ? e.message : '保存失败，请稍后重试',
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    try {
      await _service.logout(_source);
      if (!mounted) return;
      setState(() => _authenticated = false);
      AppToast.show(context, '已退出登录');
    } catch (e, s) {
      AppLog.instance.w(_logTag, '退出网盘登录失败 sourceId=${_source.id}', e, s);
      if (mounted) {
        AppToast.show(context, '退出登录失败', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: '删除${_source.provider.displayName}',
        contentText: '确认删除 ${_source.name} 吗？曲库中的对应歌曲也会移除。',
        confirmText: '删除',
        isDestructive: true,
        onConfirm: () {},
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await SourceDeletionService.instance.deleteSongsForSource(_source.id);
      await _repo.removeById(_source.id);
      await _service.logout(_source);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '删除网盘来源失败 sourceId=${_source.id}', e, s);
      if (mounted) {
        AppToast.show(context, '删除失败，请稍后重试', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    final colors = AppColors.of(context);
    final providerName = _source.provider.displayName;
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: widget.isAdd ? '添加$providerName' : '$providerName设置',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: AppSpacing.pageInsets(
          top: AppSpacing.md,
          bottom: bottomPadding,
        ),
        children: [
          AppSettingSection(
            title: '来源信息',
            children: [
              AppTextFieldTile(
                label: '名称',
                controller: _nameController,
                enabled: !_busy,
              ),
              if (_source.provider == CloudDriveProvider.baidu) ...[
                AppTextFieldTile(
                  label: 'App Key',
                  controller: _appKeyController,
                  enabled: !_busy,
                ),
                AppTextFieldTile(
                  label: 'Secret Key',
                  hintText: widget.isAdd ? null : '留空则继续使用已保存的密钥',
                  controller: _appSecretController,
                  enabled: !_busy,
                  obscureText: !_showSecret,
                  suffix: IconButton(
                    icon: Icon(
                      _showSecret
                          ? AppIcons.visibility
                          : AppIcons.visibilityOff,
                    ),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _showSecret = !_showSecret),
                  ),
                ),
                AppTextFieldTile(
                  label: '扫描目录',
                  hintText: '/',
                  controller: _baiduRootController,
                  enabled: !_busy,
                ),
              ] else
                AppSettingTile(
                  title: '扫描目录',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                        ),
                        child: Text(
                          _source.rootLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.meta.on(colors.muted),
                        ),
                      ),
                      AppSpacing.wGapXs,
                      const Icon(AppIcons.chevronRight),
                    ],
                  ),
                  onTap: _busy ? null : _chooseQuarkFolder,
                ),
            ],
          ),
          AppSpacing.gapLg,
          SurfaceCard(
            padding: AppSpacing.card,
            child: Row(
              children: [
                Icon(
                  _authenticated ? AppIcons.cloudCheck : AppIcons.cloudOff,
                  color: _authenticated
                      ? Theme.of(context).colorScheme.primary
                      : colors.muted,
                ),
                AppSpacing.wGapMd,
                Expanded(
                  child: Text(
                    _authenticated ? '已登录 $providerName' : '尚未登录 $providerName',
                    style: AppTypography.bodyLg.on(colors.text),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : (_authenticated ? _logout : _login),
                  child: Text(_authenticated ? '退出' : '扫码登录'),
                ),
              ],
            ),
          ),
          if (_source.provider == CloudDriveProvider.quark) ...[
            AppSpacing.gapMd,
            Text(
              '夸克使用网页端内部接口，可能因官方调整而失效；播放时需要保持登录 Cookie 有效。',
              style: AppTypography.caption.on(colors.muted),
            ),
          ],
          AppSpacing.gapXl,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(widget.isAdd ? '测试并添加' : '测试并保存'),
            ),
          ),
          if (!widget.isAdd) ...[
            AppSpacing.gapMd,
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _delete,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.danger,
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

class _CloudDriveLoginDialog extends StatefulWidget {
  final CloudDriveSource source;
  final CloudDriveLoginChallenge challenge;
  final CloudDriveMusicService service;

  const _CloudDriveLoginDialog({
    required this.source,
    required this.challenge,
    required this.service,
  });

  @override
  State<_CloudDriveLoginDialog> createState() => _CloudDriveLoginDialogState();
}

class _CloudDriveLoginDialogState extends State<_CloudDriveLoginDialog> {
  static const String _logTag = 'CloudDriveLoginDialog';

  String _statusText = '请使用网盘 App 扫码确认登录';
  bool _polling = true;

  @override
  void initState() {
    super.initState();
    unawaited(_poll());
  }

  @override
  void dispose() {
    _polling = false;
    super.dispose();
  }

  Future<void> _poll() async {
    final expiresAt = DateTime.now().add(widget.challenge.expiresIn);
    while (_polling && DateTime.now().isBefore(expiresAt)) {
      await Future<void>.delayed(widget.challenge.pollInterval);
      if (!_polling || !mounted) return;
      try {
        final status = await widget.service.pollLogin(
          widget.source,
          widget.challenge,
        );
        if (!mounted) return;
        if (status == CloudDriveLoginStatus.complete) {
          _polling = false;
          Navigator.pop(context, true);
          return;
        }
        if (status == CloudDriveLoginStatus.expired) {
          setState(() => _statusText = '二维码已过期，请关闭后重试');
          _polling = false;
          return;
        }
        if (status == CloudDriveLoginStatus.denied) {
          setState(() => _statusText = '已取消授权');
          _polling = false;
          return;
        }
      } catch (e, s) {
        AppLog.instance.w(_logTag, '轮询网盘扫码登录失败', e, s);
        if (!mounted) return;
        setState(
          () => _statusText = e is CloudDriveException
              ? e.message
              : '查询登录状态失败，请稍后重试',
        );
        _polling = false;
      }
    }
    if (mounted && _polling) {
      setState(() => _statusText = '二维码已过期，请关闭后重试');
      _polling = false;
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(
      widget.challenge.verificationUrl.isEmpty
          ? widget.challenge.qrValue
          : widget.challenge.verificationUrl,
    );
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '打开网盘登录地址失败', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final qr = widget.challenge.qrValueIsImageUrl
        ? Image.network(widget.challenge.qrValue, fit: BoxFit.contain)
        : QrImageView(
            data: widget.challenge.qrValue,
            backgroundColor: colors.surface,
          );
    return AppDialogShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.source.provider.displayName}扫码登录',
            style: AppTypography.section.on(colors.text),
          ),
          AppSpacing.gapMd,
          AspectRatio(aspectRatio: 1, child: qr),
          AppSpacing.gapMd,
          Text(
            _statusText,
            textAlign: TextAlign.center,
            style: AppTypography.body.on(colors.text),
          ),
          if (widget.challenge.userCode.isNotEmpty) ...[
            AppSpacing.gapSm,
            SelectableText(
              '授权码：${widget.challenge.userCode}',
              textAlign: TextAlign.center,
              style: AppTypography.bodyLg.on(colors.text),
            ),
          ],
          AppSpacing.gapSm,
          TextButton.icon(
            onPressed: _openInBrowser,
            icon: const Icon(AppIcons.openInNew),
            label: const Text('在浏览器中打开'),
          ),
          AppSpacing.gapMd,
          AppDialogButton(
            label: '关闭',
            onTap: () => Navigator.pop(context, false),
            filled: true,
          ),
        ],
      ),
    );
  }
}

class CloudDriveFolderPickerPage extends StatefulWidget {
  final CloudDriveSource source;
  final String initialId;
  final String initialPath;

  const CloudDriveFolderPickerPage({
    super.key,
    required this.source,
    required this.initialId,
    required this.initialPath,
  });

  @override
  State<CloudDriveFolderPickerPage> createState() =>
      _CloudDriveFolderPickerPageState();
}

class _CloudDriveFolderPickerPageState
    extends State<CloudDriveFolderPickerPage> {
  static const String _logTag = 'CloudDriveFolderPickerPage';

  final CloudDriveMusicService _service = CloudDriveMusicService.instance;
  final List<_FolderLocation> _stack = [];
  List<CloudDriveEntry> _folders = const [];
  bool _loading = true;
  String? _error;

  _FolderLocation get _current => _stack.last;

  @override
  void initState() {
    super.initState();
    _stack.add(_FolderLocation(id: widget.initialId, path: widget.initialPath));
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service.listChildren(widget.source, _current.id);
      if (!mounted) return;
      setState(() {
        _folders = entries.where((entry) => entry.isDirectory).toList();
      });
    } catch (e, s) {
      AppLog.instance.w(_logTag, '加载网盘目录失败 path=${_current.path}', e, s);
      if (!mounted) return;
      setState(() {
        _error = e is CloudDriveException ? e.message : '目录加载失败';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFolder(CloudDriveEntry entry) async {
    final path = _current.path == '/'
        ? '/${entry.name}'
        : '${_current.path}/${entry.name}';
    _stack.add(_FolderLocation(id: entry.id, path: path));
    await _load();
  }

  Future<bool> _goBack() async {
    if (_stack.length <= 1) return true;
    _stack.removeLast();
    await _load();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_goBack());
      },
      child: AppPageScaffold(
        extendBodyBehindAppBar: true,
        appBar: AppTopBar(
          title: '选择扫描目录',
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, (
                id: _current.id,
                path: _current.path,
              )),
              child: const Text('选择'),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Padding(
                  padding: AppSpacing.card,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.body.on(colors.muted),
                      ),
                      AppSpacing.gapMd,
                      FilledButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: AppSpacing.pageInsets(
                  top: AppSpacing.md,
                  bottom: AppPageScaffold.scrollableBottomPadding(context),
                ),
                children: [
                  Text(
                    _current.path,
                    style: AppTypography.caption.on(colors.muted),
                  ),
                  AppSpacing.gapMd,
                  if (_folders.isEmpty)
                    Text(
                      '当前目录没有子文件夹，可以直接选择这里。',
                      style: AppTypography.body.on(colors.muted),
                    )
                  else
                    SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < _folders.length;
                            index++
                          ) ...[
                            if (index > 0)
                              Divider(height: 1, color: colors.line),
                            ListTile(
                              leading: const Icon(AppIcons.folder),
                              title: Text(_folders[index].name),
                              trailing: const Icon(AppIcons.chevronRight),
                              onTap: () => _openFolder(_folders[index]),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _FolderLocation {
  final String id;
  final String path;

  const _FolderLocation({required this.id, required this.path});
}
