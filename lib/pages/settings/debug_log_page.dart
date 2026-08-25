import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/services/log/log.dart';
import '../../app/theme/tokens.dart';
import '../../components/index.dart';

/// 日志页。
///
/// 从「版本信息」里独立出来，原因是日志现在有级别、有堆栈、有过滤，塞在版本
/// 信息页的一个 300px 高的小框里根本读不了。
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

enum _LogFilter {
  all('全部'),
  problem('仅异常');

  const _LogFilter(this.label);

  final String label;
}

class _DebugLogPageState extends State<DebugLogPage> {
  final AppLog _logs = AppLog.instance;

  _LogFilter _filter = _LogFilter.all;
  final Set<int> _expanded = <int>{};

  @override
  void initState() {
    super.initState();
    _logs.ensureLoaded();
  }

  Future<void> _clear() async {
    await _logs.clear();
    if (!mounted) return;
    setState(_expanded.clear);
    AppToast.show(context, '日志已清空');
  }

  Future<void> _copy() async {
    final text = await _logs.exportText();
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppToast.show(context, '日志已复制');
  }

  Future<void> _export() async {
    final text = await _logs.exportText();
    final now = DateTime.now();
    final filename =
        'nagomusic-log-${now.year}${_two(now.month)}${_two(now.day)}'
        '-${_two(now.hour)}${_two(now.minute)}${_two(now.second)}.txt';
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsString(text, flush: true);
    if (!mounted) return;
    await _showExportedDialog(file.path);
  }

  Future<void> _showExportedDialog(String path) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AppDialog(
        title: '日志已导出',
        content: SelectableText(path, style: AppTypography.caption),
        cancelText: '复制路径',
        confirmText: '打开文件',
        onCancel: () => Navigator.of(context).pop(false),
        onConfirm: () {},
      ),
    );
    if (!mounted || open == null) return;
    if (open) {
      await _openFile(path);
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    AppToast.show(context, '文件路径已复制');
  }

  Future<void> _openFile(String path) async {
    final uri = Uri.file(path);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    AppToast.show(context, '无法打开文件，路径已复制');
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      appBar: AppTopBar(
        title: '日志',
        actions: [
          IconButton(
            icon: const Icon(AppIcons.copy),
            tooltip: '复制全部',
            onPressed: _copy,
          ),
          IconButton(
            icon: const Icon(AppIcons.download),
            tooltip: '导出为文件',
            onPressed: _export,
          ),
          IconButton(
            icon: const Icon(AppIcons.trash),
            tooltip: '清空',
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppSpacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSpacing.gapSm,
                ValueListenableBuilder<bool>(
                  valueListenable: _logs.verbose,
                  builder: (context, verbose, _) {
                    return AppSettingSection(
                      children: [
                        AppSettingSwitchTile(
                          title: '调试模式',
                          subtitle: '开启后记录每一步操作；关闭时仍然记录警告和异常',
                          value: verbose,
                          onChanged: _logs.setVerbose,
                        ),
                      ],
                    );
                  },
                ),
                AppSpacing.gapMd,
                _buildFilterBar(context),
                AppSpacing.gapSm,
              ],
            ),
          ),
          Expanded(child: _buildList(context)),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return SegmentedButton<_LogFilter>(
      segments: [
        for (final value in _LogFilter.values)
          ButtonSegment<_LogFilter>(value: value, label: Text(value.label)),
      ],
      selected: {_filter},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        setState(() => _filter = selection.first);
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<LogEntry>>(
      valueListenable: _logs.entries,
      builder: (context, all, _) {
        final visible = _filter == _LogFilter.problem
            ? all.where((entry) => entry.level.isProblem).toList()
            : all;
        if (visible.isEmpty) {
          return Center(
            child: Text(
              _filter == _LogFilter.problem ? '没有记录到异常' : '暂无日志',
              style: AppTypography.body.on(scheme.onSurfaceVariant),
            ),
          );
        }
        final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
        return Scrollbar(
          child: ListView.separated(
            padding: AppSpacing.pageBottom(bottomPadding),
            // 最新的在最上面。
            itemCount: visible.length,
            separatorBuilder: (_, _) => Divider(
              height: AppSpacing.md,
              thickness: 0.5,
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            itemBuilder: (context, index) {
              final entry = visible[visible.length - 1 - index];
              return _LogTile(
                entry: entry,
                expanded: _expanded.contains(entry.hashCode),
                onToggle: () => setState(() {
                  final key = entry.hashCode;
                  if (!_expanded.remove(key)) _expanded.add(key);
                }),
              );
            },
          ),
        );
      },
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.entry,
    required this.expanded,
    required this.onToggle,
  });

  final LogEntry entry;
  final bool expanded;
  final VoidCallback onToggle;

  Color _levelColor(ColorScheme scheme) => switch (entry.level) {
    LogLevel.error => scheme.error,
    LogLevel.warn => scheme.tertiary,
    LogLevel.info => scheme.primary,
    LogLevel.debug => scheme.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _levelColor(scheme);
    final mono = AppTypography.micro.copyWith(fontFamily: 'monospace');

    return InkWell(
      onTap: entry.hasDetail ? onToggle : null,
      borderRadius: AppRadii.rCard,
      child: Padding(
        padding: AppSpacing.cardTight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: AppSpacing.badge,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: AppRadii.rBadge,
                  ),
                  child: Text(
                    entry.level.code,
                    style: AppTypography.badge.on(color),
                  ),
                ),
                AppSpacing.wGapSm,
                Expanded(
                  child: Text(
                    entry.tag,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption
                        .on(scheme.onSurface)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(entry.clock, style: mono.on(scheme.onSurfaceVariant)),
                if (entry.hasDetail) ...[
                  AppSpacing.wGapXs,
                  Icon(
                    expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                    size: AppSpacing.md,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            AppSpacing.gapXs,
            SelectableText(
              entry.message,
              style: mono.on(scheme.onSurface.withValues(alpha: 0.9)),
            ),
            if (entry.hasDetail && expanded) ...[
              AppSpacing.gapXs,
              Container(
                width: double.infinity,
                padding: AppSpacing.cardTight,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: AppRadii.rChip,
                ),
                child: SelectableText(
                  entry.detail!,
                  style: mono.on(scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
