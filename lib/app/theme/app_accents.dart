import 'package:flutter/material.dart';

/// 强调色预设，取自作者博客（Astro / gyoza）的 `src/config.json` 的 `color.accent`。
///
/// 和原来那套九个扁平色板最大的区别：**每档是亮/暗一对，而不是一个颜色**。
///
/// 而且暗色那半不是亮色调亮，往往是另一个色相——比如第一档亮色是珊瑚红
/// `#F55555`、暗色却是琥珀黄 `#FCCF31`。这是刻意的：同一个饱和红放到深色底上
/// 会发闷、和背景拉不开，换成暖黄反而能保住"暖"的性格又够亮。所以别"顺手统一"
/// 成同色相的深浅两版，那样就把这套配色的意图改没了。
@immutable
class AppAccent {
  const AppAccent(this.light, this.dark);

  final Color light;
  final Color dark;

  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

abstract final class AppAccents {
  /// 顺序和博客 `config.json` 一致，第一档就是博客的默认强调色。
  static const List<AppAccent> presets = <AppAccent>[
    AppAccent(Color(0xFFF55555), Color(0xFFFCCF31)), // 珊瑚红 / 琥珀黄
    AppAccent(Color(0xFF0396FF), Color(0xFFABDCFF)), // 亮蓝 / 冰蓝
    AppAccent(Color(0xFFFB7287), Color(0xFF99D8CF)), // 樱粉 / 薄荷
    AppAccent(Color(0xFFF072B6), Color(0xFFFFF886)), // 玫红 / 柠檬
    AppAccent(Color(0xFF9F44D3), Color(0xFFE2B0FF)), // 紫 / 淡紫
    AppAccent(Color(0xFFFF6666), Color(0xFFA1CCD1)), // 红 / 雾蓝
    AppAccent(Color(0xFFF6416C), Color(0xFF838BC6)), // 玫瑰 / 蓝紫
    AppAccent(Color(0xFF32CCBC), Color(0xFF90F7EC)), // 青绿 / 亮青
    AppAccent(Color(0xFF33A6B8), Color(0xFF79F1A4)), // 湖蓝 / 薄荷绿
    AppAccent(Color(0xFF4F46E5), Color(0xFFA5B4FC)), // 靛蓝 / 淡靛
    AppAccent(Color(0xFF2563EB), Color(0xFF93C5FD)), // 蓝 / 淡蓝
    AppAccent(Color(0xFF0E7490), Color(0xFF67E8F9)), // 深青 / 亮青
    AppAccent(Color(0xFF047857), Color(0xFF6EE7B7)), // 深绿 / 薄荷
    AppAccent(Color(0xFF4D7C0F), Color(0xFFBEF264)), // 橄榄 / 黄绿
    AppAccent(Color(0xFFB45309), Color(0xFFFCD34D)), // 琥珀 / 金
    AppAccent(Color(0xFFC2410C), Color(0xFFFDBA74)), // 砖橙 / 浅橙
    AppAccent(Color(0xFF6D5D4D), Color(0xFFD6C6B8)), // 咖 / 奶咖
  ];

  /// 没选过主题色时用的一档。
  static const AppAccent fallback = AppAccent(
    Color(0xFFF55555),
    Color(0xFFFCCF31),
  );

  /// 按存下来的亮色值找回整对。
  ///
  /// 存储层沿用旧的 `setting_theme_seed_color`（单个颜色），存的就是这里的
  /// [AppAccent.light]。这样老用户的存档不会失效，而只要它命中某一档，暗色模式
  /// 下就能自动用上配对的那个颜色。
  ///
  /// 用户从取色器自选的颜色不会命中任何一档，此时返回 null，调用方亮暗都用它。
  static AppAccent? byLight(Color? light) {
    if (light == null) return null;
    final target = light.toARGB32();
    for (final accent in presets) {
      if (accent.light.toARGB32() == target) return accent;
    }
    return null;
  }

  /// 解析出当前亮度该用的强调色。
  ///
  /// [stored] 为 null（没选过）时用 [fallback]；命中预设时用配对值；
  /// 自选颜色时亮暗都用它本身。
  static Color resolve(Color? stored, Brightness brightness) {
    if (stored == null) return fallback.forBrightness(brightness);
    return byLight(stored)?.forBrightness(brightness) ?? stored;
  }
}
