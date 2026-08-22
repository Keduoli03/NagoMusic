import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services/app_update_service.dart';
import '../feedback/app_toast.dart';

Future<void> _openUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      AppToast.show(context, '无法打开浏览器，地址已复制');
    }
  }
}

/// Polished "update available" prompt. Shown for both manual checks and the
/// auto-check-on-launch flow.
Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppUpdateInfo info,
  required String currentVersion,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _UpdateAvailableDialog(info: info, currentVersion: currentVersion),
  );
}

/// "Already on the latest version" confirmation (manual check only).
Future<void> showLatestVersionDialog(
  BuildContext context, {
  required String currentVersion,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.verified_rounded, color: scheme.primary, size: 32),
      title: const Text('已是最新版本'),
      content: Text('当前版本 $currentVersion 已是最新版本。'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('好的'),
        ),
      ],
    ),
  );
}

/// "Check failed" dialog with manual fallbacks (manual check only).
Future<void> showUpdateFailedDialog(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.cloud_off_rounded, color: scheme.error, size: 30),
      title: const Text('检查更新失败'),
      content: const Text('无法连接更新服务，请检查网络后重试，或手动打开发布页面。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              const ClipboardData(text: AppUpdateService.releasePageUrl),
            );
            if (!context.mounted) return;
            Navigator.pop(context);
            AppToast.show(context, '更新地址已复制');
          },
          child: const Text('复制地址'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            _openUrl(context, AppUpdateService.releasePageUrl);
          },
          child: const Text('手动打开'),
        ),
      ],
    ),
  );
}

class _UpdateAvailableDialog extends StatelessWidget {
  final AppUpdateInfo info;
  final String currentVersion;

  const _UpdateAvailableDialog({
    required this.info,
    required this.currentVersion,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notes = (info.releaseNotes ?? '').trim();
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '发现新版本',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (info.releaseName != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            info.releaseName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  _VersionChip(label: currentVersion, dim: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  _VersionChip(label: info.latestVersion, dim: false),
                ],
              ),
            ),
            if (notes.isNotEmpty)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 240),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        notes,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: scheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('稍后'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openUrl(
                        context,
                        info.releaseUrl ?? AppUpdateService.releasePageUrl,
                      );
                    },
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('前往下载'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  final String label;
  final bool dim;

  const _VersionChip({required this.label, required this.dim});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dim
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: dim
            ? null
            : Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: dim ? scheme.onSurfaceVariant : scheme.primary,
        ),
      ),
    );
  }
}
