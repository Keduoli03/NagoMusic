import 'package:flutter/material.dart';

import '../../app/services/haptic_service.dart';
import '../../app/theme/app_colors.dart';

/// 全 App 统一的开关。移植自 flutter_template_local，唯一改动是**打开态默认取
/// `colorScheme.primary`（用户自选主题色 / 动态取色）而不是写死的 `kBrand`**。
///
/// **不要再用 Material `Switch` / `Switch.adaptive` / `SwitchListTile`**
/// （设置行请用 `AppSettingSwitchTile`，它内部就是这个组件）：
/// - Material 3 的 Switch 是 52×32 的大块头，还自带选中态勾图标和一圈水波纹，
///   在设置项密集的列表里显得又大又吵；
/// - 各页面 activeColor / trackOutline 各写各的，深色下轨道底色还会被 Material
///   主题接管，和卡片底色打架。
///
/// 这里是纯手绘：44×26 的轨道 + 22 的圆头，比原生小一圈；拨动时轨道颜色渐变 +
/// 圆头位移 + 轻微「拉伸-回弹」，按住不放圆头也会拉长。
///
/// `onChanged` 传 null 即禁用态（整体降透明度，不响应手势）。
class AppSwitch extends StatefulWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.scale = 1.0,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 打开态轨道色，默认当前主题的 `colorScheme.primary`。
  final Color? activeColor;

  /// 整体缩放（0.85 之类），用于个别紧凑场景。默认 1。
  final double scale;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch>
    with SingleTickerProviderStateMixin {
  // 基准尺寸：比 Material 的 52×32 小一圈，和 15px 的设置项文字更配。
  static const double _w = 44;
  static const double _h = 26;
  static const double _pad = 2;
  static const double _thumb = _h - _pad * 2; // 22

  /// 按住时圆头横向拉长的量，松手回弹。给「捏住了」的实感。
  static const double _stretch = 4;

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.value ? 1 : 0,
  );

  /// 位移用 easeOutCubic：起步快、末尾稳，不用 elastic 那种回弹过冲——
  /// 开关一天要按几十次，过冲看两次就腻。
  late final Animation<double> _t = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeOutCubic,
  );

  bool _pressed = false;

  /// 拖拽中的即时进度（0~1）。非拖拽时为 null，由 [_ctrl] 驱动。
  double? _dragT;

  bool get _enabled => widget.onChanged != null;

  @override
  void didUpdateWidget(covariant AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（异步保存失败回滚、其他入口改同一份状态）改值时跟随动画。
    if (widget.value != oldWidget.value && _dragT == null) {
      widget.value ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit(bool v) {
    if (v == widget.value) {
      // 值没变也要把动画拉回正确的一端（拖到一半又松手的情况）。
      v ? _ctrl.forward() : _ctrl.reverse();
      return;
    }
    Haptics.tap();
    v ? _ctrl.forward() : _ctrl.reverse();
    widget.onChanged!(v);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_enabled) return;
    final span = _w - _thumb - _pad * 2;
    final cur = _dragT ?? _ctrl.value;
    setState(() => _dragT = (cur + d.primaryDelta! / span).clamp(0.0, 1.0));
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_enabled) return;
    final t = _dragT ?? _ctrl.value;
    // 甩速优先于位置：快速一划即使没过半也认为是要切过去。
    final v = d.velocity.pixelsPerSecond.dx.abs() > 300
        ? d.velocity.pixelsPerSecond.dx > 0
        : t > 0.5;
    setState(() {
      _dragT = null;
      _pressed = false;
    });
    _ctrl.value = t;
    _commit(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final on = widget.activeColor ?? Theme.of(context).colorScheme.primary;
    // 浅色主题下 c.line 太淡（几乎看不出是个轨道），用稍深一档的灰。
    final off = c.surface.computeLuminance() > 0.5
        ? const Color(0xFFDFE2E5)
        : c.line;

    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      child: Opacity(
        opacity: _enabled ? 1 : 0.45,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? () => _commit(!widget.value) : null,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onHorizontalDragStart: _enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: SizedBox(
            width: _w * widget.scale,
            height: _h * widget.scale,
            child: FittedBox(
              fit: BoxFit.contain,
              child: AnimatedBuilder(
                animation: _t,
                builder: (context, _) {
                  final t = _dragT ?? _t.value;
                  final thumbW = _thumb + (_pressed ? _stretch : 0);
                  final span = _w - thumbW - _pad * 2;
                  return SizedBox(
                    width: _w,
                    height: _h,
                    child: Stack(
                      children: [
                        // 轨道：灰 → 品牌色渐变，同一条 t 上插值，不做两层叠加，
                        // 免得中间态出现半透明发灰的脏色。
                        Container(
                          decoration: BoxDecoration(
                            color: Color.lerp(off, on, t),
                            borderRadius: BorderRadius.circular(_h / 2),
                          ),
                        ),
                        Positioned(
                          top: _pad,
                          left: _pad + span * t,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                            width: thumbW,
                            height: _thumb,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(_thumb / 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
