import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log/log.dart';

/// 触感反馈强度档位（设备级偏好）。
enum HapticLevel {
  /// 关闭：所有触感调用直接吞掉。
  off,

  /// 轻柔：语义档位整体降一级（重击→中震、中震→轻触）。
  light,

  /// 标准：按语义原样触发（默认）。
  standard,
}

/// 全 App 统一的触感反馈入口（单例）。移植自 flutter_template_local。
///
/// 之所以不直接在各处裸调 [HapticFeedback]：
/// - 需要一个设备级总开关 + 强度档位（部分用户/部分 ROM 上马达很吵）；
/// - 需要按「语义」而不是「强度」来调用，各页面才不会各写各的力度；
/// - 需要节流：列表快速滑动、连续拖拽时如果每帧都震，马达会糊成一片嗡嗡声。
///
/// 用法（不要再裸调 HapticFeedback）：
/// ```dart
/// Haptics.selection();  // Tab 切换、选中一项、滑到某个刻度
/// Haptics.tap();        // 普通轻点：收藏、按钮、开关拨动
/// Haptics.impact();     // 中等确认：弹出面板、长按唤起菜单
/// Haptics.heavy();      // 重操作：删除、破坏性确认
/// Haptics.success();    // 成功（保存/导出成功）——双击轻触
/// Haptics.error();      // 失败/被拒——一次重震
/// ```
class Haptics {
  Haptics._();

  static const String _logTag = 'Haptics';

  static const _kLevel = 'haptic_level'; // off / light / standard

  static HapticLevel _level = HapticLevel.standard;
  static bool _inited = false;

  /// 供设置页监听的当前档位。业务代码判断强度请用 [level]（静态读取，
  /// 不用每次都建 ValueListenableBuilder）。
  static final ValueNotifier<HapticLevel> levelListenable = ValueNotifier(
    HapticLevel.standard,
  );

  /// 上一次真正触发震动的时刻，用于节流。用毫秒时间戳而不是 DateTime 比较，
  /// 省掉高频路径上的对象分配。
  static int _lastFireMs = 0;

  /// 连续触发的最小间隔。滑动选择类交互一秒最多十来次已足够密，再密只会糊。
  static const _minIntervalMs = 40;

  static HapticLevel get level => _level;

  static bool get enabled => _level != HapticLevel.off;

  /// 读取本地偏好；应在 main() 启动早期调用一次。失败不影响启动。
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    try {
      final p = await SharedPreferences.getInstance();
      _level = _parse(p.getString(_kLevel));
      levelListenable.value = _level;
    } catch (e, s) {
      // 存储不可用时保持默认标准档。
      AppLog.instance.w(_logTag, '读取触感档位偏好失败，使用默认标准档', e, s);
    }
  }

  /// 更新档位并持久化。切到非关闭档时给一次即时反馈，方便用户确认手感。
  static Future<void> setLevel(HapticLevel v) async {
    _level = v;
    levelListenable.value = v;
    if (v != HapticLevel.off) {
      _lastFireMs = 0; // 清掉节流，保证这一次预览一定震
      impact();
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLevel, v.name);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '保存触感档位偏好失败: level=${v.name}', e, s);
    }
  }

  static HapticLevel _parse(String? s) => switch (s) {
    'off' => HapticLevel.off,
    'light' => HapticLevel.light,
    _ => HapticLevel.standard,
  };

  // ---- 语义档位 ----

  /// 选择变更：Tab 切换、单选选中、滚轮滑过一格。
  static void selection() => _fire(_Kind.selection);

  /// 普通轻点：收藏/关注、图标按钮、开关拨动。
  static void tap() => _fire(_Kind.light);

  /// 中等确认：长按唤起菜单、弹出底部面板。
  static void impact() => _fire(_Kind.medium);

  /// 重操作：删除、破坏性确认。
  static void heavy() => _fire(_Kind.heavy);

  /// 成功：保存/导出/复制成功。用「轻—轻」两下区别于单次轻点。
  static void success() {
    if (!enabled) return;
    _fire(_Kind.light, force: true);
    Future.delayed(const Duration(milliseconds: 90), () {
      _fire(_Kind.light, force: true);
    });
  }

  /// 失败：操作失败、校验不通过。
  static void error() => _fire(_Kind.heavy, force: true);

  // ---- 内部 ----

  static void _fire(_Kind kind, {bool force = false}) {
    if (!enabled) return;
    if (!force) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastFireMs < _minIntervalMs) return;
      _lastFireMs = now;
    }

    // 轻柔档整体降一级：重→中、中→轻、轻/选择→选择。
    final k = _level == HapticLevel.light ? _soften(kind) : kind;
    try {
      switch (k) {
        case _Kind.selection:
          HapticFeedback.selectionClick();
        case _Kind.light:
          HapticFeedback.lightImpact();
        case _Kind.medium:
          HapticFeedback.mediumImpact();
        case _Kind.heavy:
          HapticFeedback.heavyImpact();
      }
    } catch (_) {
      // 无马达/平台不支持时静默忽略，绝不影响业务主流程。
    }
  }

  static _Kind _soften(_Kind k) => switch (k) {
    _Kind.heavy => _Kind.medium,
    _Kind.medium => _Kind.light,
    _ => _Kind.selection,
  };
}

enum _Kind { selection, light, medium, heavy }
