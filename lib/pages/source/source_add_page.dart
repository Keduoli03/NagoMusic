import 'package:flutter/material.dart';
import 'package:nagomusic/app/theme/tokens.dart';

import '../../app/router/app_page_route.dart';
import '../../app/services/cloud_drive/cloud_drive_source_repository.dart';
import '../../app/services/cloud_drive/cloud_drive_types.dart';
import '../../app/services/navidrome/navidrome_source_repository.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../components/index.dart';
import 'cloud_drive/cloud_drive_edit_page.dart';
import 'navidrome/navidrome_edit_page.dart';
import 'webdav/webdav_edit_page.dart';

class _SourceAddOption {
  final _SourceAddKind kind;
  final String title;
  final IconData icon;

  const _SourceAddOption({
    required this.kind,
    required this.title,
    required this.icon,
  });
}

enum _SourceAddKind { webdav, navidrome, baidu, quark }

class SourceAddPage extends StatelessWidget {
  SourceAddPage({super.key});

  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  final NavidromeSourceRepository _navidromeRepo =
      NavidromeSourceRepository.instance;
  final CloudDriveSourceRepository _cloudDriveRepo =
      CloudDriveSourceRepository.instance;

  Future<void> _openWebDavAdd(BuildContext context) async {
    final draft = WebDavSource(
      id: _webDavRepo.newId(),
      name: '我的 WebDAV',
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

  Future<void> _openCloudDriveAdd(
    BuildContext context,
    CloudDriveProvider provider,
  ) async {
    final draft = CloudDriveSource(
      id: _cloudDriveRepo.newIdFor(provider),
      name: provider.displayName,
      provider: provider,
      root: provider.defaultRoot,
    );
    final changed = await Navigator.push<bool>(
      context,
      buildAppPageRoute((_) => CloudDriveEditPage(source: draft, isAdd: true)),
    );
    if (!context.mounted) return;
    if (changed == true) Navigator.of(context).pop(true);
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
                kind: _SourceAddKind.webdav,
                title: 'WebDAV',
                icon: AppIcons.arrowsClockwise,
              ),
              _SourceAddOption(
                kind: _SourceAddKind.navidrome,
                title: 'Navidrome / Subsonic',
                icon: AppIcons.musicNotes,
              ),
              _SourceAddOption(
                kind: _SourceAddKind.baidu,
                title: '百度网盘',
                icon: AppIcons.cloud,
              ),
              _SourceAddOption(
                kind: _SourceAddKind.quark,
                title: '夸克网盘',
                icon: AppIcons.cloudDownload,
              ),
            ],
            onTap: (option) {
              switch (option.kind) {
                case _SourceAddKind.webdav:
                  _openWebDavAdd(context);
                  break;
                case _SourceAddKind.navidrome:
                  _openNavidromeAdd(context);
                  break;
                case _SourceAddKind.baidu:
                  _openCloudDriveAdd(context, CloudDriveProvider.baidu);
                  break;
                case _SourceAddKind.quark:
                  _openCloudDriveAdd(context, CloudDriveProvider.quark);
                  break;
              }
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
    final accent = colors.primary;
    return ListTile(
      minVerticalPadding: 16,
      leading: _SourceAddIcon(icon: option.icon, color: accent),
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
      trailing: Icon(AppIcons.chevronRight, color: colors.onSurfaceVariant),
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
        borderRadius: AppRadii.rPanel,
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
