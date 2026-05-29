import 'package:flutter/material.dart';

import '../../app/router/app_page_route.dart';
import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../components/index.dart';
import 'navidrome/navidrome_edit_page.dart';
import 'webdav/webdav_edit_page.dart';

class _SourceAddOption {
  final String title;
  final IconData icon;
  final Color color;

  const _SourceAddOption({
    required this.title,
    required this.icon,
    required this.color,
  });
}

class SourceAddPage extends StatelessWidget {
  SourceAddPage({super.key});

  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  final NavidromeSourceRepository _navidromeRepo =
      NavidromeSourceRepository.instance;

  Future<void> _openWebDavAdd(BuildContext context) async {
    final draft = WebDavSource(
      id: _webDavRepo.newId(),
      name: 'WebDAV',
      endpoint: '',
      username: '',
      password: '',
      path: '/',
    );

    final changed = await Navigator.push<bool>(
      context,
      buildAppPageRoute((_) => WebDavEditPage(source: draft, isAdd: true)),
    );
    if (!context.mounted) return;
    if (changed == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openNavidromeAdd(BuildContext context) async {
    final draft = NavidromeSource(
      id: _navidromeRepo.newId(),
      name: 'Navidrome',
      endpoint: '',
      username: '',
      password: '',
      salt: _navidromeRepo.newSalt(),
    );

    final changed = await Navigator.push<bool>(
      context,
      buildAppPageRoute((_) => NavidromeEditPage(source: draft, isAdd: true)),
    );
    if (!context.mounted) return;
    if (changed == true) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '添加新文件源',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          _SourceAddSection(
            title: '网络存储',
            options: const [
              _SourceAddOption(
                title: 'WebDAV',
                icon: Icons.cloud_sync_rounded,
                color: Color(0xFF27B5D8),
              ),
              _SourceAddOption(
                title: 'Navidrome / Subsonic',
                icon: Icons.library_music_rounded,
                color: Color(0xFF6D7CF6),
              ),
            ],
            onTap: (option) {
              if (option.title == 'WebDAV') {
                _openWebDavAdd(context);
                return;
              }
              _openNavidromeAdd(context);
            },
          ),
        ],
      ),
    );
  }
}

class _SourceAddSection extends StatelessWidget {
  final String title;
  final List<_SourceAddOption> options;
  final ValueChanged<_SourceAddOption> onTap;

  const _SourceAddSection({
    required this.title,
    required this.options,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SourceSectionCard(
      title: title,
      children: options
          .map((option) => _SourceAddTile(option: option, onTap: onTap))
          .toList(),
    );
  }
}

class _SourceAddTile extends StatelessWidget {
  final _SourceAddOption option;
  final ValueChanged<_SourceAddOption> onTap;

  const _SourceAddTile({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minVerticalPadding: 16,
      leading: _SourceAddIcon(icon: option.icon, color: option.color),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              option.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: colors.onSurfaceVariant,
      ),
      onTap: () => onTap(option),
    );
  }
}

class _SourceAddIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SourceAddIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
