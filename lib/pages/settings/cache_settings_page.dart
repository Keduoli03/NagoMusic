import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/haptic_service.dart';
import '../../app/services/log/log.dart';
import '../../app/services/storage/device_storage_service.dart';
import '../../app/services/storage/storage_sections.dart';
import '../../app/services/storage/storage_usage_service.dart';
import '../../app/state/settings_state.dart';
import '../../app/theme/tokens.dart';
import '../../app/utils/format_utils.dart';
import '../../components/index.dart';

/// 设置 → 存储与缓存：看清楚 App 占了多少、按类清理。
///
/// 存储类别本身来自 [_sections]（[appStorageSections]），这个页面只负责展示和
/// 触发清理，加/改一类存储去改 `storage_sections.dart`，不用动这里。
///
/// 顶部「本 App / 其他 App / 剩余可用」构成条依赖 [DeviceStorageService] 的原生
/// 桥，拿不到设备容量（桌面端/模拟器/iOS 未接桥）时退回「按类别构成」。
class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key, this.debugUsage, this.debugDevice});

  /// 测试注入：给定后跳过真实统计（测试环境没有 path_provider 平台实现，
  /// 拿不到任何真实数字，靠它才能把有数据的样子渲染出来）。
  @visibleForTesting
  final StorageUsage? debugUsage;

  @visibleForTesting
  final DeviceStorage? debugDevice;

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage>
    with SignalsMixin {
  static const String _logTag = 'CacheSettingsPage';

  late final List<StorageSection> _sections = appStorageSections();

  late final _usage = createSignal<StorageUsage?>(null);
  late final _device = createSignal<DeviceStorage?>(null);

  /// 正在清理的类别 key（清理期间该卡片显示转圈、按钮不可点）。
  late final _clearing = createSignal<String?>(null);

  @override
  void initState() {
    super.initState();
    AppCacheSettings.ensureLoaded();
    SongDownloadSettings.ensureLoaded();
    LibraryRefreshSettings.ensureLoaded();
    WebDavPlaybackSettings.ensureLoaded();
    _measure();
  }

  Future<void> _measure() async {
    if (widget.debugUsage != null) {
      _usage.value = widget.debugUsage;
      _device.value = widget.debugDevice;
      return;
    }
    final results = await Future.wait([
      StorageUsageService.measure(_sections),
      DeviceStorageService.capacity(),
    ]);
    if (!mounted) return;
    _usage.value = results[0] as StorageUsage;
    _device.value = results[1] as DeviceStorage?;
  }

  Future<void> _clear(StorageSection section) async {
    final confirmed = await AppDialog.showConfirm(
      context,
      title: section.confirmTitle,
      content: section.confirmMessage,
      confirmText: '清理',
      isDestructive: section.destructive,
      icon: AppIcons.trash,
    );
    if (confirmed != true || !mounted) return;

    _clearing.value = section.key;
    final before = _usage.value?.of(section.key) ?? 0;
    try {
      await section.clear();
    } catch (e, s) {
      AppLog.instance.w(_logTag, '清理存储分类失败，section=${section.key}', e, s);
      if (!mounted) return;
      _clearing.value = null;
      AppToast.show(context, '清理失败', type: ToastType.error);
      return;
    }
    // 先把数字刷新再收掉转圈：否则会有一瞬间显示"已清理但数字还是旧的"
    await _measure();
    if (!mounted) return;
    _clearing.value = null;
    Haptics.tap();
    AppToast.show(
      context,
      '已释放 ${formatFileSize(before, fractionDigits: 2, placeholder: '0 B')}',
      type: ToastType.success,
    );
  }

  Future<void> _pickDownloadDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.trim().isEmpty) return;
    await SongDownloadSettings.setCustomDirectoryPath(path);
    await SongDownloadSettings.setUseCustomDirectory(true);
    if (!mounted) return;
    AppToast.show(context, '已设置下载目录');
  }

  Future<void> _clearDownloadDirectory() async {
    await SongDownloadSettings.setUseCustomDirectory(false);
    await SongDownloadSettings.setCustomDirectoryPath(null);
    if (!mounted) return;
    AppToast.show(context, '已恢复为系统下载目录');
  }

  String _limitLabel(int gb) {
    if (gb <= 0) return '无限制';
    return '$gb GB';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    final c = AppColors.of(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '存储与缓存',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Watch.builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            bottomPadding,
          ),
          children: [
            _summary(context, c),
            AppSpacing.gapLg,
            for (final section in _sections) ...[
              _sectionCard(context, c, section),
              AppSpacing.gapMd,
            ],
            AppSpacing.gapSm,
            Text(
              '清理只删除本机缓存文件，不影响你的曲库数据、已下载歌曲与云端内容。',
              style: AppTypography.caption.on(c.muted),
            ),
            AppSpacing.gapLg,
            AppSettingSection(
              title: '缓存管理',
              children: [
                ValueListenableBuilder<int>(
                  valueListenable: AppCacheSettings.audioCacheLimitGb,
                  builder: (context, gb, _) {
                    final sliderValue = gb <= 0 ? 6.0 : gb.toDouble();
                    return AppSettingSlider(
                      title: '缓存上限',
                      description: '达到上限后会自动清理旧缓存',
                      value: sliderValue,
                      min: 1,
                      max: 6,
                      divisions: 5,
                      valueText: _limitLabel(gb),
                      onChanged: (value) {
                        final v = value.round();
                        AppCacheSettings.setAudioCacheLimitGb(v >= 6 ? 0 : v);
                      },
                    );
                  },
                ),
              ],
            ),
            AppSpacing.gapLg,
            AppSettingSection(
              title: '云端播放',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: WebDavPlaybackSettings.prefetchEnabled,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '预取下一首',
                      subtitle: '提前缓存下一首减少卡顿',
                      value: enabled,
                      onChanged: WebDavPlaybackSettings.setPrefetchEnabled,
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: WebDavPlaybackSettings.segmentedEnabled,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '分段并发下载',
                      subtitle: '提高弱网下缓存速度',
                      value: enabled,
                      onChanged: WebDavPlaybackSettings.setSegmentedEnabled,
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: WebDavPlaybackSettings.segmentedEnabled,
                  builder: (context, enabled, _) {
                    if (!enabled) return const SizedBox.shrink();
                    return ValueListenableBuilder<int>(
                      valueListenable:
                          WebDavPlaybackSettings.segmentConcurrency,
                      builder: (context, count, _) {
                        return AppSettingSlider(
                          title: '分段并发数',
                          description: '并发越高速度越快但更耗网络',
                          value: count.toDouble(),
                          min: 1,
                          max: 8,
                          divisions: 7,
                          valueText: '$count',
                          onChanged: (value) {
                            WebDavPlaybackSettings.setSegmentConcurrency(
                              value.round(),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            ),
            AppSpacing.gapLg,
            AppSettingSection(
              title: '下载设置',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: SongDownloadSettings.useCustomDirectory,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '使用自定义下载目录',
                      subtitle: enabled
                          ? '保存到你设置的文件夹'
                          : '默认保存到 Download/NagoMusic',
                      value: enabled,
                      onChanged: (value) async {
                        if (value &&
                            (SongDownloadSettings.customDirectoryPath.value ??
                                    '')
                                .trim()
                                .isEmpty) {
                          await _pickDownloadDirectory();
                          return;
                        }
                        await SongDownloadSettings.setUseCustomDirectory(value);
                      },
                    );
                  },
                ),
                ValueListenableBuilder<String?>(
                  valueListenable: SongDownloadSettings.customDirectoryPath,
                  builder: (context, pathValue, _) {
                    final subtitle =
                        (pathValue == null || pathValue.trim().isEmpty)
                        ? '未设置，当前使用 Download/NagoMusic'
                        : pathValue;
                    return AppSettingNavTile(
                      title: '下载路径',
                      subtitle: subtitle,
                      onTap: _pickDownloadDirectory,
                    );
                  },
                ),
                AppSettingTile(
                  title: '恢复默认下载路径',
                  subtitle: '切回系统 Download/NagoMusic 目录',
                  trailing: const Icon(AppIcons.refresh),
                  onTap: _clearDownloadDirectory,
                ),
              ],
            ),
            AppSpacing.gapLg,
            AppSettingSection(
              title: '启动刷新',
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable:
                      LibraryRefreshSettings.autoRefreshLocalOnLaunch,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '启动时刷新本地音源',
                      subtitle: '进入应用后自动检查本地是否有新增歌曲',
                      value: enabled,
                      onChanged: (value) {
                        LibraryRefreshSettings.setAutoRefreshLocalOnLaunch(
                          value,
                        );
                      },
                    );
                  },
                ),
                ValueListenableBuilder<bool>(
                  valueListenable:
                      LibraryRefreshSettings.autoRefreshCloudOnLaunch,
                  builder: (context, enabled, _) {
                    return AppSettingSwitchTile(
                      title: '启动时刷新云端音源',
                      subtitle: '进入应用后自动检查 WebDAV 是否有新增歌曲',
                      value: enabled,
                      onChanged: (value) {
                        LibraryRefreshSettings.setAutoRefreshCloudOnLaunch(
                          value,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部总览。
  ///
  /// 拿得到设备容量时画「本 App / 其他 App / 剩余可用」构成条；拿不到就退回
  /// 「本 App 内部按类别构成」，两种都不会出现空条。
  Widget _summary(BuildContext context, AppColors c) {
    final usage = _usage.value;
    final device = _device.value;
    final scheme = Theme.of(context).colorScheme;
    final total = usage?.total ?? 0;
    return SurfaceCard(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (device != null) ...[
            _deviceBar(context, c, device, total),
            AppSpacing.gapMd,
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                _legendDot(c, scheme.primary, '本应用已用'),
                _legendDot(c, _otherAppsTint(c), '其他 App 已用'),
                _legendDot(c, _freeTint(c), '手机剩余可用'),
              ],
            ),
            AppSpacing.gapXl,
          ],
          Text('本应用已用空间', style: AppTypography.caption.on(c.muted)),
          AppSpacing.gapXs,
          if (usage == null)
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                AppSpacing.wGapSm,
                Text('计算中…', style: AppTypography.title.on(c.muted)),
              ],
            )
          else ...[
            Text(
              formatFileSize(total, fractionDigits: 2, placeholder: '0 B'),
              style: AppTypography.display.on(c.text),
            ),
            if (device != null) ...[
              AppSpacing.gapXs,
              Text(
                '占手机 ${device.percentOf(total)}% 存储空间',
                style: AppTypography.caption.on(c.muted),
              ),
            ],
          ],
          if (device == null) ...[
            AppSpacing.gapLg,
            _categoryBar(c, usage),
            AppSpacing.gapMd,
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                for (var i = 0; i < _sections.length; i++)
                  _legendDot(
                    c,
                    _shadeOf(scheme, c, i),
                    '${_sections[i].title} '
                    '${formatFileSize(usage?.of(_sections[i].key), fractionDigits: 2, placeholder: '0 B')}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 「本 App / 其他 App / 剩余可用」三段条。
  ///
  /// 本 App 那段用的是各类之和，**这是可清理部分，不等于 App 的全部占用**
  /// （安装包体积、偏好设置这些都没算，两个平台也都没有免权限拿自身总占用的 API）。
  /// 差额会落进"其他 App"段里 —— 顶部条是给用户一个体量感，不是审计报表。
  Widget _deviceBar(
    BuildContext context,
    AppColors c,
    DeviceStorage device,
    int mine,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final mineClamped = mine.clamp(0, device.used);
    final others = device.used - mineClamped;
    return ClipRRect(
      borderRadius: AppRadii.rPill,
      child: SizedBox(
        height: AppSpacing.md,
        child: Row(
          // 必须 stretch：Row 默认 center，而 ColoredBox 没有 child 自身高度算作 0，
          // 三段会各自宽度正确但高度为 0 —— 表现就是"整条压根没渲染出来"。
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mineClamped > 0)
              Expanded(
                flex: _flex(mineClamped, device.total),
                child: ColoredBox(color: scheme.primary),
              ),
            if (others > 0)
              Expanded(
                flex: _flex(others, device.total),
                child: ColoredBox(color: _otherAppsTint(c)),
              ),
            if (device.free > 0)
              Expanded(
                flex: _flex(device.free, device.total),
                child: ColoredBox(color: _freeTint(c)),
              ),
          ],
        ),
      ),
    );
  }

  /// 千分比当 flex 用。
  ///
  /// 下限刻意给到 15‰ 而不是 1‰：512G 的手机上 App 占 1G 就是 2‰，按真实比例画出来
  /// 只有一两个物理像素，肉眼看就是"这条根本没画"。宁可让最小的那段略微失真，
  /// 也要让它看得见——这条的作用是"我在这台手机上占多大分量"，不是精确读数。
  static int _flex(int part, int total) =>
      total <= 0 ? 1 : (part * 1000 ~/ total).clamp(15, 1000);

  /// 其他 App 已用：中性灰，比强调色弱但必须清晰可辨。
  Color _otherAppsTint(AppColors c) => c.muted.withValues(alpha: 0.5);

  /// 剩余可用：条的"空槽"。
  /// **不能用 `c.line`**（很浅的描边色）——画在白卡片上几乎隐形，
  /// 手机剩余空间多的时候整条看着就像没渲染出来。
  Color _freeTint(AppColors c) => c.muted.withValues(alpha: 0.16);

  /// 降级条按顺序取强调色的同色阶。
  /// **不用多种彩色**：强调色只给品牌标识，多彩分类条既违规也没多少信息量。
  Color _shadeOf(ColorScheme scheme, AppColors c, int index) => switch (index) {
    0 => scheme.primary,
    1 => scheme.primary.withValues(alpha: 0.6),
    2 => scheme.primary.withValues(alpha: 0.35),
    _ => c.muted.withValues(alpha: 0.35),
  };

  /// 降级用的类别构成条。总量为 0（或还没算完）时画一条空槽，不留空白跳动。
  Widget _categoryBar(AppColors c, StorageUsage? usage) {
    final total = usage?.total ?? 0;
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: AppRadii.rPill,
      child: SizedBox(
        height: AppSpacing.sm,
        child: total <= 0
            ? ColoredBox(color: _freeTint(c))
            : Row(
                // 同 _deviceBar：不 stretch 的话 ColoredBox 高度为 0，条不可见
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    if (usage!.of(_sections[i].key) > 0)
                      Expanded(
                        flex: usage.of(_sections[i].key),
                        child: ColoredBox(color: _shadeOf(scheme, c, i)),
                      ),
                ],
              ),
      ),
    );
  }

  Widget _legendDot(AppColors c, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSpacing.sm,
          height: AppSpacing.sm,
          decoration: BoxDecoration(color: color, borderRadius: AppRadii.rPill),
        ),
        AppSpacing.wGapXs,
        Text(label, style: AppTypography.caption.on(c.muted)),
      ],
    );
  }

  Widget _sectionCard(
    BuildContext context,
    AppColors c,
    StorageSection section,
  ) {
    final usage = _usage.value;
    final bytes = usage?.of(section.key) ?? 0;
    final busy = _clearing.value == section.key;
    final canClear =
        section.clearable &&
        usage != null &&
        bytes > 0 &&
        _clearing.value == null;

    return SurfaceCard(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 层级：标题一行（按钮跟它对齐）→ 占用大小 → 灰色说明。
          // 大小紧跟标题（gapXs），不要拉开——中间空一截会让人以为是两块无关信息。
          Row(
            children: [
              Icon(section.icon, size: 20, color: c.text),
              AppSpacing.wGapSm,
              Expanded(
                child: Text(
                  section.title,
                  style: AppTypography.title.on(c.text),
                ),
              ),
              if (section.clearable) ...[
                AppSpacing.wGapSm,
                _clearButton(
                  context,
                  c,
                  section,
                  busy: busy,
                  enabled: canClear,
                ),
              ],
            ],
          ),
          AppSpacing.gapXs,
          if (usage == null)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              formatFileSize(bytes, fractionDigits: 2, placeholder: '0 B'),
              style: AppTypography.section.on(c.text),
            ),
          AppSpacing.gapSm,
          Text(section.description, style: AppTypography.caption.on(c.muted)),
        ],
      ),
    );
  }

  /// 清理按钮：可点时强调色实心 + 反色字（主 CTA），不可点时浅灰底 + muted 字。
  Widget _clearButton(
    BuildContext context,
    AppColors c,
    StorageSection section, {
    required bool busy,
    required bool enabled,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && !busy;
    return GestureDetector(
      onTap: active ? () => _clear(section) : null,
      child: Container(
        height: AppSpacing.xl + AppSpacing.sm,
        padding: AppSpacing.page,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? scheme.primary : c.muted.withValues(alpha: 0.12),
          borderRadius: AppRadii.rPill,
        ),
        child: busy
            // 实心底上的转圈必须是反色，用 muted 会糊成一团
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : Text(
                '清理',
                style: AppTypography.body.strong.on(
                  active ? scheme.onPrimary : c.muted,
                ),
              ),
      ),
    );
  }
}
