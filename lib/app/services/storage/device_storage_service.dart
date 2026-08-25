import 'package:flutter/services.dart';

import '../log/log.dart';

/// 设备存储容量（总量 / 可用），给「存储与缓存」页顶部那条
/// 「本 App 已用 / 其他 App 已用 / 剩余可用」构成条用。
///
/// 【为什么自己写 channel 而不是加包】只要两个数字，Android 是 `StorageStatsManager`
/// / `StatFs` 两行，不需要任何权限。pub 上的同类包封装的正是这两行，却要多背一份
/// 供应链和版本兼容。
///
/// 【拿不到怎么办】桌面端、模拟器、厂商 ROM 抽风都可能失败（iOS 本项目未实现桥，
/// 也会走到这条路径）。失败返回 null，页面退回到「按类别构成」的旧样式，
/// 不弹错也不留空条。
class DeviceStorage {
  const DeviceStorage({required this.total, required this.free});

  /// 设备存储总容量（字节）。Android 8+ 取的是厂商标称容量（跟系统设置一致，
  /// 比 StatFs 的可用分区大小更符合用户认知）。
  final int total;

  /// 可用空间（字节）。
  final int free;

  /// 已被占用的部分（含本 App 自己）。
  int get used => (total - free).clamp(0, total);

  /// [bytes] 占设备总容量的百分比，直接拿去填文案。
  ///
  /// 不到 1% 时保留一位小数：App 才装上没多少数据时显示成 "0%"，看着像统计没跑起来。
  String percentOf(int bytes) {
    if (total <= 0) return '0';
    final p = bytes * 100 / total;
    return p < 1 ? p.toStringAsFixed(1) : p.toStringAsFixed(0);
  }
}

class DeviceStorageService {
  DeviceStorageService._();

  static const String _logTag = 'DeviceStorageService';

  static const _channel = MethodChannel('app/device_storage');

  /// 查询设备容量；查不到返回 null（调用方负责降级，不要抛给用户）。
  static Future<DeviceStorage?> capacity() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('capacity');
      final total = (r?['total'] as num?)?.toInt() ?? 0;
      final free = (r?['free'] as num?)?.toInt() ?? 0;
      if (total <= 0) return null;
      return DeviceStorage(total: total, free: free.clamp(0, total));
    } catch (e, s) {
      AppLog.instance.w(_logTag, '查询设备存储容量失败', e, s);
      return null;
    }
  }
}
