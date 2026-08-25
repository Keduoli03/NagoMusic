import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:flutter/material.dart';

import '../../app/router/app_router.dart';
import '../../app/services/app_update_service.dart';
import '../../app/services/log/log.dart';
import '../../app/state/settings_state.dart';
import '../../components/dialog/app_update_dialog.dart';
import '../../components/index.dart';

class VersionInfoPage extends StatefulWidget {
  const VersionInfoPage({super.key});

  @override
  State<VersionInfoPage> createState() => _VersionInfoPageState();
}

class _VersionInfoPageState extends State<VersionInfoPage> {
  static const String _logTag = 'VersionInfoPage';

  static const String _appName = 'NagoMusic';
  static const String _iconAsset = '开发文档/NagoAPP图标.png';

  bool _checking = false;
  String _version = '...';
  AppUpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    AppLaunchUpdateSettings.ensureLoaded();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await AppUpdateService.instance.currentVersion();
    if (!mounted) return;
    setState(() => _version = v);
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final current = await AppUpdateService.instance.currentVersion();
      final info = await AppUpdateService.instance.checkLatest(current);
      if (!mounted) return;
      setState(() => _updateInfo = info);
      if (info.hasUpdate) {
        await showAppUpdateDialog(context, info: info, currentVersion: current);
      } else {
        await showLatestVersionDialog(context, currentVersion: current);
      }
    } catch (e, s) {
      AppLog.instance.w(_logTag, '检查更新失败', e, s);
      if (!mounted) return;
      await showUpdateFailedDialog(context);
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '版本信息',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
        children: [
          AppSettingSection(
            title: '应用信息',
            children: [
              AppSettingTile(
                title: '应用名称',
                subtitle: _appName,
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    _iconAsset,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              AppSettingTile(
                title: '当前版本',
                subtitle: _version,
                leading: const Icon(AppIcons.info),
              ),
              AppSettingTile(
                title: '检查更新',
                subtitle: _updateSubtitle(),
                leading: const Icon(AppIcons.download),
                trailing: _checking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.chevronRight),
                onTap: _checking ? null : _checkUpdate,
              ),
              ValueListenableBuilder<bool>(
                valueListenable:
                    AppLaunchUpdateSettings.autoCheckUpdateOnLaunch,
                builder: (context, enabled, _) {
                  return AppSettingSwitchTile(
                    title: '启动时自动检查更新',
                    subtitle: '打开应用时在后台检查，有新版本会弹窗提示',
                    value: enabled,
                    onChanged:
                        AppLaunchUpdateSettings.setAutoCheckUpdateOnLaunch,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppSettingSection(
            title: '调试',
            children: [
              AppSettingNavTile(
                title: '日志',
                subtitle: '异常始终记录；开启调试模式后还会记录每一步操作',
                leading: const Icon(AppIcons.info),
                route: AppRoutes.debugLog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _updateSubtitle() {
    final info = _updateInfo;
    if (info == null) return '检查是否有新版本';
    if (info.hasUpdate) {
      return '发现新版本 ${info.latestVersion}';
    }
    return '当前已是最新版本';
  }
}
