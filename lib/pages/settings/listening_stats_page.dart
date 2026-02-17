import 'package:flutter/material.dart';

import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/player_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/common/setting_widgets.dart';
import '../../components/layout/base/app_page_scaffold.dart';
import '../../components/layout/base/app_top_bar.dart';
import '../../components/list/media_list_tile.dart';
import '../songs/song_detail_sheet.dart';

class ListeningStatsPage extends StatefulWidget {
  const ListeningStatsPage({super.key});

  @override
  State<ListeningStatsPage> createState() => _ListeningStatsPageState();
}

class _ListeningStatsPageState extends State<ListeningStatsPage> {
  final StatsService _statsService = StatsService.instance;
  final SongDao _songDao = SongDao();
  final PlayerService _player = PlayerService.instance;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  List<DayListeningStat> _monthStats = [];
  StatsTotals _totalStats = const StatsTotals(listenMs: 0, playCount: 0);
  List<_SongStatRow> _topSongs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final monthStats = await _statsService.fetchMonthStats(
      year: _month.year,
      month: _month.month,
    );
    final totalStats = await _statsService.fetchTotalStats();
    final topStats = await _statsService.fetchTopSongs(limit: 20);
    final songIds = topStats.map((e) => e.songId).toList();
    final songs = await _songDao.fetchByIds(songIds);
    final songMap = <String, SongEntity>{
      for (final song in songs) song.id: song,
    };
    final topSongs = topStats
        .map((stat) {
          final song = songMap[stat.songId];
          if (song == null) return null;
          return _SongStatRow(song: song, stat: stat);
        })
        .whereType<_SongStatRow>()
        .toList();
    if (!mounted) return;
    setState(() {
      _monthStats = monthStats;
      _totalStats = totalStats;
      _topSongs = topSongs;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  String _monthTitle(DateTime month) {
    return '${month.year}年${month.month.toString().padLeft(2, '0')}月';
  }

  String _formatDuration(int ms) {
    if (ms <= 0) return '0分钟';
    final totalMinutes = (ms / 60000).floor();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '$minutes分钟';
    return '$hours小时${minutes.toString().padLeft(2, '0')}分钟';
  }

  String _formatShortDuration(int ms) {
    if (ms <= 0) return '0:00';
    final totalSeconds = (ms / 1000).round();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = AppPageScaffold.scrollableBottomPadding(context);
    return AppPageScaffold(
      extendBodyBehindAppBar: true,
      appBar: const AppTopBar(
        title: '听歌统计',
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
          children: [
            _buildMonthHeader(context),
            const SizedBox(height: 12),
            _buildCalendar(context),
            const SizedBox(height: 16),
            _buildMonthSummary(context),
            const SizedBox(height: 16),
            _buildTotalSummary(context),
            const SizedBox(height: 16),
            _buildTopSongs(context),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  String _durationText(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '--:--';
    final totalSeconds = (durationMs / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildMonthHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _changeMonth(-1),
        ),
        Expanded(
          child: Text(
            _monthTitle(_month),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => _changeMonth(1),
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final theme = Theme.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final firstDay = DateTime(_month.year, _month.month, 1);
    final leadingEmpty = firstDay.weekday - 1;
    final totalCells = ((leadingEmpty + daysInMonth) / 7).ceil() * 7;
    final statsMap = {
      for (final stat in _monthStats) stat.dayKey: stat,
    };
    final maxListenMs =
        _monthStats.fold<int>(0, (max, stat) => stat.listenMs > max ? stat.listenMs : max);
    final labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Column(
      children: [
        Row(
          children: labels
              .map(
                (label) => Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            final dayNumber = index - leadingEmpty + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }
            final dayKey = _dayKey(DateTime(_month.year, _month.month, dayNumber));
            final stat = statsMap[dayKey];
            final ratio = maxListenMs == 0 || stat == null
                ? 0.0
                : (stat.listenMs / maxListenMs).clamp(0.0, 1.0);
            final hasListen = stat != null && stat.listenMs > 0;
            final bgColor = hasListen
                ? theme.colorScheme.primary.withValues(alpha: 0.18 + 0.62 * ratio)
                : Colors.transparent;
            final textColor = hasListen && ratio > 0.45
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface;
            return Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: hasListen
                    ? null
                    : Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.25),
                      ),
              ),
              child: Center(
                child: Text(
                  '$dayNumber',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMonthSummary(BuildContext context) {
    final totalListenMs =
        _monthStats.fold<int>(0, (sum, stat) => sum + stat.listenMs);
    final totalPlayCount =
        _monthStats.fold<int>(0, (sum, stat) => sum + stat.playCount);
    final daysListened =
        _monthStats.where((stat) => stat.listenMs > 0).length;
    return AppSettingSection(
      title: '本月概览',
      children: [
        _StatRow(label: '听歌天数', value: '$daysListened 天'),
        _StatRow(label: '听歌时长', value: _formatDuration(totalListenMs)),
        _StatRow(label: '播放次数', value: '$totalPlayCount 次'),
      ],
    );
  }

  Widget _buildTotalSummary(BuildContext context) {
    return AppSettingSection(
      title: '累计数据',
      children: [
        _StatRow(label: '听歌时长', value: _formatDuration(_totalStats.listenMs)),
        _StatRow(label: '播放次数', value: '${_totalStats.playCount} 次'),
      ],
    );
  }

  Widget _buildTopSongs(BuildContext context) {
    final queue = _topSongs.map((e) => e.song).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '高频歌曲',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Card(
          child: _topSongs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('暂无播放数据')),
                )
              : ValueListenableBuilder<SongEntity?>(
                  valueListenable: _player.currentSong,
                  builder: (context, current, _) {
                    return Column(
                      children: _topSongs.asMap().entries.map((entry) {
                        final row = entry.value;
                        final song = row.song;
                        final isPlaying = current?.id == song.id;
                        return MediaListTile(
                          leading: ArtworkWidget(
                            song: song,
                            size: 44,
                            borderRadius: 8,
                            placeholder: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                song.title.isEmpty
                                    ? '?'
                                    : song.title.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          title: song.title,
                          subtitle:
                              '${song.artist} · ${song.album ?? '未知专辑'} · ${_durationText(song.durationMs)}',
                          selected: false,
                          multiSelect: false,
                          isHighlighted: isPlaying,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${row.stat.playCount} 次',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                _formatShortDuration(row.stat.listenMs),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          onTap: () {
                            if (queue.isEmpty) return;
                            _player.playQueue(queue, entry.key);
                          },
                          onLongPress: () {
                            showModalBottomSheet<void>(
                              context: context,
                              backgroundColor: Colors.transparent,
                              isScrollControlled: true,
                              builder: (_) => SongDetailSheet(song: song),
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _dayKey(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingTile(
      title: label,
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SongStatRow {
  final SongEntity song;
  final SongListeningStat stat;

  const _SongStatRow({
    required this.song,
    required this.stat,
  });
}
