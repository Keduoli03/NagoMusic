import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../app/services/artwork_service.dart';
import '../../../app/services/log/log.dart';
import '../../../app/state/song_state.dart';
import '../../../components/common/letter_artwork_placeholder.dart';

const String _logTag = 'ParticleCover';

/// 「粒子封面」。
///
/// **稳态**：全图铺一层点画（stipple）质感——中心接近干净的原图，密度往边缘
/// 快速升高，边缘一圈近乎"雪花"，再往外溶解进背景。这是静态贴图，不逐帧
/// 重绘（省电，也避免几千个点每帧重算）。
///
/// **切歌过渡**（900ms）：旧封面先按"离边缘越近越先飞散"的顺序碎成粒子
/// （前 450ms），新封面的粒子再按同样的顺序从四散状态聚拢回来、边缘的最后
/// 归位（后 450ms）。这一路用的是另一张更粗的网格——过渡期间要逐帧重算几千个
/// 点的位置，密度不能和稳态点画一样高，不然真机跑不动。
///
/// **实现方式**：`dart:ui` 的 `FragmentProgram` 只有片元着色器，没有顶点
/// 着色器、没有点精灵、没有 GPU 端的逐顶点缓冲区，GPU 驱动的原生粒子系统这条
/// 路径在 Flutter 里走不通。这里改成 Dart 端算点的位置（网格采样封面颜色），
/// `CustomPainter` 批量画出来。
class ParticleCover extends StatefulWidget {
  const ParticleCover({super.key, required this.song, required this.side});

  final SongEntity? song;

  /// 封面方框的边长（逻辑像素）。解码分辨率按它换算，必须和外层容器的实际
  /// 尺寸一致——两边算错任何一处，都会回到"解码的比显示的小"那个糊的老问题。
  final double side;

  @override
  State<ParticleCover> createState() => _ParticleCoverState();
}

class _ParticleCoverState extends State<ParticleCover>
    with SingleTickerProviderStateMixin {
  /// 切歌过渡用的粗网格——逐帧重算，密度不能高。
  static const int _transitionGridSize = 44;

  /// 稳态点画用的密网格——只在封面换的时候算一次，不逐帧重算，可以铺得很密。
  static const int _stippleGridSize = 96;

  static const Duration _transitionDuration = Duration(milliseconds: 900);

  String? _loadedSongId;
  int _loadToken = 0;

  /// 稳态 / 过渡终点（聚拢目标）用的网格。
  _CoverGrid? _currentGrid;

  /// 只在过渡期间非空：正在飞散的旧封面。
  _CoverGrid? _outgoingGrid;

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: _transitionDuration,
  )..addStatusListener(_onTransitionStatus);

  @override
  void initState() {
    super.initState();
    _handleSongChanged(widget.song);
  }

  @override
  void didUpdateWidget(covariant ParticleCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.song?.id != oldWidget.song?.id) {
      _handleSongChanged(widget.song);
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    _currentGrid?.image.dispose();
    _outgoingGrid?.image.dispose();
    super.dispose();
  }

  Future<void> _handleSongChanged(SongEntity? song) async {
    if (song == null || _loadedSongId == song.id) return;
    _loadedSongId = song.id;
    final token = ++_loadToken;

    ui.Image? image;
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final decodeWidth = (widget.side * dpr).round().clamp(320, 1600);
      image = await _loadCoverBitmap(song, decodeWidth);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '封面解码失败 songId=${song.id}', e, s);
    }
    if (!mounted || token != _loadToken) {
      image?.dispose();
      return;
    }
    if (image == null) {
      AppLog.instance.d(_logTag, '三级兜底都没拿到封面字节 songId=${song.id}');
      return;
    }

    _CoverGrid? grid;
    try {
      grid = await _buildGrid(image, _transitionGridSize, _stippleGridSize);
    } catch (e, s) {
      AppLog.instance.w(_logTag, '封面取样网格构建失败 songId=${song.id}', e, s);
    }
    if (!mounted || token != _loadToken) {
      image.dispose();
      return;
    }
    if (grid == null) {
      image.dispose();
      return;
    }

    final previous = _currentGrid;
    if (previous == null) {
      // 第一次进来，没有旧封面可以分解，直接进稳态。
      setState(() => _currentGrid = grid);
      return;
    }

    // 连续快速切歌：上一次过渡可能还没播完，直接掐掉，从当前显示状态重新起播，
    // 不去追那个已经过时的动画链——这里不追求"打断也丝滑"，只保证不崩、不叠加。
    if (_transition.isAnimating) {
      _transition.stop();
      _outgoingGrid?.image.dispose();
    }

    setState(() {
      _outgoingGrid = previous;
      _currentGrid = grid;
    });
    _transition
      ..reset()
      ..forward();
  }

  void _onTransitionStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final outgoing = _outgoingGrid;
    if (outgoing == null) return;
    outgoing.image.dispose();
    if (mounted) setState(() => _outgoingGrid = null);
  }

  @override
  Widget build(BuildContext context) {
    // 没有可用封面（没嵌图、也没缓存的外置封面）时退回全站统一的首字母占位图，
    // 不能什么都不画——之前就是空着，看起来像"封面加载不出来"，其实是这首歌
    // 本来就没有封面，不是加载失败。
    if (_currentGrid == null) {
      return LetterArtworkPlaceholder(
        label: widget.song?.title ?? '',
        borderRadius: BorderRadius.zero,
        tintedBackground: true,
      );
    }
    // 稳态是静态贴图：不挂持续跑的动画，AnimatedBuilder 只在 _transition
    // 真正播放（切歌那 900ms）时才触发重绘，平时零重绘开销。
    return AnimatedBuilder(
      animation: _transition,
      builder: (context, _) {
        return CustomPaint(
          painter: _CoverPainter(
            steady: _currentGrid,
            outgoing: _outgoingGrid,
            transitionValue: _transition.value,
            transitioning: _transition.isAnimating,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- 采样网格

/// 切歌过渡用的粗粒子。
@immutable
class _CoverSample {
  const _CoverSample({
    required this.uv,
    required this.color,
    required this.rank,
    required this.scatterDir,
  });

  /// 这一格在封面里的位置，0~1。
  final Offset uv;
  final Color color;

  /// 0（画面中心）~1（贴着边缘），再叠一点哈希噪声——决定这一格在过渡里
  /// "第几个飞散 / 第几个归位"。边缘优先，呼应"材质从边缘剥落"的直觉。
  final double rank;

  /// 飞散方向（单位向量），哈希生成、每次都一样——同一格封面每次碎的样子
  /// 是固定的，不是每次重新随机，看起来才像"这块材质就是这么碎的"而不是
  /// 一次性烟花。
  final Offset scatterDir;
}

/// 稳态点画用的密粒子。
@immutable
class _StippleDot {
  const _StippleDot({
    required this.uv,
    required this.color,
    required this.edgeness,
    required this.presence,
    required this.sizeSeed,
    required this.whiteSeed,
  });

  final Offset uv;
  final Color color;

  /// 0（中心）~1（边缘），点画密度直接按它算——中心接近干净，边缘接近铺满。
  final double edgeness;

  /// 独立哈希（和 [edgeness] 不相关），配合密度曲线决定这一点画不画：
  /// `presence <= density(edgeness)` 才画。密度低的区域（画面中心）大部分点
  /// 会被这道门槛挡掉，只剩零星几个漏网的，边缘密度高时门槛松，绝大多数
  /// 点都画得出来。
  final double presence;

  /// 独立哈希，决定这一点的大小。点画质感全靠大小不一，不能所有点一个尺寸。
  final double sizeSeed;

  /// 独立哈希，决定这一点偏白还是偏原色。大部分偏白（呼应参考图那种"雪花/
  /// 高光颗粒"的观感），少数保留原色增加色彩层次，不然会变成纯黑白噪点。
  final double whiteSeed;
}

@immutable
class _CoverGrid {
  const _CoverGrid({
    required this.image,
    required this.samples,
    required this.stipple,
  });

  final ui.Image image;

  /// 粗网格，切歌过渡用。
  final List<_CoverSample> samples;

  /// 密网格，稳态点画用。
  final List<_StippleDot> stipple;
}

/// 整数哈希，出的是 0~1。不用 `Random`：点的位置抖动/方向/大小要在多次重建
/// 之间保持一致（同一张封面每次长的样子该是固定的），哈希天然满足这一点。
double _hash(int x, int y) {
  var n = x * 374761393 + y * 668265263;
  n = (n ^ (n >> 13)) * 1274126177;
  n = n ^ (n >> 16);
  return (n & 0x7fffffff) / 2147483647.0;
}

double _edgeness(double u, double v) {
  final edgeDist = math.min(math.min(u, 1 - u), math.min(v, 1 - v));
  return (1 - edgeDist / 0.5).clamp(0.0, 1.0);
}

Future<_CoverGrid?> _buildGrid(
  ui.Image image,
  int transitionGridSize,
  int stippleGridSize,
) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) return null;
  final pixels = data.buffer.asUint8List();
  final width = image.width;
  final height = image.height;

  final samples = _buildTransitionSamples(
    pixels,
    width,
    height,
    transitionGridSize,
  );
  final stipple = _buildStipple(pixels, width, height, stippleGridSize);
  return _CoverGrid(image: image, samples: samples, stipple: stipple);
}

List<_CoverSample> _buildTransitionSamples(
  Uint8List pixels,
  int width,
  int height,
  int gridSize,
) {
  final samples = <_CoverSample>[];
  for (var gy = 0; gy < gridSize; gy++) {
    for (var gx = 0; gx < gridSize; gx++) {
      final u = (gx + 0.5) / gridSize;
      final v = (gy + 0.5) / gridSize;
      final px = (u * width).floor().clamp(0, width - 1);
      final py = (v * height).floor().clamp(0, height - 1);
      final i = (py * width + px) * 4;
      final color = Color.fromARGB(
        255,
        pixels[i],
        pixels[i + 1],
        pixels[i + 2],
      );

      final noise = _hash(gx, gy);
      final rank = (_edgeness(u, v) * 0.6 + noise * 0.4).clamp(0.0, 1.0);
      final angle = _hash(gx * 7 + 3, gy * 11 + 5) * 2 * math.pi;

      samples.add(
        _CoverSample(
          uv: Offset(u, v),
          color: color,
          rank: rank,
          scatterDir: Offset(math.cos(angle), math.sin(angle)),
        ),
      );
    }
  }
  return samples;
}

List<_StippleDot> _buildStipple(
  Uint8List pixels,
  int width,
  int height,
  int gridSize,
) {
  final dots = <_StippleDot>[];
  for (var gy = 0; gy < gridSize; gy++) {
    for (var gx = 0; gx < gridSize; gx++) {
      // 格内再抖动一次位置，避免看出规整的行列——点画从来不是对齐的网格。
      final jitterX = _hash(gx * 3 + 1, gy * 5 + 2) - 0.5;
      final jitterY = _hash(gx * 7 + 4, gy * 9 + 6) - 0.5;
      final u = ((gx + 0.5 + jitterX) / gridSize).clamp(0.0, 1.0);
      final v = ((gy + 0.5 + jitterY) / gridSize).clamp(0.0, 1.0);
      final px = (u * width).floor().clamp(0, width - 1);
      final py = (v * height).floor().clamp(0, height - 1);
      final i = (py * width + px) * 4;
      final color = Color.fromARGB(
        255,
        pixels[i],
        pixels[i + 1],
        pixels[i + 2],
      );

      dots.add(
        _StippleDot(
          uv: Offset(u, v),
          color: color,
          edgeness: _edgeness(u, v),
          presence: _hash(gx * 13 + 5, gy * 17 + 11),
          sizeSeed: _hash(gx * 19 + 3, gy * 23 + 7),
          whiteSeed: _hash(gx * 29 + 2, gy * 31 + 9),
        ),
      );
    }
  }
  return dots;
}

Future<ui.Image?> _loadCoverBitmap(SongEntity song, int targetWidth) async {
  final bytes = await _loadCoverBytes(song);
  if (bytes == null || bytes.isEmpty) return null;
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

/// 按 [ArtworkWidget] 同一套优先级取封面字节，分三级兜底。
///
/// **这就是"离开播放页再回来偶尔加载不出封面"的根因。** 之前这里只调用
/// `loadArtworkBytes(preferOriginal: true)`：这个参数只读**已经存在**的原图
/// 缓存文件，缺失时不会自动补一次抓取，直接返回 null——不是"加载失败"，是
/// 压根没发起过第二次尝试。原图缓存是不是齐全，取决于别处（比如迷你播放条）
/// 有没有先用同一首歌预热过；同一首歌换个时机重进播放页，缓存状态不一定
/// 一样，所以才会"有的能有的不能"。
///
/// [ArtworkWidget] 之所以稳，是因为它在原图字节拿不到时会退到
/// `song.localCoverPath` 指向的压缩缓存文件（这个缓存写得早、写得稳），
/// 压缩缓存也没有才最后退到内嵌 tag 提取。这里照抄同一条链路。
Future<Uint8List?> _loadCoverBytes(SongEntity song) async {
  final original = await ArtworkService.instance.loadArtworkBytes(
    uri: song.uri,
    localCoverPath: song.localCoverPath,
    localAssetId: song.localAssetId,
    isLocal: song.isLocal,
    preferOriginal: true,
  );
  if (original != null && original.isNotEmpty) return original;

  final cachedPath = (song.localCoverPath ?? '').trim();
  if (cachedPath.isNotEmpty) {
    try {
      final file = File(cachedPath);
      if (await file.exists()) return await file.readAsBytes();
    } catch (e, s) {
      AppLog.instance.w(_logTag, '读压缩封面缓存失败 path=$cachedPath', e, s);
    }
  }

  return ArtworkService.instance.loadArtworkBytes(
    uri: song.uri,
    localCoverPath: song.localCoverPath,
    localAssetId: song.localAssetId,
    isLocal: song.isLocal,
    preferOriginal: false,
  );
}

// ---------------------------------------------------------------- 绘制

class _CoverPainter extends CustomPainter {
  _CoverPainter({
    required this.steady,
    required this.outgoing,
    required this.transitionValue,
    required this.transitioning,
  });

  final _CoverGrid? steady;
  final _CoverGrid? outgoing;
  final double transitionValue;
  final bool transitioning;

  /// 归属阈值的羽化宽度：rank 相差在这个范围内的粒子会同时动，不是严格的
  /// 一个一个按顺序弹出，看起来才不像逐帧点名。
  static const double _feather = 0.20;

  /// 粒子最大飞散距离，占画布短边的比例。
  static const double _travelFraction = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    if (transitioning && outgoing != null && steady != null) {
      if (transitionValue < 0.5) {
        _paintScatter(
          canvas,
          size,
          outgoing!,
          _outCubic(transitionValue / 0.5),
        );
      } else {
        _paintGather(
          canvas,
          size,
          steady!,
          _inOutCubic((transitionValue - 0.5) / 0.5),
        );
      }
      return;
    }
    _paintSteady(canvas, size, steady);
  }

  void _paintSteady(Canvas canvas, Size size, _CoverGrid? grid) {
    if (grid == null) return;
    _drawImage(canvas, size, grid.image, alpha: 1);
    _drawStipple(canvas, size, grid.stipple);
  }

  void _drawStipple(Canvas canvas, Size size, List<_StippleDot> dots) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final dot in dots) {
      // 密度曲线：指数 >1 让中间过渡更陡——画面中心几乎干净，一靠近边缘密度
      // 就迅速拉满，呼应参考图"中心清楚、边缘瞬间变浓"的观感，不是均匀渐变。
      final density = math.pow(dot.edgeness, 1.6).toDouble();
      if (dot.presence > density) continue;

      final pos = Offset(dot.uv.dx * size.width, dot.uv.dy * size.height);
      final dotSize = 0.9 + dot.sizeSeed * 2.0;
      final useWhite = dot.whiteSeed > 0.28;
      final alpha = (0.25 + 0.65 * dot.edgeness).clamp(0.0, 0.9);
      paint.color = (useWhite ? Colors.white : dot.color).withValues(
        alpha: alpha,
      );
      canvas.drawCircle(pos, dotSize / 2, paint);
    }
  }

  void _paintScatter(
    Canvas canvas,
    Size size,
    _CoverGrid grid,
    double progress,
  ) {
    // 底图整体随进度淡出——它在"剥离"，不是瞬间消失。
    final baseAlpha = (1 - progress).clamp(0.0, 1.0);
    if (baseAlpha > 0.02) {
      _drawImage(canvas, size, grid.image, alpha: baseAlpha);
    }

    final paint = Paint()..style = PaintingStyle.fill;
    for (final sample in grid.samples) {
      final localT = _smoothstep(
        sample.rank - _feather,
        sample.rank + _feather,
        progress,
      );
      if (localT <= 0.01) continue; // 还没轮到，贴在底图上，不用重复画
      final travel =
          sample.scatterDir * (_travelFraction * size.shortestSide * localT);
      final pos =
          Offset(sample.uv.dx * size.width, sample.uv.dy * size.height) +
          travel;
      final alpha = (1 - localT) * 0.9;
      if (alpha <= 0.01) continue;
      paint.color = sample.color.withValues(alpha: alpha);
      final dot = 2.2 + 1.8 * (1 - localT);
      canvas.drawRect(
        Rect.fromCenter(center: pos, width: dot, height: dot),
        paint,
      );
    }
  }

  void _paintGather(
    Canvas canvas,
    Size size,
    _CoverGrid grid,
    double progress,
  ) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final sample in grid.samples) {
      // localT：0 还在四散状态，1 已经归位。
      final localT = _smoothstep(
        sample.rank - _feather,
        sample.rank + _feather,
        progress,
      );
      if (localT >= 0.99) continue; // 已经归位的交给下面淡入的底图接管
      final travel =
          sample.scatterDir *
          (_travelFraction * size.shortestSide * (1 - localT));
      final pos =
          Offset(sample.uv.dx * size.width, sample.uv.dy * size.height) +
          travel;
      final alpha = 0.1 + localT.clamp(0.0, 1.0) * 0.8;
      paint.color = sample.color.withValues(alpha: alpha);
      final dot = 2.2 + 1.8 * (1 - localT);
      canvas.drawRect(
        Rect.fromCenter(center: pos, width: dot, height: dot),
        paint,
      );
    }

    // 底图跟着整体进度淡入，粒子负责还没归位的部分，两者在中段会有一点
    // 叠加——不是 bug，散射/聚拢两个 pass 本来就是这样叠加合成的。
    if (progress > 0.02) {
      _drawImage(canvas, size, grid.image, alpha: progress);
    }
  }

  void _drawImage(
    Canvas canvas,
    Size size,
    ui.Image image, {
    required double alpha,
  }) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Offset.zero & size;
    if (alpha >= 0.999) {
      canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    // drawImageRect 的 Paint.color 不控制整体不透明度，要用 saveLayer 才能
    // 让一次绘制按 alpha 合成——这是 Flutter 给图片调透明度的标准写法。
    canvas.saveLayer(
      dst,
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverPainter oldDelegate) {
    return steady != oldDelegate.steady ||
        outgoing != oldDelegate.outgoing ||
        transitionValue != oldDelegate.transitionValue ||
        transitioning != oldDelegate.transitioning;
  }
}

double _outCubic(double x) {
  final v = x.clamp(0.0, 1.0);
  return 1 - math.pow(1 - v, 3).toDouble();
}

double _inOutCubic(double x) {
  final v = x.clamp(0.0, 1.0);
  return v < 0.5 ? 4 * v * v * v : 1 - math.pow(-2 * v + 2, 3).toDouble() / 2;
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}
