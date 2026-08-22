/// 各音乐源扫描过程共用的进度与结果类型。
library;

/// 扫描进行中的进度快照。
class ScanProgress {
  final int processed;
  final int added;
  final int total;

  const ScanProgress({
    required this.processed,
    required this.added,
    required this.total,
  });
}

/// 扫描结束后的统计结果。
class ScanResult {
  final int processed;
  final int added;

  const ScanResult({required this.processed, required this.added});
}
