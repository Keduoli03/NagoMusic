import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show IconData;

/// 存储空间页的**通用层**：类别模型 + 占用统计 + 目录遍历工具。
///
/// 这个文件本应和 `flutter_template_local` 逐字节一致，项目差异全部收在
/// `storage_sections.dart`（哪些类别、各自算哪些路径、怎么清）。想加一类存储，
/// 去那个文件加一条 [StorageSection]，这里不用动。
///
/// 【为什么要分类而不是一键清空】"清除缓存"式的一键全清，用户既看不到清掉了多少，
/// 也没法只清某一类留另一类；而且很容易漏掉某个缓存目录（NagoMusic 的旧版
/// 「存储与缓存」页就漏了元数据缓存和 B 站封面缓存两个目录），点完"已清除"
/// 空间却没怎么降。

/// 这一类占了哪些路径（目录或文件，不存在的会被忽略）。
///
/// 异步是因为路径通常要先问 `path_provider`；返回具体条目而不是一个根目录，
/// 是为了让"临时目录里除了别人认领的以外的全部"这种类别也能用同一套统计。
typedef StoragePathResolver = Future<List<String>> Function();

typedef StorageCleaner = Future<void> Function();

/// 存储空间页里的一类占用。
@immutable
class StorageSection {
  const StorageSection({
    required this.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.resolvePaths,
    required this.clear,
    this.destructive = false,
    this.clearable = true,
  });

  /// 统计结果的索引键，页面内唯一即可（用不到 i18n，不要拿标题当键）。
  final String key;

  final IconData icon;

  /// 卡片标题，如"图片缓存"。
  final String title;

  /// 卡片底部的灰色说明：**说清楚清理之后会失去什么**，别只写"清理缓存"。
  final String description;

  final String confirmTitle;
  final String confirmMessage;

  final StoragePathResolver resolvePaths;
  final StorageCleaner clear;

  /// 删的是用户数据而不是可再生的缓存时置 true（确认按钮转成警示红）。
  final bool destructive;

  /// 是否在页面上给这一类展示「清理」按钮。
  ///
  /// 默认 true。曲库数据库、已下载歌曲这类**用户数据**（而非可再生缓存）应置为
  /// false：它们仍要参与总占用和构成条的统计（用户有权知道空间去哪了），但一个
  /// 通用的「清理」按钮不该有能力删掉它们——数据库有专门的备份/恢复流程，下载的
  /// 歌曲是通过 MediaStore 落进公共 Download 目录的用户财产，不是缓存。
  final bool clearable;
}

/// 一次统计的结果，按 [StorageSection.key] 索引。
@immutable
class StorageUsage {
  const StorageUsage(this.sizes);

  /// 全 0 的占位（统计失败时用，页面显示 0 B 好过一直转圈）。
  factory StorageUsage.emptyFor(List<StorageSection> sections) =>
      StorageUsage({for (final s in sections) s.key: 0});

  final Map<String, int> sizes;

  int of(String key) => sizes[key] ?? 0;

  int get total => sizes.values.fold(0, (a, b) => a + b);
}

class StorageUsageService {
  StorageUsageService._();

  /// 统计每一类的占用。
  ///
  /// 目录遍历放到后台 isolate（[compute]）：缓存目录动辄上千个文件，
  /// 在 UI 线程 `listSync` 会明显卡住返回动画。
  static Future<StorageUsage> measure(List<StorageSection> sections) async {
    try {
      final groups = <List<String>>[];
      for (final s in sections) {
        groups.add(await s.resolvePaths());
      }
      final sizes = await compute(_measureGroups, groups);
      return StorageUsage({
        for (var i = 0; i < sections.length; i++) sections[i].key: sizes[i],
      });
    } catch (e) {
      // 目录拿不到（平台不支持/权限异常）不该让整页停在转圈上
      debugPrint('[storage] measure failed: $e');
      return StorageUsage.emptyFor(sections);
    }
  }
}

/// 写 [StorageSection] 的 `resolvePaths` / `clear` 时的公共工具。
class StorageScan {
  StorageScan._();

  /// 临时文件的"正在使用"判定窗口，见 [touchedRecently]。
  static const inUseWindow = Duration(minutes: 5);

  /// 列出 [dir] 下的直接子项路径，跳过 [exclude] 里的名字。
  ///
  /// 用于"临时目录里除了别的类别已经认领的以外，剩下的都算我"这种类别。
  static List<String> childrenOf(
    Directory dir, {
    Set<String> exclude = const {},
  }) {
    try {
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(followLinks: false)
          .where((e) => !exclude.contains(nameOf(e.path)))
          .map((e) => e.path)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 路径里的最后一段（同时兼容 `/` 和 `\`）。
  static String nameOf(String path) => path.split(RegExp(r'[/\\]')).last;

  /// 该条目（或目录下任一文件）是否在 [inUseWindow] 内被写过。
  ///
  /// **清临时文件前必须问一句**：用户可能正在选图/上传/下载更新，那些插件的中间
  /// 文件也落在临时目录，删掉会让进行中的操作直接失败。
  /// 目录自身的 mtime 不随子文件更新而变，所以目录必须往里看一层。
  static bool touchedRecently(FileSystemEntity e) {
    final now = DateTime.now();
    bool fresh(FileStat s) => now.difference(s.modified) < inUseWindow;
    try {
      if (e is File) return fresh(e.statSync());
      if (e is Directory) {
        if (fresh(e.statSync())) return true;
        for (final child in e.listSync(recursive: true, followLinks: false)) {
          if (child is File && fresh(child.statSync())) return true;
        }
      }
    } catch (_) {
      // stat 不出来的当作"在用"，宁可少清一点也别删错
      return true;
    }
    return false;
  }

  /// 删除一个条目，失败静默跳过。
  ///
  /// 单个文件删不掉（被占用/权限）不该让整次清理报错——用户要的是"腾出空间"，
  /// 少删一个文件不影响这个目标。
  static void deleteQuietly(FileSystemEntity e) {
    try {
      if (e is Directory) {
        e.deleteSync(recursive: true);
      } else {
        e.deleteSync();
      }
    } catch (_) {}
  }

  /// 删除路径列表里的条目（[keep] 里的原样保留，路径分隔符已归一化比较）。
  static void deletePaths(
    Iterable<String> paths, {
    Set<String> keep = const {},
  }) {
    final normalizedKeep = keep.map((p) => p.replaceAll('\\', '/')).toSet();
    for (final p in paths) {
      if (normalizedKeep.contains(p.replaceAll('\\', '/'))) continue;
      final dir = Directory(p);
      if (dir.existsSync()) {
        deleteQuietly(dir);
        continue;
      }
      final f = File(p);
      if (f.existsSync()) deleteQuietly(f);
    }
  }
}

/// 后台 isolate 入口：每组路径求和，返回与入参等长的字节数列表。
List<int> _measureGroups(List<List<String>> groups) => [
  for (final paths in groups)
    paths.fold<int>(0, (acc, p) => acc + _sizeOfPath(p)),
];

int _sizeOfPath(String path) {
  final dir = Directory(path);
  if (dir.existsSync()) return _sizeOfEntity(dir);
  final f = File(path);
  return f.existsSync() ? _sizeOfEntity(f) : 0;
}

int _sizeOfEntity(FileSystemEntity e) {
  try {
    if (e is File) return e.lengthSync();
    if (e is Directory) {
      var t = 0;
      for (final child in e.listSync(recursive: true, followLinks: false)) {
        if (child is File) {
          try {
            t += child.lengthSync();
          } catch (_) {
            // 遍历途中被别人删掉的文件，跳过
          }
        }
      }
      return t;
    }
  } catch (_) {}
  return 0;
}
