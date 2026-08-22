import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 液态玻璃效果的可用性探测 + 着色器加载。
///
/// `ui.ImageFilter.shader` **硬性要求 Impeller**，在没跑 Impeller 的设备上会直接
/// 抛 `UnsupportedError`。Flutter 3.44 在安卓上默认开 Impeller，但不支持 Vulkan 的
/// 老设备仍会回落到 Skia —— 所以不能假设它一定可用，必须探测一次并缓存结果。
///
/// 探测方式是真的建一次 `ImageFilter.shader` 再扔掉：没有公开 API 能查询当前渲染
/// 后端，try/catch 是唯一可靠的判断。只做一次，结果全局复用。
class LiquidGlassSupport {
  LiquidGlassSupport._();

  static const _assetKey = 'assets/shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static bool? _supported;
  static Future<void>? _loading;

  /// 是否可用。未探测完成时返回 false —— 调用方据此渲染普通底栏，
  /// 探测完成后 [ensureLoaded] 的 future 完成，再重建就会切到玻璃。
  static bool get isSupported => _supported ?? false;

  /// 探测是否已经跑完（不论结果）。
  static bool get isResolved => _supported != null;

  static ui.FragmentProgram? get program => _program;

  /// 加载着色器并探测 Impeller。可重复调用，只会真正执行一次。
  static Future<void> ensureLoaded() {
    if (_supported != null) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(_assetKey);
      final shader = program.fragmentShader();
      // 先把 uniform 填成合法值，否则 ImageFilter.shader 会因为
      // 「第一个 uniform 必须是 vec2 且至少有一个 sampler」的校验直接抛错，
      // 那样就分不清是不支持 Impeller 还是我们自己传错了。
      _setUniforms(
        shader,
        size: const Size(16, 16),
        radius: 4,
        thickness: 4,
        refraction: 1,
        dispersion: 0,
        highlight: 0,
        edgeShade: 0,
        sheen: 0,
        vibrancy: 1,
        tint: const Color(0x00000000),
        backdrop: null,
      );
      // 真正的探测：这一行在非 Impeller 上抛 UnsupportedError。
      // 注意这里的 shader 和实际渲染时用的是同一套配置（uniform 填满、
      // sampler 不手动绑 —— backdrop 由引擎注入），所以探测结果对真实路径有代表性。
      ui.ImageFilter.shader(shader);
      _program = program;
      _supported = true;
      // 这一行**不加 kDebugMode 判断**，profile 包也要打 —— 玻璃没生效时表现是
      // 「底栏变成一块不透明白板」，和参数没调好长得很像，必须能一眼分辨。
      // 只在启动时打一次。
      debugPrint('[LiquidGlass] 已启用（Impeller 可用）');
    } on UnsupportedError catch (e) {
      // 设备没跑 Impeller。这是预期内的降级，不是 bug。
      _supported = false;
      debugPrint('[LiquidGlass] 当前设备未启用 Impeller，回落到普通底栏: $e');
    } on StateError catch (e) {
      // uniform 数量/顺序和 .frag 对不上，或者少了 sampler —— 这是我们自己的 bug，
      // 不该被当成「设备不支持」悄悄咽掉。
      _supported = false;
      assert(false, '[LiquidGlass] 着色器 uniform 配置有误: $e');
      debugPrint('[LiquidGlass] 着色器 uniform 配置有误: $e');
    } catch (e) {
      _supported = false;
      debugPrint('[LiquidGlass] 加载失败，回落到普通底栏: $e');
    }
  }

  /// uniform 的赋值顺序必须和 .frag 里的声明顺序**完全一致**，
  /// 错一个位置整个效果就会变成噪声。改 .frag 的话记得同步改这里。
  static void _setUniforms(
    ui.FragmentShader shader, {
    required Size size,
    required double radius,
    required double thickness,
    required double refraction,
    required double dispersion,
    required double highlight,
    required double edgeShade,
    required double sheen,
    required double vibrancy,
    required Color tint,
    required ui.Image? backdrop,
  }) {
    var i = 0;
    shader.setFloat(i++, size.width); // uSize.x
    shader.setFloat(i++, size.height); // uSize.y
    shader.setFloat(i++, radius); // uRadius
    shader.setFloat(i++, thickness); // uThickness
    shader.setFloat(i++, refraction); // uRefraction
    shader.setFloat(i++, dispersion); // uDispersion
    shader.setFloat(i++, highlight); // uHighlight
    shader.setFloat(i++, edgeShade); // uEdgeShade
    shader.setFloat(i++, sheen); // uSheen
    shader.setFloat(i++, vibrancy); // uVibrancy
    shader.setFloat(i++, tint.a); // uTintAlpha
    shader.setFloat(i++, tint.r); // uTintColor.r
    shader.setFloat(i++, tint.g); // uTintColor.g
    shader.setFloat(i++, tint.b); // uTintColor.b
    if (backdrop != null) {
      shader.setImageSampler(0, backdrop);
    }
  }

  static void applyUniforms(
    ui.FragmentShader shader, {
    required Size size,
    required double radius,
    required double thickness,
    required double refraction,
    required double dispersion,
    required double highlight,
    required double edgeShade,
    required double sheen,
    required double vibrancy,
    required Color tint,
  }) {
    _setUniforms(
      shader,
      size: size,
      radius: radius,
      thickness: thickness,
      refraction: refraction,
      dispersion: dispersion,
      highlight: highlight,
      edgeShade: edgeShade,
      sheen: sheen,
      vibrancy: vibrancy,
      tint: tint,
      backdrop: null,
    );
  }
}

/// 把子组件渲染成一块液态玻璃。
///
/// 背后是 `BackdropFilter` + `ImageFilter.compose(outer: 折射着色器, inner: 高斯模糊)`：
/// 模糊交给引擎自带的优化实现，着色器只负责边缘折射和高光。在着色器里手写高斯
/// 又慢又难看。
///
/// **不支持时自动降级**：Impeller 不可用、或着色器加载失败，直接渲染 [child]
/// 外加 [fallbackColor] 的实底，不会白屏也不会报错。
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    required this.fallbackColor,
    this.borderRadius = BorderRadius.zero,
    this.blurSigma = 18,
    this.thickness = 22,
    this.refraction = 14,
    this.dispersion = 2.5,
    this.highlight = 0.35,
    this.edgeShade = 0.10,
    this.sheen = 0.06,
    this.vibrancy = 1.5,
    this.tint,
    this.surfaceColor,
    this.surfaceGradient,
    this.surfaceHighlightGradient,
    this.borderColor,
  });

  final Widget child;

  /// 效果不可用时用的实底色。
  final Color fallbackColor;

  final BorderRadius borderRadius;

  /// 背景模糊强度。
  final double blurSigma;

  /// 折射带宽度（逻辑像素），从边缘往内算。
  final double thickness;

  /// 折射强度：边缘处采样点最多往内挪多少像素。
  final double refraction;

  /// 色散强度，0 = 关闭。
  final double dispersion;

  /// 边缘高光强度 0~1。
  final double highlight;

  /// 边缘暗带强度 0~1。**纯色背景下玻璃唯一可见的东西** —— 折射只是把背景挪个
  /// 位置，背景是一片白的话折射出来还是白的。这条暗带负责把轮廓画出来。
  final double edgeShade;

  /// 顶部光带强度 0~1。和 [edgeShade] 一样，是玻璃在**纯色背景上**被看见的来源：
  /// 真实玻璃的弧面会把环境光聚成一条亮带，人眼靠它认出「这里有块透明的东西」。
  final double sheen;

  /// 背景饱和度。1 = 原色，1.5 接近 AndroidLiquidGlass 的 vibrancy。
  final double vibrancy;

  /// 玻璃自身的叠色。null 时用主题 surface 的低透明度版本。
  final Color? tint;

  /// 绘制在模糊、折射结果上方的亚克力蒙版。
  ///
  /// [tint] 属于着色器内部的染色；这一层是实际的材质表面，用较高透明度遮住
  /// 背景细节，只保留模糊后的色块。
  final Color? surfaceColor;

  /// 亚克力表面的光照渐变。设置后优先于 [surfaceColor]。
  final Gradient? surfaceGradient;

  /// 位于材质底色之上、内容之下的反光和内暗带。
  final Gradient? surfaceHighlightGradient;

  /// 玻璃边缘的描边。真实玻璃的轮廓靠这条线定形 —— 只有折射和高光的话，
  /// 玻璃和背景之间没有明确边界，观感会「糊」而不是「透」。
  final Color? borderColor;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;

  Widget _buildSurface(Color? color) {
    Widget surface = widget.child;
    if (widget.surfaceHighlightGradient != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          gradient: widget.surfaceHighlightGradient,
          borderRadius: widget.borderRadius,
        ),
        child: surface,
      );
    }
    if (color != null || widget.surfaceGradient != null) {
      surface = DecoratedBox(
        decoration: BoxDecoration(
          color: widget.surfaceGradient == null ? color : null,
          gradient: widget.surfaceGradient,
          borderRadius: widget.borderRadius,
        ),
        child: surface,
      );
    }
    if (widget.borderColor != null) {
      surface = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: Border.all(color: widget.borderColor!, width: 0.8),
        ),
        child: surface,
      );
    }
    return surface;
  }

  @override
  void initState() {
    super.initState();
    if (LiquidGlassSupport.isResolved) {
      _initShader();
    } else {
      LiquidGlassSupport.ensureLoaded().then((_) {
        if (!mounted) return;
        setState(_initShader);
      });
    }
  }

  void _initShader() {
    if (!LiquidGlassSupport.isSupported) return;
    _shader ??= LiquidGlassSupport.program?.fragmentShader();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) {
      // 没有 Impeller 时仍保留亚克力的模糊蒙版，只降级掉折射和色散。
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
            tileMode: TileMode.clamp,
          ),
          child: _buildSurface(widget.surfaceColor ?? widget.fallbackColor),
        ),
      );
    }

    final tint =
        widget.tint ??
        Theme.of(context).colorScheme.surface.withValues(alpha: 0.16);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
        );
        if (size.isEmpty) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: widget.fallbackColor,
              borderRadius: widget.borderRadius,
            ),
            child: widget.child,
          );
        }

        final dpr = MediaQuery.devicePixelRatioOf(context);
        // 着色器里的一切都按物理像素算：FlutterFragCoord() 给的是物理像素，
        // 而这里的 size / radius 是逻辑像素，不换算的话折射带会在高 dpr 屏上窄一大截。
        LiquidGlassSupport.applyUniforms(
          shader,
          size: size * dpr,
          radius: widget.borderRadius.topLeft.x * dpr,
          thickness: widget.thickness * dpr,
          refraction: widget.refraction * dpr,
          dispersion: widget.dispersion * dpr,
          highlight: widget.highlight,
          edgeShade: widget.edgeShade,
          sheen: widget.sheen,
          vibrancy: widget.vibrancy,
          tint: tint,
        );

        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: BackdropFilter(
            filter: ui.ImageFilter.compose(
              outer: ui.ImageFilter.shader(shader),
              inner: ui.ImageFilter.blur(
                sigmaX: widget.blurSigma,
                sigmaY: widget.blurSigma,
                tileMode: TileMode.clamp,
              ),
            ),
            child: _buildSurface(widget.surfaceColor),
          ),
        );
      },
    );
  }
}
