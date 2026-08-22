import 'pref_entry.dart';

enum PlayerStylePreset { classic, poster }

extension PlayerStylePresetLabel on PlayerStylePreset {
  String get label {
    switch (this) {
      case PlayerStylePreset.classic:
        return '默认';
      case PlayerStylePreset.poster:
        return '海报歌词';
    }
  }

  String get description {
    switch (this) {
      case PlayerStylePreset.classic:
        return '沿用当前播放器布局';
      case PlayerStylePreset.poster:
        return '大封面海报与底部控制';
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
