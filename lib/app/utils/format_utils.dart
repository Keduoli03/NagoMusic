/// 全应用共用的展示格式化函数。
///
/// 这些函数此前在多个页面/服务中各自实现，行为略有差异；
/// 这里通过参数保留各调用点原本的输出格式。
library;

/// 两位补零，用于时间/日期拼接。
String twoDigits(int value) => value.toString().padLeft(2, '0');

/// `yyyy-MM-dd` 形式的日期键。
String formatDayKey(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${twoDigits(time.month)}-${twoDigits(time.day)}';

/// 毫秒时长格式化为 `m:ss`，无效值返回 [placeholder]。
///
/// [padMinutes] 为 true 时分钟补零（`mm:ss`）；[roundSeconds] 为 true 时秒数
/// 四舍五入，否则向下取整。
String formatDurationMs(
  int? durationMs, {
  String placeholder = '--:--',
  bool padMinutes = false,
  bool roundSeconds = false,
}) {
  if (durationMs == null || durationMs <= 0) return placeholder;
  final totalSeconds = roundSeconds
      ? (durationMs / 1000).round()
      : (durationMs / 1000).floor();
  final minutes = totalSeconds ~/ 60;
  final minutesText = padMinutes ? twoDigits(minutes) : '$minutes';
  return '$minutesText:${twoDigits(totalSeconds % 60)}';
}

/// [Duration] 格式化为 `mm:ss`（分钟也补零）。
///
/// [zeroText] 为非正时长的返回值，null 表示照常返回 `00:00`。
String formatClock(Duration? duration, {String? zeroText}) {
  final total = duration?.inSeconds ?? 0;
  if (total <= 0 && zeroText != null) return zeroText;
  return '${twoDigits(total ~/ 60)}:${twoDigits(total % 60)}';
}

/// 分钟数格式化为 `h:mm`。
String formatMinutesAsClock(num minutes) {
  final totalMinutes = minutes.round();
  return '${totalMinutes ~/ 60}:${twoDigits(totalMinutes % 60)}';
}

/// 字节数格式化为带单位的字符串。
///
/// [fractionDigits] 为 null 时使用自适应精度（小于 10 且非 B 单位保留两位，
/// 否则一位）；传入具体值则固定精度。
String formatFileSize(
  int? bytes, {
  int? fractionDigits,
  String placeholder = '-',
}) {
  final value = bytes ?? 0;
  if (value <= 0) return placeholder;
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value.toDouble();
  var index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index++;
  }
  final digits = fractionDigits ?? (size < 10 && index > 0 ? 2 : 1);
  return '${size.toStringAsFixed(digits)} ${units[index]}';
}

/// 比特率格式化为 kbps。
String formatBitrate(int? bitrate, {String placeholder = '-'}) {
  final value = bitrate ?? 0;
  if (value <= 0) return placeholder;
  final kbps = value / 1000;
  return '${kbps.toStringAsFixed(kbps >= 100 ? 0 : 1)} kbps';
}

/// 采样率格式化为 Hz / kHz。
String formatSampleRate(int? sampleRate, {String placeholder = '-'}) {
  final value = sampleRate ?? 0;
  if (value <= 0) return placeholder;
  if (value < 1000) return '$value Hz';
  final khz = value / 1000;
  return '${khz.toStringAsFixed(khz >= 100 ? 0 : 1)} kHz';
}
