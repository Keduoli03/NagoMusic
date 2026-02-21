import 'dart:async';

import 'package:flutter/material.dart';
import 'package:signals/signals.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../app/services/local_music_service.dart';
import '../../app/services/db/dao/song_dao.dart';
import '../../app/services/webdav/webdav_music_service.dart';
import '../../app/services/webdav/webdav_source_repository.dart';
import '../../components/index.dart';
import 'local/local_folder_browser.dart';
import 'local_source_settings_page.dart';
import 'webdav/webdav_edit_page.dart';
import 'webdav/webdav_folder_browser.dart';

enum SourceType { local, webdav }

class SourceItem {
  final String id;
  final String name;
  final SourceType type;
  final int songCount;

  const SourceItem({
    required this.id,
    required this.name,
    required this.type,
    required this.songCount,
  });
}

class _ScanProgress {
  final int processed;
  final int added;
  final int total;
  final bool isScanning;

  const _ScanProgress({
    required this.processed,
    required this.added,
    required this.total,
    required this.isScanning,
  });
}

class SourcePage extends StatefulWidget {
  const SourcePage({super.key});

  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> with SignalsMixin {
  final LocalMusicService _localService = LocalMusicService();
  final WebDavMusicService _webDavService = WebDavMusicService();
  final WebDavSourceRepository _webDavRepo = WebDavSourceRepository.instance;
  final SongDao _songDao = SongDao();
  final GlobalKey<AppPageScaffoldState> _scaffoldKey =
      GlobalKey<AppPageScaffoldState>();
  final Map<String, ValueNotifier<_ScanProgress>> _scanNotifiers = {};
  final Set<String> _scanRunning = {};
  final Map<String, bool> _scanCancelSignals = {};

  late final _localSongCount = createSignal(0);
  late final _webDavConfigs = createSignal<List<WebDavSource>>([]);
  late final _webDavSongCounts = createSignal<Map<String, int>>({});

  late final _sources = computed<List<SourceItem>>(() {
    final localCount = _localSongCount.value;
    final webdavConfigs = _webDavConfigs.value;
    final webdavCounts = _webDavSongCounts.value;
    return [
      SourceItem(
        id: 'local',
        name: '本地音乐',
        type: SourceType.local,
        songCount: localCount,
      ),
      ...webdavConfigs.map(
        (s) => SourceItem(
          id: s.id,
          name: s.name.trim().isNotEmpty ? s.name.trim() : 'WebDAV',
          type: SourceType.webdav,
          songCount: webdavCounts[s.id] ?? 0,
        ),
      ),
    ];
  });

  late final _localSources =
      computed<List<SourceItem>>(() => _sources.value
          .where((s) => s.type == SourceType.local)
          .toList());
  late final _webDavSourceItems =
      computed<List<SourceItem>>(() => _sources.value
          .where((s) => s.type == SourceType.webdav)
          .toList());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final notifier in _scanNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    await _loadLocalCount();
    await _loadWebDavSourcesAndCounts();
  }

  Future<void> _loadLocalCount() async {
    final count = await _localService.getLocalSongCount();
    if (!mounted) return;
    _localSongCount.value = count;
  }

  Future<void> _loadWebDavSourcesAndCounts() async {
    final sources = await _webDavRepo.loadSources();
    final entries = await Future.wait(
      sources.map(
        (s) async => MapEntry<String, int>(s.id, await _songDao.countBySource(s.id)),
      ),
    );
    final counts = {for (final e in entries) e.key: e.value};
    if (!mounted) return;
    _webDavConfigs.value = sources;
    _webDavSongCounts.value = counts;
  }

  ValueNotifier<_ScanProgress> _notifierFor(SourceItem source) {
    return _scanNotifiers.putIfAbsent(
      source.id,
      () => ValueNotifier<_ScanProgress>(
        const _ScanProgress(processed: 0, added: 0, total: 0, isScanning: false),
      ),
    );
  }

  bool _isScanning(SourceItem source) {
    return _scanRunning.contains(source.id);
  }

  void _showScanDialog(SourceItem source) {
    final notifier = _notifierFor(source);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return ValueListenableBuilder<_ScanProgress>(
          valueListenable: notifier,
          builder: (context, progress, child) {
            return SourceScanDialog(
              processed: progress.processed,
              added: progress.added,
              total: progress.total,
              isScanning: progress.isScanning,
              onCancel: () {
                _cancelScan(source);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              onHide: () {},
            );
          },
        );
      },
    );
  }

  void _startScan(SourceItem source) {
    if (source.type == SourceType.local) {
      _startLocalScan(source);
      return;
    }
    _startWebDavScan(source);
  }

  Future<void> _startLocalScan(SourceItem source) async {
    if (_scanRunning.contains(source.id)) {
      _showScanDialog(source);
      return;
    }

    _scanRunning.add(source.id);
    _scanCancelSignals[source.id] = false;
    final notifier = _notifierFor(source);
    notifier.value =
        const _ScanProgress(processed: 0, added: 0, total: 0, isScanning: true);
    _showScanDialog(source);

    final settings = await _localService.loadSettings();
    var lastTotal = 0;
    final result = await _localService.scan(
      settings: settings,
      isCancelled: () => _scanCancelSignals[source.id] == true,
      onProgress: (progress) {
        lastTotal = progress.total;
        notifier.value = _ScanProgress(
          processed: progress.processed,
          added: progress.added,
          total: progress.total,
          isScanning: true,
        );
      },
    );

    final cancelled = _scanCancelSignals[source.id] == true;
    _scanRunning.remove(source.id);
    _scanCancelSignals.remove(source.id);

    if (!mounted) return;
    if (cancelled) {
      notifier.value = _ScanProgress(
        processed: notifier.value.processed,
        added: notifier.value.added,
        total: lastTotal,
        isScanning: false,
      );
      AppToast.show(context, '已取消扫描');
      return;
    }

    await _localService.saveLastScanCount(result.added);
    if (!mounted) return;
    final count = await _localService.getLocalSongCount();
    if (!mounted) return;
    _localSongCount.value = count;
    notifier.value = _ScanProgress(
      processed: result.processed,
      added: result.added,
      total: lastTotal,
      isScanning: false,
    );
    AppToast.show(context, '成功添加 ${result.added} 首歌', type: ToastType.success);
  }

  Future<void> _startWebDavScan(SourceItem sourceItem) async {
    if (_scanRunning.contains(sourceItem.id)) {
      _showScanDialog(sourceItem);
      return;
    }
    final source = _webDavConfigs.value.firstWhere(
      (e) => e.id == sourceItem.id,
      orElse: () => const WebDavSource(
        id: '',
        name: 'WebDAV',
        endpoint: '',
        username: '',
        password: '',
        path: '/',
      ),
    );
    if (source.id.isEmpty) return;
    if (source.endpoint.trim().isEmpty) {
      AppToast.show(context, '请先配置 WebDAV 地址');
      await _openWebDavSetting(sourceItem);
      return;
    }

    _scanRunning.add(sourceItem.id);
    _scanCancelSignals[sourceItem.id] = false;
    final notifier = _notifierFor(sourceItem);
    notifier.value =
        const _ScanProgress(processed: 0, added: 0, total: 0, isScanning: true);
    _showScanDialog(sourceItem);

    final result = await _webDavService.scan(
      source: source,
      isCancelled: () => _scanCancelSignals[sourceItem.id] == true,
      onProgress: (progress) {
        notifier.value = _ScanProgress(
          processed: progress.processed,
          added: progress.added,
          total: progress.total,
          isScanning: true,
        );
      },
    );

    final cancelled = _scanCancelSignals[sourceItem.id] == true;
    _scanRunning.remove(sourceItem.id);
    _scanCancelSignals.remove(sourceItem.id);

    if (!mounted) return;
    if (cancelled) {
      notifier.value = _ScanProgress(
        processed: notifier.value.processed,
        added: notifier.value.added,
        total: notifier.value.total,
        isScanning: false,
      );
      AppToast.show(context, '已取消扫描');
      return;
    }

    await _loadWebDavSourcesAndCounts();
    if (!mounted) return;
    notifier.value = _ScanProgress(
      processed: result.processed,
      added: result.added,
      total: notifier.value.total,
      isScanning: false,
    );
    AppToast.show(context, '成功添加 ${result.added} 首歌', type: ToastType.success);
  }

  void _cancelScan(SourceItem source) {
    final notifier = _notifierFor(source);
    _scanCancelSignals[source.id] = true;
    notifier.value = _ScanProgress(
      processed: notifier.value.processed,
      added: notifier.value.added,
      total: notifier.value.total,
      isScanning: false,
    );
    AppToast.show(context, '已取消扫描');
  }

  void _openLocalSetting() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LocalSourceSettingsPage()),
    ).then((_) => _loadLocalCount());
  }

  Future<void> _openWebDavSetting(SourceItem source) async {
    final raw = _webDavConfigs.value.firstWhere(
      (e) => e.id == source.id,
      orElse: () => WebDavSource(
        id: source.id,
        name: source.name,
        endpoint: '',
        username: '',
        password: '',
        path: '/',
      ),
    );

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => WebDavEditPage(source: raw),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      await _loadWebDavSourcesAndCounts();
    }
  }

  Future<void> _openWebDavAdd() async {
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
      MaterialPageRoute(
        builder: (_) => WebDavEditPage(source: draft, isAdd: true),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      await _loadWebDavSourcesAndCounts();
    }
  }

  Future<void> _openSource(SourceItem source) async {
    if (source.type == SourceType.local) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LocalFolderBrowser()),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebDavFolderBrowser(
            sourceId: source.id,
            sourceName: source.name,
          ),
        ),
      );
    }
    if (mounted) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppTopBar(
        title: '音源',
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _openWebDavAdd,
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: SideMenu(
        onCloseDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
      ),
      body: Watch.builder(
        builder: (context) {
          final localSources = _localSources.value;
          final webDavSources = _webDavSourceItems.value;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
            children: [
              if (localSources.isNotEmpty)
                SourceSectionCard(
                  title: '本地',
                  children: localSources
                      .map(
                        (source) => SourceTile(
                          icon: Icons.folder_open,
                          title: source.name,
                          subtitle: '${source.songCount} 首歌曲',
                          actions: [
                            SourceTileAction(
                              icon: Icons.sync,
                              isLoading: _isScanning(source),
                              tooltip: '扫描本地音乐',
                              onTap: () => _startScan(source),
                            ),
                            SourceTileAction(
                              icon: Icons.settings,
                              tooltip: '设置',
                              onTap: _openLocalSetting,
                            ),
                          ],
                          onTap: () => _openSource(source),
                        ),
                      )
                      .toList(),
                ),
              if (webDavSources.isNotEmpty) ...[
                const SizedBox(height: 24),
                SourceSectionCard(
                  title: '云端',
                  children: webDavSources
                      .map(
                        (source) => SourceTile(
                          icon: Icons.cloud,
                          title: source.name,
                          subtitle: '${source.songCount} 首歌曲',
                          actions: [
                            SourceTileAction(
                              icon: Icons.sync,
                              isLoading: _isScanning(source),
                              tooltip: '扫描云端音乐',
                              onTap: () => _startScan(source),
                            ),
                            SourceTileAction(
                              icon: Icons.settings,
                              tooltip: '设置',
                              onTap: () => _openWebDavSetting(source),
                            ),
                          ],
                          onTap: () => _openSource(source),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
