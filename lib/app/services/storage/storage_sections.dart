import 'dart:io';
import 'package:nagomusic/app/theme/app_icons.dart';

import 'package:media_cache/media_cache.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../bili/bili_music_service.dart';
import '../db/db_constants.dart';
import '../../state/settings_cache_state.dart';
import 'storage_usage_service.dart';

/// 「存储与缓存」页在本项目里管哪几类 —— **这份就是你要改的文件**。
///
/// 加了新的缓存目录（引入新的三方库、新加一个音源……）就往下加一条
/// [StorageSection]，页面自动多一张卡，不用动 `cache_settings_page.dart`。
///
/// ⚠️ 两条铁律：
/// 1. `tag_probe_cache`、`bili_covers` 这两个目录以前**没有**出现在这份清单里——
///    旧版「清空全部缓存」只清了音频/封面/歌词三类，元数据探测缓存和 B 站封面
///    缓存一直在悄悄攒着，用户点了"已清除"空间却降不了多少，这就是那个 bug 的
///    根源。加类别时优先去翻各 service 里实际落盘的目录，别只抄旧页面的清单。
/// 2. `database` 和 `downloads` 两类 `clearable: false`——数据库存的是播放列表
///    和统计数据，删了找不回来（有单独的「数据备份」流程做这件事）；下载的歌曲
///    是通过 MediaStore 落进公共 Download 目录的用户财产，不是缓存。它们仍然
///    参与总占用和构成条统计，只是不给通用「清理」按钮删除它们的权力。

/// 已下载歌曲落地的公共目录（未启用自定义下载目录时）。
///
/// Android 上没有免权限的 API 能直接拿到「公共 Download 目录」路径（写入走的
/// 是 MediaStore，见 `MainActivity.saveToDownloads`），这里只是按标准布局猜一个
/// 路径去读；读不到就说明没有存储权限或路径不对，直接放弃统计，不申请权限、
/// 不报错。
const _publicDownloadDir = '/storage/emulated/0/Download/NagoMusic';

List<StorageSection> appStorageSections() => [
  StorageSection(
    key: 'audio',
    icon: AppIcons.musicNote,
    title: '音频缓存',
    description: '播放在线歌曲时缓存的音频文件，清理后需要重新下载。',
    confirmTitle: '清除音频缓存',
    confirmMessage: '确定要清除音频缓存吗？这将需要重新下载音频文件。',
    resolvePaths: () async {
      final support = await getApplicationSupportDirectory();
      return [p.join(support.path, 'audio_cache')];
    },
    clear: () => AudioCacheService.instance.clearCache(),
  ),
  StorageSection(
    key: 'artwork',
    icon: AppIcons.image,
    title: '封面缓存',
    description: '本地生成的封面缩略图，清理后会在需要时重新生成。',
    confirmTitle: '清除封面缓存',
    confirmMessage: '确定要清除封面缓存吗？这将需要重新生成封面缩略图。',
    resolvePaths: () async {
      final docs = await getApplicationDocumentsDirectory();
      return [p.join(docs.path, 'artwork_cache')];
    },
    // ArtworkCacheHelper 只有按 key 删除的接口、没有批量清空，跟旧页面一样
    // 用「删目录再重建」代替。
    clear: () => _recreateDir(() async {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'artwork_cache'));
    }),
  ),
  StorageSection(
    key: 'lyrics',
    icon: AppIcons.fileText,
    title: '歌词缓存',
    description: '本地歌词文件的缓存副本，清理后会在需要时重新读取。',
    confirmTitle: '清除歌词缓存',
    confirmMessage: '确定要清除歌词缓存吗？本地歌词会在需要时重新读取。',
    resolvePaths: () async {
      final support = await getApplicationSupportDirectory();
      return [p.join(support.path, 'lyrics')];
    },
    clear: () => _recreateDir(() async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'lyrics'));
    }),
  ),
  StorageSection(
    key: 'tag_probe',
    icon: AppIcons.checkCircle,
    title: '元数据缓存',
    description: '扫描音频文件时缓存的标签/时长等元数据，清理后会在需要时重新探测。',
    confirmTitle: '清除元数据缓存',
    confirmMessage: '确定要清除元数据缓存吗？下次扫描时会重新探测这些文件的信息。',
    resolvePaths: () async {
      final support = await getApplicationSupportDirectory();
      return [p.join(support.path, 'tag_probe_cache')];
    },
    clear: () => _recreateDir(() async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'tag_probe_cache'));
    }),
  ),
  StorageSection(
    key: 'bili_cover',
    icon: AppIcons.video,
    title: 'B 站封面',
    description: '登录 B 站账号后缓存的视频封面，清理后会在需要时重新下载。',
    confirmTitle: '清除 B 站封面缓存',
    confirmMessage: '确定要清除 B 站封面缓存吗？这将需要重新下载封面图片。',
    resolvePaths: () async {
      final support = await getApplicationSupportDirectory();
      return [p.join(support.path, BiliMusicService.coverDirName)];
    },
    clear: () => _recreateDir(() async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, BiliMusicService.coverDirName));
    }),
  ),
  StorageSection(
    key: 'database',
    icon: AppIcons.hardDrive,
    title: '曲库数据',
    description: '你的歌单、收藏和播放统计都存在本机数据库里。想清理请用「数据备份」流程。',
    confirmTitle: '',
    confirmMessage: '',
    clearable: false,
    resolvePaths: () async {
      final docs = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docs.path, DbConstants.dbName);
      // -wal/-shm 是 sqlite 的日志与共享内存文件，不算进来的话
      // 写入高峰期能差出好几 MB
      return [dbPath, '$dbPath-wal', '$dbPath-shm'];
    },
    clear: () async {},
  ),
  StorageSection(
    key: 'downloads',
    icon: AppIcons.download,
    title: '已下载歌曲',
    description: '通过「下载」保存到本机的歌曲文件，属于你的数据，不在缓存清理范围内。',
    confirmTitle: '',
    confirmMessage: '',
    clearable: false,
    resolvePaths: () async {
      final useCustom = SongDownloadSettings.useCustomDirectory.value;
      final customPath = SongDownloadSettings.customDirectoryPath.value?.trim();
      if (useCustom && customPath != null && customPath.isNotEmpty) {
        return [customPath];
      }
      // 公共 Download 目录读不到（无权限/路径不对）就当没有，不申请权限、不报错
      try {
        if (Directory(_publicDownloadDir).existsSync()) {
          return [_publicDownloadDir];
        }
      } catch (_) {}
      return const [];
    },
    clear: () async {},
  ),
];

/// 删除目录再重建为空目录，用于没有「批量清空」接口、只能按 key 增删的缓存。
Future<void> _recreateDir(Future<Directory> Function() resolve) async {
  final dir = await resolve();
  if (await dir.exists()) {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
  try {
    await dir.create(recursive: true);
  } catch (_) {}
}
