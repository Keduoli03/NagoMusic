import 'package:flutter/material.dart';

import '../../app/services/log/log.dart';
import '../../app/services/lyrics/lyrics_service.dart';
import '../../app/services/online_meta/online_metadata_service.dart';
import '../../app/services/online_meta/vkeys_music_api.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_icons.dart';
import '../../app/theme/app_radii.dart';
import '../../components/index.dart';

/// 在线匹配面板：搜 QQ 音乐，把歌名 / 歌手 / 专辑 / 封面 / 歌词写回本地歌曲。
///
/// 打开时用当前歌曲自动搜一次；搜不准就改关键词重搜。选中一条即应用，
/// 面板返回更新后的 [SongEntity]（没应用任何东西则返回 null）。
class OnlineMatchSheet extends StatefulWidget {
  final SongEntity song;

  const OnlineMatchSheet({super.key, required this.song});

  static Future<SongEntity?> show(BuildContext context, SongEntity song) {
    return showModalBottomSheet<SongEntity>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OnlineMatchSheet(song: song),
    );
  }

  @override
  State<OnlineMatchSheet> createState() => _OnlineMatchSheetState();
}

class _OnlineMatchSheetState extends State<OnlineMatchSheet> {
  static const String _logTag = 'OnlineMatchSheet';

  final OnlineMetadataService _service = OnlineMetadataService.instance;
  final TextEditingController _queryCtrl = TextEditingController();

  List<VkeysSong> _results = const [];
  bool _searching = false;
  bool _applying = false;
  String? _applyingKey;
  bool _searched = false;

  OnlineMatchOptions _options = const OnlineMatchOptions();

  @override
  void initState() {
    super.initState();
    _queryCtrl.text = _service.buildQuery(widget.song);
    _search();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _queryCtrl.text.trim();
    if (keyword.isEmpty) {
      setState(() {
        _results = const [];
        _searched = true;
      });
      return;
    }

    setState(() => _searching = true);
    try {
      final results = await _service.search(keyword);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  /// 从当前这批结果里挑最像的直接应用；不够像就不动，让用户自己选。
  Future<void> _applyBest() async {
    final best = _service.pickBest(_results, widget.song);
    if (best == null) {
      AppToast.show(context, '没有足够接近的结果，请手动选一条', type: ToastType.info);
      return;
    }
    await _apply(best);
  }

  Future<void> _apply(VkeysSong match) async {
    if (_options.isNoop) {
      AppToast.show(context, '至少要选一项要覆盖的内容', type: ToastType.error);
      return;
    }

    setState(() {
      _applying = true;
      _applyingKey = _keyOf(match);
    });
    try {
      final outcome = await _service.apply(
        song: widget.song,
        match: match,
        options: _options,
      );
      if (!mounted) return;

      if (!outcome.anythingApplied) {
        AppToast.show(context, '这条没能取到可用内容', type: ToastType.error);
        return;
      }

      // 歌词换了就让歌词页重新读一次，否则播放中的那首还显示旧词。
      if (outcome.lyricsApplied) {
        LyricsService.instance.reloadCurrentSong();
      }

      // 标题/歌手/封面改了，同步进播放器的内存状态——不然这首歌正在播的话，
      // 迷你播放条、通知栏、状态栏歌词、以及退出重进的播放页，读到的还是旧
      // 实例（没封面）。是不是当前播放项由 refreshSongMetadata 自己判断，
      // 不是就什么都不做，这里不用先查一遍。
      if (outcome.infoApplied || outcome.coverApplied) {
        PlayerService.instance.refreshSongMetadata(outcome.song);
      }

      AppToast.show(context, _summarize(outcome), type: ToastType.success);
      Navigator.pop(context, outcome.song);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '应用在线匹配失败 songId=${widget.song.id}', e, s);
      if (!mounted) return;
      AppToast.show(context, '匹配失败，请重试', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _applyingKey = null;
        });
      }
    }
  }

  String _summarize(OnlineMatchOutcome outcome) {
    final parts = <String>[
      if (outcome.infoApplied) '信息',
      if (outcome.coverApplied) '封面',
      if (outcome.lyricsApplied) '歌词',
    ];
    return '已更新${parts.join(' / ')}';
  }

  String _keyOf(VkeysSong song) =>
      song.mid.isNotEmpty ? song.mid : '${song.id}';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final busy = _searching || _applying;

    return AppSheetPanel(
      title: '在线匹配',
      expand: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryCtrl,
                    enabled: !_applying,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    style: TextStyle(fontSize: 15, color: c.text),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: c.mediaBg,
                      hintText: '歌名，可加歌手',
                      hintStyle: TextStyle(fontSize: 15, color: c.muted),
                      prefixIcon: Icon(
                        AppIcons.search,
                        size: 18,
                        color: c.muted,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: const OutlineInputBorder(
                        borderRadius: AppRadii.rPanel,
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: busy ? null : _search,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _OptionChip(
                  label: '信息',
                  selected: _options.applyInfo,
                  enabled: !busy,
                  onTap: () => setState(() {
                    _options = _options.copyWith(
                      applyInfo: !_options.applyInfo,
                    );
                  }),
                ),
                const SizedBox(width: 8),
                _OptionChip(
                  label: '封面',
                  selected: _options.applyCover,
                  enabled: !busy,
                  onTap: () => setState(() {
                    _options = _options.copyWith(
                      applyCover: !_options.applyCover,
                    );
                  }),
                ),
                const SizedBox(width: 8),
                _OptionChip(
                  label: '歌词',
                  selected: _options.applyLyrics,
                  enabled: !busy,
                  onTap: () => setState(() {
                    _options = _options.copyWith(
                      applyLyrics: !_options.applyLyrics,
                    );
                  }),
                ),
                const Spacer(),
                if (_results.isNotEmpty)
                  TextButton(
                    onPressed: busy ? null : _applyBest,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('自动选最佳'),
                  )
                else
                  Flexible(
                    child: Text(
                      '选中一条即应用',
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Expanded(child: _buildBody(c)),
        ],
      ),
    );
  }

  Widget _buildBody(AppColors c) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_searched) {
      return const SizedBox.shrink();
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '没搜到结果。\n试试只用歌名，或者换个关键词。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: c.muted, height: 1.6),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        0,
        4,
        0,
        MediaQuery.viewPaddingOf(context).bottom + 16,
      ),
      itemCount: _results.length,
      separatorBuilder: (_, _) =>
          Divider(height: 0.5, thickness: 0.5, indent: 76, color: c.line),
      itemBuilder: (context, index) {
        final item = _results[index];
        return _ResultTile(
          song: item,
          busy: _applying,
          working: _applyingKey == _keyOf(item),
          onTap: () => _apply(item),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final VkeysSong song;
  final bool busy;
  final bool working;
  final VoidCallback onTap;

  const _ResultTile({
    required this.song,
    required this.busy,
    required this.working,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final subtitle = [
      if (song.singer.isNotEmpty) song.singer,
      if (song.album.isNotEmpty) song.album,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: AppRadii.rChip,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: song.cover.isEmpty
                      ? ColoredBox(
                          color: c.mediaBg,
                          child: Icon(
                            AppIcons.musicNote,
                            size: 20,
                            color: c.muted,
                          ),
                        )
                      : Image.network(
                          song.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: c.mediaBg,
                            child: Icon(
                              AppIcons.musicNote,
                              size: 20,
                              color: c.muted,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.song,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (working)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  song.interval,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? accent.withValues(alpha: 0.14) : c.mediaBg,
      borderRadius: AppRadii.rPill,
      child: InkWell(
        borderRadius: AppRadii.rPill,
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? AppIcons.checkCircle : AppIcons.circle,
                size: 15,
                color: selected ? accent : c.muted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? accent : c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
