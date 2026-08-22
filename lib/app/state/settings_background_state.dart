import 'package:flutter/foundation.dart';

import 'pref_entry.dart';

class AppBackgroundSettings {
  static final backgroundImagePath = PrefEntry.nullableText(
    'setting_background_image_path',
  );
  // 重构前这里存在一处不一致：ValueNotifier 初值是 0.35，而 _doLoad 的缺省
  // 回落是 0.5。由于 ensureLoaded 会在启动早期执行，用户实际看到的一直是 0.5，
  // 因此这里统一取 0.5（0.35 只在加载完成前的极短窗口内出现过）。
  static final backgroundMaskOpacity = PrefEntry.number(
    'setting_background_mask_opacity',
    defaultValue: 0.5,
    sanitize: (v) => v.clamp(0.0, 1.0),
  );
  // 0 = original sharp image, 32 = heavily blurred. Users kept complaining
  // that "透明度=0" still looked hazy — that was this constant-16 blur.
  static final backgroundBlurSigma = PrefEntry.number(
    'setting_background_blur_sigma',
    defaultValue: 16,
    sanitize: (v) => v.clamp(0.0, 32.0),
  );
  static final pageGlowEnabled = PrefEntry.boolean('setting_page_glow_enabled');
  static final panelOpacity = PrefEntry.number(
    'setting_panel_opacity',
    defaultValue: 0.72,
    sanitize: (v) => v.clamp(0.0, 1.0),
  );

  // Legacy notifiers — the "毛玻璃质感" feature was removed. They are kept so
  // widgets that still read them compile without a rewrite, but their values
  // are pinned to "off" and no UI can flip them back on.
  static final ValueNotifier<bool> glassEffectEnabled = ValueNotifier(false);
  static final ValueNotifier<double> panelBlurStrength = ValueNotifier(0);

  static final _group = PrefGroup([
    backgroundImagePath,
    backgroundMaskOpacity,
    backgroundBlurSigma,
    pageGlowEnabled,
    panelOpacity,
  ]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setBackgroundImagePath(String? path) =>
      backgroundImagePath.set(path);

  static Future<void> setBackgroundMaskOpacity(double value) =>
      backgroundMaskOpacity.set(value);

  static Future<void> setBackgroundBlurSigma(double value) =>
      backgroundBlurSigma.set(value);

  static Future<void> setPageGlowEnabled(bool enabled) =>
      pageGlowEnabled.set(enabled);

  static Future<void> setPanelOpacity(double value) => panelOpacity.set(value);
}
