import 'models.dart';

/// 从 playurl 返回的一堆音频流里挑一路来播。
///
/// 排序按「音质档位优先、同档位比码率」，而不是直接信接口给的顺序 ——
/// `dash.audio` 的顺序在不同视频上并不一致。
class BiliAudioSelector {
  const BiliAudioSelector._();

  /// 档位权重。Hi-Res / 杜比只有大会员能取到，取不到时接口压根不会返回。
  static int _rank(int id) => switch (id) {
    30251 => 5, // Hi-Res 无损
    30250 => 4, // 杜比全景声
    30280 => 3, // 192K
    30232 => 2, // 132K
    30216 => 1, // 64K
    _ => 0,
  };

  /// 返回音质最好的一路；[streams] 为空时返回 null。
  static BiliAudioStream? best(List<BiliAudioStream> streams) {
    if (streams.isEmpty) return null;
    final sorted = [...streams]
      ..sort((a, b) {
        final byRank = _rank(b.id).compareTo(_rank(a.id));
        if (byRank != 0) return byRank;
        return b.bandwidth.compareTo(a.bandwidth);
      });
    return sorted.first;
  }

  /// 挑不超过 [limit] 档的音质列表，用于「音质选择」这类 UI。
  static List<BiliAudioStream> ranked(
    List<BiliAudioStream> streams, {
    int limit = 4,
  }) {
    final sorted = [...streams]
      ..sort((a, b) {
        final byRank = _rank(b.id).compareTo(_rank(a.id));
        if (byRank != 0) return byRank;
        return b.bandwidth.compareTo(a.bandwidth);
      });
    return sorted.take(limit).toList();
  }
}
