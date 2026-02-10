import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import 'package:vibe_music/widgets/app_toast.dart';
import '../models/music_entity.dart';
import '../viewmodels/library_viewmodel.dart';
import '../widgets/app_dialog.dart';
import 'library_page.dart';
import 'local/local_folder_browser.dart';
import 'webdav/webdav_folder_browser.dart';
import 'webdav/webdav_page.dart';

class SourcePage extends StatefulWidget {
  const SourcePage({super.key});

  @override
  State<SourcePage> createState() => _SourcePageState();
}

class _SourcePageState extends State<SourcePage> {
  final Set<String> _scanningSourceIds = {};

  void _openLocalSetting(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LibraryPage()),
    );
  }

  void _openWebDavSetting(BuildContext context, {MusicSource? source, bool isAdd = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WebDavPage(source: source, isAdd: isAdd)),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    if (items.isEmpty) return items;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      children.add(items[i]);
      if (i != items.length - 1) {
        children.add(const SizedBox(height: 6));
      }
    }
    return children;
  }

  Widget _sectionCard(BuildContext context, String title, List<Widget> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white70 : Colors.black87;
    final cardColor =
        isDark ? const Color(0xFF1F2329) : const Color.fromARGB(242, 255, 255, 255);
    final shadowColor = isDark
        ? const Color.fromARGB(28, 0, 0, 0)
        : const Color.fromARGB(15, 0, 0, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(children: _withDividers(items)),
        ),
      ],
    );
  }

  Widget _glow({
    required Alignment alignment,
    required double size,
    required List<Color> colors,
  }) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }

  int _getSongCount(LibraryViewModel vm, String sourceId) {
    return vm.allSongs.where((s) => s.sourceId == sourceId).length;
  }

  Future<void> _handleScan(BuildContext context, LibraryViewModel vm, MusicSource source) async {
    // If already scanning, just show the dialog again
    if (_scanningSourceIds.contains(source.id)) {
      _showScanDialog(context, vm, source);
      return;
    }

    setState(() {
      _scanningSourceIds.add(source.id);
    });

    _showScanDialog(context, vm, source);

    var addedCount = 0;
    try {
      addedCount = await vm.scanSource(source, notifyLoading: false);
    } finally {
      if (mounted) {
        setState(() {
          _scanningSourceIds.remove(source.id);
        });
      }
    }

    if (context.mounted) {
      AppToast.show(context, '成功添加 $addedCount 首歌', type: ToastType.success);
    }
  }

  void _showScanDialog(BuildContext context, LibraryViewModel vm, MusicSource source) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AppDialog(
        title: '正在扫描...',
        content: Watch.builder(builder: (context) {
          watchSignal(context, vm.scanTick);
          
          // Auto-close if scan finishes
          if (!_scanningSourceIds.contains(source.id)) {
             Future.microtask(() {
               if (ctx.mounted && Navigator.canPop(ctx)) {
                 Navigator.pop(ctx);
               }
             });
          }

          final processed = vm.scanProcessedCount;
          final added = vm.scanAddedCount;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text('已扫描: $processed'),
              const SizedBox(height: 4),
              Text('已添加: $added'),
            ],
          );
        },),
        cancelText: '取消',
        confirmText: '隐藏',
        isDestructive: true,
        onCancel: () {
          vm.cancelScan();
          Navigator.of(ctx).pop();
        },
        onConfirm: () {
           // Just hide (default behavior of AppDialog's confirm button is to pop)
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Watch.builder(builder: (context) {
      final vm = LibraryViewModel();
      watchSignal(context, vm.libraryTick);
      watchSignal(context, vm.scanTick);
      final local = vm.getOrCreateLocalSource();
      final webdavs = vm.sources.where((s) => s.type == MusicSourceType.webdav).toList();

      final isDark = Theme.of(context).brightness == Brightness.dark;
      final background = isDark
          ? const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1C1F24),
                Color(0xFF22262C),
                Color(0xFF1B1D22),
              ],
            )
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF6F7FB),
                Color(0xFFF7F3E8),
                Color(0xFFF1F7F4),
              ],
            );

      return Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () {
              final val = LibraryViewModel().isMenuOpen.value;
              LibraryViewModel().isMenuOpen.value = !val;
            },
          ),
          title: const Text(''),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _openWebDavSetting(context, isAdd: true),
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(gradient: background),
          child: Stack(
            children: [
              if (!isDark)
                _glow(
                  alignment: Alignment.topRight,
                  size: 260,
                  colors: [
                    const Color(0x66FDE2A7),
                    const Color(0x00FDE2A7),
                  ],
                ),
              if (!isDark)
                _glow(
                  alignment: Alignment.bottomLeft,
                  size: 240,
                  colors: [
                    const Color(0x66CBE8FF),
                    const Color(0x00CBE8FF),
                  ],
                ),
              SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
                  children: [
                    _sectionCard(
                      context,
                      '本地',
                      [
                        ListTile(
                          leading: const Icon(Icons.folder_open),
                          title: const Text('本地音乐'),
                          subtitle: Text('${_getSongCount(vm, local.id)} 首歌曲'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: _scanningSourceIds.contains(local.id)
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.sync),
                                onPressed: () => _handleScan(context, vm, local),
                                tooltip: '扫描本地音乐',
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings),
                                onPressed: () => _openLocalSetting(context),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LocalFolderBrowser(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    if (webdavs.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _sectionCard(
                        context,
                        '云端',
                        webdavs.map((source) {
                          return ListTile(
                            leading: const Icon(Icons.cloud),
                            title: Text(source.name.isNotEmpty ? source.name : 'WebDAV'),
                            subtitle: Text('${_getSongCount(vm, source.id)} 首歌曲'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: _scanningSourceIds.contains(source.id)
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.sync),
                                  onPressed: () => _handleScan(context, vm, source),
                                  tooltip: '扫描云端音乐',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.settings),
                                  onPressed: () =>
                                      _openWebDavSetting(context, source: source),
                                ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => WebDavFolderBrowser(source: source),
                                ),
                              );
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },);
  }
}
