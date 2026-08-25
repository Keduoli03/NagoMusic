import 'pref_entry.dart';

enum PlayerStylePreset { classic, poster, immersive }

extension PlayerStylePresetLabel on PlayerStylePreset {
  String get label {
    switch (this) {
      case PlayerStylePreset.classic:
        return '默认';
      case PlayerStylePreset.poster:
        return '海报歌词';
      case PlayerStylePreset.immersive:
        return '沉浸';
    }
  }

  String get description {
    switch (this) {
      case PlayerStylePreset.classic:
        return '沿用当前播放器布局';
      case PlayerStylePreset.poster:
        return '大封面海报与底部控制';
      case PlayerStylePreset.immersive:
        return '点阵封面、居中双语歌词，无进度条';
    }
  }
}

/// 一个样式在设置页里暴露哪些自定义项。
///
/// **别把这个偷懒成一个 bool。** 现在只有"底部操作栏"这一项分叉——只有默认样式
/// 的控制区走的是可插拔按钮那一套，海报和沉浸都是固定的一排播放/暂停/上一首/
/// 下一首，没有位置能塞这些按钮，开放这项设置只会让用户以为"调了没生效"。
/// 以后新增样式专属的设置项（比如沉浸样式的点阵密度），也在这里加一个字段，
/// 不要在设置页里散落 `if (preset == xxx)`。
class PlayerStyleCapabilities {
  const PlayerStyleCapabilities({this.customBottomActions = false});

  /// 是否支持自定义底部操作栏（增删/排序播放模式、定时、播放队列等按钮）。
  final bool customBottomActions;
}

extension PlayerStylePresetCapabilities on PlayerStylePreset {
  PlayerStyleCapabilities get capabilities {
    switch (this) {
      case PlayerStylePreset.classic:
        return const PlayerStyleCapabilities(customBottomActions: true);
      case PlayerStylePreset.poster:
      case PlayerStylePreset.immersive:
        return const PlayerStyleCapabilities();
    }
  }
}

class PlayerStyleSettings {
  // 枚举名与原本存储的 'classic' / 'poster' 一致，改用 PrefEntry 不影响存档值。
  static final stylePreset = PrefEntry.enumeration<PlayerStylePreset>(
    'player_style_preset',
    values: PlayerStylePreset.values,
    defaultValue: PlayerStylePreset.classic,
  );

  static final _group = PrefGroup([stylePreset]);

  static Future<void> ensureLoaded() => _group.ensureLoaded();

  static Future<void> setStylePreset(PlayerStylePreset preset) =>
      stylePreset.set(preset);
}
