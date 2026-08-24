import 'package:flutter/widgets.dart';

/// 全 App 排版 token。**九档，比参考模板（flutter_template）多三档，别再"精简"回六档。**
///
/// 参考模板的六档规模是从一个没有 token 层的项目审计出来的理想刻度，但本仓库在引入
/// 这层之前就已经跑出了实打实的字号分布：12(×30)、13(×19)、15(×18)、14(×15)、
/// 16(×13)、17(×8)、11(×6)、18(×5)、10(×4) —— 9 种字号、几百处调用点。这次重构的
/// 前提是**零视觉变化**，不允许借着"建 token 层"顺手把 16/17/18 揉成一档、把 11/13
/// 揉进 12/14，那样任何一处套用新 token 的页面都会跳像素。所以这里把六档模板扩成
/// 九档超集，先把现状如实建模，等以后要收拢字号再单独立项、逐页核对视觉。
///
/// ## 用法
/// ```dart
/// Text(post.title, style: AppTypography.title.on(c.text))
/// Text(timeLabel,  style: AppTypography.caption.on(c.muted))
/// ```
///
/// ## 硬性规则
/// - 每个 token 自带 `height`，**不要在调用处覆盖行高**。
/// - 变色用 [TextStyleTone.on]，不要整个重写 TextStyle。
/// - 新增字号需求先看这九档能不能覆盖，不要在页面里再手写 `fontSize:`。
abstract final class AppTypography {
  /// 10 / w600 —— 角标、水印、图上小字。
  static const TextStyle badge = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 11 / w400 —— 比 caption 更小的辅助说明、次要 meta。
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// 12 / w400 —— meta 行（时间 / 计数）、辅助说明。全站出现频率最高的字号。
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// 13 / w400 —— 介于 caption 与 body 之间的次级正文 / meta。
  static const TextStyle meta = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// 14 / w400 —— 正文、列表主文案。
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  /// 15 / w600 —— 卡片标题、列表行标题。
  static const TextStyle bodyLg = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// 16 / w600 —— 区块小标题、强调文案。
  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// 17 / w600 —— 页面标题（含顶部栏）、区块标题。
  static const TextStyle section = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// 20 / w600 —— 顶部栏大标题。
  static const TextStyle topBar = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );

  /// 24 / w700 —— 数字大字、空态主标题、金额。
  static const TextStyle display = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
}

/// 给 token 上色 / 微调的扩展。只提供这几个口子，避免又退化成到处手写 TextStyle。
extension TextStyleTone on TextStyle {
  /// 上色：`AppTypography.caption.on(c.muted)`
  TextStyle on(Color color) => copyWith(color: color);

  /// 加粗一档（w400→w600，w600→w700）。用于同一档字号内区分主次，
  /// 避免为了"重一点"而跳到更大的字号。
  TextStyle get strong => copyWith(
    fontWeight: fontWeight == FontWeight.w400
        ? FontWeight.w600
        : FontWeight.w700,
  );

  /// 删除线（原价、已完成的待办）。
  TextStyle get strike => copyWith(decoration: TextDecoration.lineThrough);
}
