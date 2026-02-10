import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/cache/cache_manager.dart';
import '../core/database/database_helper.dart';
import '../models/music_entity.dart';
import '../pages/albums/albums_page.dart';
import '../pages/artists/artists_page.dart';
import '../services/tag_probe_service.dart';
import '../utils/remote_metadata_helper.dart';
import '../viewmodels/library_viewmodel.dart';
import '../viewmodels/player_viewmodel.dart';
import 'app_dialog.dart';
import 'app_list_tile.dart';
import 'app_toast.dart';
import 'artwork_widget.dart';

class SongDetailSheet extends StatelessWidget {
  final MusicEntity song;

  const SongDetailSheet({super.key, required this.song});

  static void show(BuildContext context, MusicEntity song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      builder: (context) => SongDetailSheet(song: song),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = theme.scaffoldBackgroundColor;
    final secondaryTextColor =
        isDark ? Colors.white70 : const Color.fromARGB(255, 100, 100, 100);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  ArtworkWidget(
                    song: song,
                    size: 52,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${song.artist}${song.album != null && song.album!.isNotEmpty ? ' · ${song.album}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 0.6),
            AppListTile(
              leading: const Icon(Icons.queue_play_next),
              title: '下一首播放',
              onTap: () async {
                Navigator.of(context).pop();
                await PlayerViewModel().playNextFromLibrary(song);
              },
            ),
            AppListTile(
              leading: const Icon(Icons.add_to_photos_outlined),
              title: '添加到歌单',
              onTap: () {
                Navigator.of(context).pop();
                _showAddToPlaylistDialog(context, song);
              },
            ),
            AppListTile(
              leading: const Icon(Icons.person),
              title: '艺术家：${song.artist}',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArtistDetailPage(artistName: song.artist),
                  ),
                );
              },
            ),
            if (song.album != null && song.album!.isNotEmpty && song.album != '未知专辑')
              AppListTile(
                leading: const Icon(Icons.album),
                title: '专辑：${song.album}',
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailPage(albumName: song.album!),
                    ),
                  );
                },
              ),
            AppListTile(
              leading: const Icon(Icons.info_outline),
              title: '歌曲信息',
              onTap: () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => _SongInfoSheet(song: song),
                );
              },
            ),
            AppListTile(
              leading: const Icon(Icons.refresh),
              title: '刮削信息',
              onTap: () async {
                Navigator.of(context).pop();
                final cleared = await _clearScrapeInfo(context, song, showToast: false);
                if (!context.mounted) return;
                await _rescrapeSong(context, cleared);
              },
            ),
            AppListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: '移除歌曲',
              titleColor: Colors.red,
              onTap: () {
                Navigator.of(context).pop();
                _deleteSong(context, song);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddToPlaylistDialog(BuildContext context, MusicEntity song) async {
    final vm = LibraryViewModel();
    final playlists = vm.playlists;

    await showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: '添加到歌单',
          confirmText: '新建歌单',
          onConfirm: () {
            // Wait for current dialog to close before showing the new one
            Future.delayed(const Duration(milliseconds: 100), () {
              if (context.mounted) {
                _showCreatePlaylistDialog(context, song);
              }
            });
          },
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: playlists.isEmpty 
              ? const Center(child: Text('暂无歌单', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return AppListTile(
                      leading: Icon(
                         playlist.isFavorite ? Icons.favorite : Icons.queue_music,
                        color: playlist.isFavorite ? Colors.red : Theme.of(context).iconTheme.color?.withAlpha(179),
                      ),
                      title: playlist.name,
                      subtitle: '${playlist.songCount ?? 0} 首',
                      onTap: () async {
                        await vm.addSongToPlaylist(playlist.id, song.id);
                        if (context.mounted) {
                          Navigator.pop(context);
                          AppToast.show(context, '已添加到歌单: ${playlist.name}', type: ToastType.success);
                        }
                      },
                    );
                  },
                ),
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, MusicEntity song) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AppDialog(
          title: '新建歌单',
          confirmText: '创建',
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '请输入歌单名称',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (value) => _handleCreatePlaylist(context, controller, song),
          ),
          onConfirm: () => _handleCreatePlaylist(context, controller, song),
        );
      },
    );
  }

  Future<void> _handleCreatePlaylist(BuildContext context, TextEditingController controller, MusicEntity song) async {
    final name = controller.text.trim();
    if (name.isNotEmpty) {
      final vm = LibraryViewModel();
      final id = await vm.createPlaylist(name);
      await vm.addSongToPlaylist(id, song.id);
      
      if (context.mounted) {
        // AppDialog closes automatically via its onConfirm wrapper
        AppToast.show(context, '已创建并添加到: $name', type: ToastType.success);
      }
    }
  }

  Future<MusicEntity> _clearScrapeInfo(BuildContext context, MusicEntity song, {bool showToast = true}) async {
    try {
      final cache = CacheManager();
      final coverPath = await cache.getCoverPath(song.id);
      final file = File(coverPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    
    // Clear memory cache to prevent immediate reloading of stale/null data
    TagProbeService.clearMemoryCache(song.id);

    final updated = song.copyWith(
      localCoverPath: null,
      artwork: null,
      lyrics: null,
      tagsParsed: false, // Force re-parsing on next attempt
    );
    final db = DatabaseHelper();
    await db.insertSong(updated);
    LibraryViewModel().updateSongInLibrary(updated);
    if (showToast && context.mounted) {
      AppToast.show(context, '已删除刮削信息', type: ToastType.success);
    }
    return updated;
  }

  Future<void> _rescrapeSong(BuildContext context, MusicEntity song) async {
    TagProbeService.clearMemoryCache(song.id);
    AppToast.show(null, '开始刮削');
    final ok = await PlayerViewModel().fetchRemoteEmbeddedTags(song, force: true);
    AppToast.show(
      null, 
      ok ? '已更新' : '没找到', 
      type: ok ? ToastType.success : ToastType.info,
    );
  }

  Future<void> _deleteSong(BuildContext context, MusicEntity song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除歌曲'),
        content: const Text('确定要将这首歌曲从媒体库中移除吗？\n(本地文件不会被删除，仅移除数据库记录)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LibraryViewModel().deleteSongs([song.id]);
      if (context.mounted) {
        Navigator.pop(context); // Close sheet
      }
      AppToast.show(null, '已移除歌曲', type: ToastType.success);
    }
  }

}

class _SongInfoSheet extends StatefulWidget {
  final MusicEntity song;
  const _SongInfoSheet({required this.song});

  @override
  State<_SongInfoSheet> createState() => _SongInfoSheetState();
}

class _SongInfoSheetState extends State<_SongInfoSheet> {
  late Map<String, String> _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _info = {
      '标题': widget.song.title,
      '艺术家': widget.song.artist,
      '专辑': widget.song.album ?? '未知',
      '来源': widget.song.isLocal ? '本地' : '云端 (WebDAV)',
      '时长': _formatDuration(widget.song.durationMs ?? 0),
      '格式': widget.song.uri?.split('.').last.toUpperCase() ?? '未知',
    };
    _loadExtendedInfo();
  }

  Future<void> _loadExtendedInfo() async {
    final song = widget.song;
    
    if (song.isLocal && song.uri != null) {
      try {
        final file = File(song.uri!);
        if (await file.exists()) {
           if (mounted) {
             setState(() {
               _info['大小'] = _formatFileSize(file.lengthSync());
             });
           }
           try {
             // Try to get extended metadata using audio_metadata_reader
            final metadata = readMetadata(file, getImage: false);
             if (mounted) {
               setState(() {
                 if (metadata.bitrate != null) {
                   _info['比特率'] = '${(metadata.bitrate! / 1000).round()} kbps';
                 }
                 if (metadata.sampleRate != null) {
                   _info['采样率'] = '${(metadata.sampleRate! / 1000).toStringAsFixed(1)} kHz';
                 }
                 if (metadata.year != null) {
                   _info['年份'] = metadata.year!.year.toString();
                 }
                 if (metadata.genres.isNotEmpty) {
                   _info['流派'] = metadata.genres.join(', ');
                 }
               });
             }
           } catch (e) {
             debugPrint('Error reading extended metadata: $e');
           }
        }
      } catch (e) {
         debugPrint('Error accessing file: $e');
      }
    } else if (!song.isLocal && song.uri != null) {
      // Remote logic
      if (song.bitrate != null && song.fileSize != null) {
         if (mounted) {
            setState(() {
              _info['大小'] = _formatFileSize(song.fileSize!);
              _info['比特率'] = '${(song.bitrate! / 1000).round()} kbps';
              _info['采样率'] = '${(song.sampleRate! / 1000).toStringAsFixed(1)} kHz';
              _info['格式'] = song.format ?? '未知';
            });
         }
      } else {
        // Try to read from local cache first
        RemoteMetadata? metadata;
        try {
          final cacheDir = await CacheManager().getAudioCachePath();
          // Derive extension from URI to match cache naming convention
          final uri = Uri.parse(song.uri!);
          String ext = p.extension(uri.path);
          if (ext.startsWith('.')) ext = ext.substring(1);
          if (ext.isEmpty) ext = 'mp3';
          
          final cachePath = p.join(cacheDir, '${song.id.hashCode}.$ext');
          final cacheFile = File(cachePath);
          final completeFile = File('$cachePath.complete');
          
          if (await cacheFile.exists() && await completeFile.exists()) {
            final audioMeta = readMetadata(cacheFile, getImage: false);
            final size = await cacheFile.length();
            metadata = RemoteMetadata(
              fileSize: size,
              bitrate: audioMeta.bitrate,
              sampleRate: audioMeta.sampleRate,
              format: ext.toUpperCase(),
              duration: audioMeta.duration,
            );
          }
        } catch (e) {
          debugPrint('Failed to read from local cache: $e');
        }

        // Fallback to remote fetch if local cache failed or didn't exist
        final effectiveMetadata = metadata ?? await RemoteMetadataHelper.fetch(song);

        if (mounted) {
          setState(() {
            if (effectiveMetadata.fileSize != null) _info['大小'] = _formatFileSize(effectiveMetadata.fileSize!);
            if (effectiveMetadata.bitrate != null) _info['比特率'] = '${(effectiveMetadata.bitrate! / 1000).round()} kbps';
            if (effectiveMetadata.sampleRate != null) _info['采样率'] = '${(effectiveMetadata.sampleRate! / 1000).toStringAsFixed(1)} kHz';
            if (effectiveMetadata.format != null) _info['格式'] = effectiveMetadata.format!;
            if (effectiveMetadata.duration != null) _info['时长'] = _formatDuration(effectiveMetadata.duration!.inMilliseconds);
          });
        }
        
        // Save to DB
        if (effectiveMetadata.bitrate != null || effectiveMetadata.fileSize != null || effectiveMetadata.duration != null) {
           final updated = song.copyWith(
             fileSize: effectiveMetadata.fileSize ?? song.fileSize,
             bitrate: effectiveMetadata.bitrate ?? song.bitrate,
             sampleRate: effectiveMetadata.sampleRate ?? song.sampleRate,
             format: effectiveMetadata.format ?? song.format,
             durationMs: effectiveMetadata.duration?.inMilliseconds ?? song.durationMs,
           );
           await DatabaseHelper().updateMusic(updated);
           LibraryViewModel().updateSongInLibrary(updated);
        }
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '未知';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double v = bytes.toDouble();
    while (v >= 1024 && i < suffixes.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(2)} ${suffixes[i]}';
  }
  
  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '歌曲信息',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_loading) ...[
                    const SizedBox(width: 8),
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: _info.entries.map((e) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        e.key,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      subtitle: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      onTap: () {},
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
