import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';
import '../../app/state/song_state.dart';
import '../../app/theme/app_radii.dart';
import '../../app/utils/audio_quality.dart';

/// 音质标记（HI-RES / LOSSLESS / HQ）。
///
/// 位置在**元信息行的最前面**，排在歌手之前：
/// 「⌈LOSSLESS⌋ 周杰伦 · 我很忙 · 4:07」。
///
/// 三条刻意的设定：
/// - **不在标题行**。标题行是列表里视觉权重最高的位置，塞个徽章进去会跟歌名抢
///   注意力，而且 “LOSSLESS” 常常比中文歌名还宽。
/// - **比正文小**。字号 9，比 12 的元信息小一档，逐行出现时才不会压过内容。
/// - **只有线框没有填充**。线框 + 填充 + 彩字三层装饰堆在十几 px 的元素上会显廉价，
///   线框加颜色已经足够区分三档。
///
/// 右侧留 6 的外边距，和后面的歌手名隔开；关掉设置或歌曲没有值得标注的规格时整体
/// 不渲染，也就不会留下多余的空隙。
class QualityTagBadge extends StatelessWidget {
  final SongEntity song;

  const QualityTagBadge({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SongListDisplaySettings.showQualityTag,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        final tag = audioQualityTagFor(song);
        if (tag == null) return const SizedBox.shrink();
        final color = tag.color(context);
        // 光学对齐：徽章的框比中文字形高一圈，纯居中的结果是框顶比字顶高出一截、
        // 框底却只低一点点，看着整体偏上。往下挪 1px 把这点不对称补回来。
        // 用 Transform 而不是 margin/padding，是为了只动视觉不动布局。
        return Transform.translate(
          offset: const Offset(0, 1),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            // 右内边距比左边少 0.4 —— letterSpacing 会在最后一个字符后面也留一份
            // 间距，不补回来的话文字在框里看着偏左。
            padding: const EdgeInsets.fromLTRB(4, 1.5, 3.6, 1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.badge),
              border: Border.all(
                color: color.withValues(alpha: 0.55),
                width: 0.6,
              ),
            ),
            child: Text(
              tag.label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                // 不设 height —— 「无损」这类中文字形比 1em 高，压成 height: 1.0
                // 会让它们画到框线外面去。改用 even 让字形在行框里居中。
                leadingDistribution: TextLeadingDistribution.even,
              ),
            ),
          ),
        );
      },
    );
  }
}
