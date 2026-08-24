import 'package:bili_api/bili_api.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router/app_router.dart';
import '../../app/services/lyrics/lyrics_service.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radii.dart';
import '../../components/index.dart';

/// B 站个人主页：账号信息 + 收藏夹显示筛选 + 相关功能开关。
///
/// 从 B站主页左上角的头像进来。所有 B 站相关的设置集中在这里，不散落到全局
/// 设置页去 —— 那边是按功能分组的，B 站是一个「源」，跟着源走更好找。
class BiliProfilePage extends StatefulWidget {
  const BiliProfilePage({super.key});

  @override
  State<BiliProfilePage> createState() => _BiliProfilePageState();
}

class _BiliProfilePageState extends State<BiliProfilePage> {
  final BiliApi _api = BiliApi.instance;

  BiliAccount _account = const BiliAccount();
  List<BiliFavFolder> _folders = const [];
  Set<int> _visible = const {};
  bool _loadingFolders = false;
  String _folderError = '';
  bool _subtitleLyrics = true;

  /// 退出登录后要让上一页知道账号变了。
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final account = await BiliCookieRepository.instance.load();
    final visible = await BiliPrefs.visibleFolderIds();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _account = account;
      _visible = visible;
      _subtitleLyrics =
          prefs.getBool(LyricsService.prefsBiliSubtitleEnabled) ?? true;
    });
    if (account.isLoggedIn) _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _loadingFolders = true;
      _folderError = '';
    });
    try {
      final folders = await _api.favFolders();
      if (!mounted) return;
      setState(() {
        _folders = folders;
        _loadingFolders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingFolders = false;
        _folderError = e is BiliApiException ? e.message : '加载失败：$e';
      });
    }
  }

  Future<void> _toggleFolder(BiliFavFolder folder, bool show) async {
    // 空集合的语义是「全部显示」。用户第一次取消勾选某个收藏夹时，得先把
    // 当前可见的全部写进去，否则会从「全部显示」直接跳成「只显示这一个」。
    final next = _visible.isEmpty
        ? _folders.map((f) => f.id).toSet()
        : {..._visible};
    if (show) {
      next.add(folder.id);
    } else {
      next.remove(folder.id);
    }
    setState(() => _visible = next);
    await BiliPrefs.setVisibleFolderIds(next);
  }

  Future<void> _setSubtitleLyrics(bool value) async {
    setState(() => _subtitleLyrics = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(LyricsService.prefsBiliSubtitleEnabled, value);
    await LyricsService.instance.refreshSettings();
    LyricsService.instance.reloadCurrentSong();
  }

  Future<void> _login() async {
    final result = await Navigator.pushNamed(context, AppRoutes.biliLogin);
    if (result is BiliAccount && mounted) {
      _accountChanged = true;
      setState(() => _account = result);
      _loadFolders();
    }
  }

  Future<void> _logout() async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: '退出登录',
      content: '退出后将无法查看账号中的 B 站收藏夹，本地视频收藏不受影响。',
      confirmText: '退出',
      isDestructive: true,
    );
    if (confirmed != true) return;
    await _api.logout();
    if (!mounted) return;
    _accountChanged = true;
    setState(() {
      _account = const BiliAccount();
      _folders = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {},
      child: AppPageScaffold(
        extendBodyBehindAppBar: true,
        appBar: AppTopBar(
          title: '账号',
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _accountChanged),
          ),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
          children: [
            _buildAccountCard(),
            const SizedBox(height: 20),
            _buildFolderSection(),
            const SizedBox(height: 20),
            AppSettingSection(
              title: '功能',
              children: [
                AppSettingSwitchTile(
                  title: 'B站字幕当歌词',
                  subtitle: '本地没有歌词时，自动取视频字幕（需登录）',
                  value: _subtitleLyrics,
                  onChanged: _setSubtitleLyrics,
                ),
              ],
            ),
            if (_account.isLoggedIn) ...[
              const SizedBox(height: 20),
              AppSettingSection(
                children: [
                  AppSettingTile(
                    title: '退出登录',
                    leading: Icon(
                      Icons.logout_rounded,
                      color: AppColors.of(context).danger,
                    ),
                    onTap: _logout,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            backgroundImage: _account.face.isEmpty
                ? null
                : NetworkImage(_account.face),
            child: _account.face.isEmpty
                ? Icon(Icons.person_rounded, color: scheme.primary)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _account.isLoggedIn ? _account.uname : '未登录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  !_account.isLoggedIn
                      ? '登录后可查看收藏夹、获取高音质与字幕'
                      : _account.isVip
                      ? '大会员 · UID ${_account.mid}'
                      : 'UID ${_account.mid}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ],
            ),
          ),
          if (!_account.isLoggedIn)
            FilledButton.tonal(onPressed: _login, child: const Text('登录')),
        ],
      ),
    );
  }

  Widget _buildFolderSection() {
    if (!_account.isLoggedIn) {
      return const SizedBox.shrink();
    }
    if (_loadingFolders) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_folderError.isNotEmpty) {
      return AppSettingSection(
        title: '收藏夹显示',
        children: [
          AppSettingTile(
            title: _folderError,
            subtitle: '点击重试',
            onTap: _loadFolders,
          ),
        ],
      );
    }
    if (_folders.isEmpty) {
      return AppSettingSection(
        title: '收藏夹显示',
        children: [
          AppSettingTile(
            title: '还没有收藏夹',
            subtitle: '点击刷新',
            onTap: _loadFolders,
          ),
        ],
      );
    }
    // 空集合 = 全部显示，勾选框要照这个语义显示成全选。
    final allVisible = _visible.isEmpty;
    return AppSettingSection(
      title: '收藏夹显示（勾选的才出现在 B站 页）',
      children: [
        for (final folder in _folders)
          AppSettingSwitchTile(
            title: folder.title,
            subtitle: '${folder.mediaCount} 个视频',
            value: allVisible || _visible.contains(folder.id),
            onChanged: (value) => _toggleFolder(folder, value),
          ),
      ],
    );
  }
}

/// 顶栏左上角的「头像 + 用户名」。点击进入 [BiliProfilePage]。
class BiliAccountChip extends StatelessWidget {
  final BiliAccount account;
  final VoidCallback onTap;

  const BiliAccountChip({
    super.key,
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                backgroundImage: account.face.isEmpty
                    ? null
                    : NetworkImage(account.face),
                child: account.face.isEmpty
                    ? Icon(
                        Icons.person_rounded,
                        size: 18,
                        color: scheme.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 9),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  account.isLoggedIn ? account.uname : '未登录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
