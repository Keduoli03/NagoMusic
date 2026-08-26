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
/// **播放过程**：开局是完整高清原封面；播放进度越靠后，最外 5% 越多地剥落为
/// 粒子。已经剥落的粒子会在封面四周持续缓慢飞舞，暂停时冻结。边缘粒子直接移植自
/// mica-music 的 `buildEdgeParticles()`：固定 Java Random 序列、同一组 band /
/// size / scatter 参数；先生成 3,200 枚候选碎片，再用固定的簇状门控留出疏密与
/// 空隙，每枚方块只采样自己 UV 的封面颜色。
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
  const ParticleCover({
    super.key,
    required this.song,
    required this.side,
    required this.playbackProgress,
    required this.isPlaying,
  });

  final SongEntity? song;

  /// 封面方框的边长（逻辑像素）。解码分辨率按它换算，必须和外层容器的实际
  /// 尺寸一致——两边算错任何一处，都会回到"解码的比显示的小"那个糊的老问题。
  final double side;

  /// 当前播放位置占歌曲总时长的比例，控制边缘实际剥落程度。
  final double playbackProgress;

  /// 只控制粒子是否继续飞舞；暂停不会改变已经剥落的程度。
  final bool isPlaying;

  @override
  State<ParticleCover> createState() => _ParticleCoverState();
}

class _ParticleCoverState extends State<ParticleCover>
    with TickerProviderStateMixin {
  /// 切歌过渡用的粗网格——逐帧重算，密度不能高。
  static const int _transitionGridSize = 44;

  /// 原 OpenGL 的 11,000 点还会经过 shard mask；Flutter atlas 是实心方块，
  /// 因此只生成 3,200 枚候选点，随后再经过簇状门控筛成更稀疏的可见碎片。
  static const int _edgeParticleCount = 3200;

  static const Duration _transitionDuration = Duration(milliseconds: 900);
  static const Duration _motionDuration = Duration(seconds: 9);

  String? _loadedSongId;
  int _loadToken = 0;
  bool _didLoadInitialSong = false;

  /// 稳态 / 过渡终点（聚拢目标）用的网格。
  _CoverGrid? _currentGrid;

  /// 只在过渡期间非空：正在飞散的旧封面。
  _CoverGrid? _outgoingGrid;

  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: _transitionDuration,
  )..addStatusListener(_onTransitionStatus);

  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: _motionDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadInitialSong) return;
    _didLoadInitialSong = true;
    _syncMotion();
    _handleSongChanged(widget.song);
  }

  @override
  void didUpdateWidget(covariant ParticleCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) _syncMotion();
    if (widget.song?.id != oldWidget.song?.id) {
      _motion.value = 0;
      _handleSongChanged(widget.song);
    }
  }

  void _syncMotion() {
    if (widget.isPlaying) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    _transition.dispose();
    _motion.dispose();
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
      grid = await _buildGrid(image, _transitionGridSize, _edgeParticleCount);
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
    return CustomPaint(
      painter: _CoverPainter(
        steady: _currentGrid,
        outgoing: _outgoingGrid,
        transition: _transition,
        motion: _motion,
        playbackProgress: widget.playbackProgress,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      child: const SizedBox.expand(),
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

/// 稳态时覆盖在高清原图边缘的一枚碎片。
@immutable
class _EdgeParticle {
  const _EdgeParticle({
    required this.uv,
    required this.home,
    required this.scatter,
    required this.size,
    required this.edgeWeight,
    required this.seed,
  });

  /// 原仓库的 `aUv`：颜色只采样该粒子在封面上的对应像素。
  final Offset uv;

  /// 原仓库顶点缓冲中的 home / scatter，范围为 OpenGL 的 -1~1。
  final Offset home;
  final Offset scatter;
  final double size;
  final double edgeWeight;

  /// 原仓库每个粒子自带的随机种子，用于错开出现时机和飞舞相位。
  final double seed;
}

@immutable
class _CoverGrid {
  const _CoverGrid({
    required this.image,
    required this.samples,
    required this.edgeParticles,
  });

  final ui.Image image;

  /// 粗网格，切歌过渡用。
  final List<_CoverSample> samples;

  /// 只分布在封面最外 5% 的碎片。
  final List<_EdgeParticle> edgeParticles;
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
  int edgeParticleCount,
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
  final edgeParticles = _buildEdgeParticles(edgeParticleCount);
  return _CoverGrid(
    image: image,
    samples: samples,
    edgeParticles: edgeParticles,
  );
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

List<_EdgeParticle> _buildEdgeParticles(int count) {
  // 下面的 seed、5% 边缘带、分布指数和散射范围均直接来自原仓库的
  // buildEdgeParticles()，不再为本项目另设一套视觉参数。
  final random = _JavaRandom(0xE06ED957);
  const edgeBand = 0.050;
  final particles = <_EdgeParticle>[];
  for (var index = 0; index < count; index++) {
    final side = random.nextInt(4);
    final layer = math.pow(random.nextFloat(), 2.65).toDouble();
    final edgeDepth = edgeBand * layer;
    final edgeWeight = math
        .pow(1 - _smoothstep(0, edgeBand, edgeDepth), 1.35)
        .toDouble();
    final tangent = random.nextFloat();
    final tangentJitter = random.between(-0.035, 0.035) * (0.35 + edgeWeight);
    late double u;
    late double v;
    var normalX = 0.0;
    var normalY = 0.0;
    switch (side) {
      case 0:
        u = (tangent + tangentJitter).clamp(0.0, 1.0);
        v = edgeDepth.clamp(0.0, 1.0);
        normalY = 1;
      case 1:
        u = (1 - edgeDepth).clamp(0.0, 1.0);
        v = (tangent + tangentJitter).clamp(0.0, 1.0);
        normalX = 1;
      case 2:
        u = (tangent + tangentJitter).clamp(0.0, 1.0);
        v = (1 - edgeDepth).clamp(0.0, 1.0);
        normalY = -1;
      default:
        u = edgeDepth.clamp(0.0, 1.0);
        v = (tangent + tangentJitter).clamp(0.0, 1.0);
        normalX = -1;
    }
    final homeX = u * 2 - 1;
    final homeY = 1 - v * 2;
    final outward =
        random.between(0.018, 0.34) * edgeBand * (0.28 + edgeWeight * 1.18) * 2;
    final shear =
        random.between(-0.11, 0.11) * edgeBand * (0.25 + edgeWeight) * 2;
    final scatter = Offset(
      homeX + normalX * outward + normalY * shear,
      homeY + normalY * outward + normalX * shear,
    );
    random.between(-1, 1); // homeZ
    final size =
        random.between(2.0, 3.4) + edgeWeight * random.between(1.4, 3.4);
    random.between(-0.08, 0.16); // scatterZ
    final seed = random.nextFloat();

    // 原始随机池均匀铺满四条边，在 Flutter 的实心方块下很容易形成连续边框。
    // 用两层沿边波形形成簇与空隙，再以固定哈希抽样；同一封面每次分布一致，
    // 但不会四边等密度地围成一圈。
    final edgeTangent = side.isEven ? u : v;
    final primaryCluster =
        0.5 + 0.5 * math.sin(2 * math.pi * (edgeTangent * 2.35 + side * 0.17));
    final secondaryCluster =
        0.5 + 0.5 * math.sin(2 * math.pi * (edgeTangent * 5.1 + side * 0.31));
    final clusterStrength =
        math.pow(primaryCluster, 2.4) * (0.55 + 0.45 * secondaryCluster);
    final keepChance = 0.08 + 0.72 * clusterStrength;
    if (_hash(index * 37 + side, index * 53 + 11) > keepChance) continue;

    particles.add(
      _EdgeParticle(
        uv: Offset(u, v),
        home: Offset(homeX, homeY),
        scatter: scatter,
        size: size,
        edgeWeight: edgeWeight,
        seed: seed,
      ),
    );
  }
  return particles;
}

/// `java.util.Random` 的 48-bit LCG，用来复现原仓库的固定粒子序列。
class _JavaRandom {
  _JavaRandom(int seed) : _seed = (seed ^ _multiplier) & _mask;

  static const int _multiplier = 0x5DEECE66D;
  static const int _addend = 0xB;
  static const int _mask = (1 << 48) - 1;

  int _seed;

  int _next(int bits) {
    _seed = (_seed * _multiplier + _addend) & _mask;
    return _seed >> (48 - bits);
  }

  bool nextBoolean() => _next(1) != 0;

  double nextFloat() => _next(24) / (1 << 24);

  double between(double min, double max) => min + nextFloat() * (max - min);

  int nextInt(int bound) {
    if (bound <= 0) throw ArgumentError.value(bound, 'bound');
    if ((bound & -bound) == bound) return (bound * _next(31)) >> 31;
    while (true) {
      final bits = _next(31);
      final value = bits % bound;
      if (bits - value + (bound - 1) >= 0) return value;
    }
  }
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
    required this.transition,
    required this.motion,
    required this.playbackProgress,
    required this.devicePixelRatio,
  }) : super(repaint: Listenable.merge([transition, motion]));

  final _CoverGrid? steady;
  final _CoverGrid? outgoing;
  final Animation<double> transition;
  final Animation<double> motion;
  final double playbackProgress;
  final double devicePixelRatio;

  /// 归属阈值的羽化宽度：rank 相差在这个范围内的粒子会同时动，不是严格的
  /// 一个一个按顺序弹出，看起来才不像逐帧点名。
  static const double _feather = 0.20;

  /// 粒子最大飞散距离，占画布短边的比例。
  static const double _travelFraction = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    final transitionValue = transition.value;
    if (transition.isAnimating && outgoing != null && steady != null) {
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
    final dissolve = _smoothstep(0, 1, playbackProgress);
    _drawFeatheredImage(canvas, size, grid, dissolve);
    if (dissolve > 0.0001) {
      _drawEdgeParticles(canvas, size, grid, dissolve, motion.value);
    }
  }

  /// 原图不做像素化，只在原仓库的 EdgeParticleBand=0.05 区间渐隐。
  void _drawFeatheredImage(
    Canvas canvas,
    Size size,
    _CoverGrid grid,
    double dissolve,
  ) {
    const edgeBand = 0.050;
    // 原仓库 StableEdgeResidueAlpha=0.38；最外沿仍保留一层原图，不把封面
    // 挖成透明框，再由碎片补满。
    final edgeResidue = Color.fromRGBO(0, 0, 0, 1 - 0.62 * dissolve);
    const opaque = Color.fromARGB(255, 0, 0, 0);
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawImageRect(
      grid.image,
      Rect.fromLTWH(
        0,
        0,
        grid.image.width.toDouble(),
        grid.image.height.toDouble(),
      ),
      bounds,
      Paint()..filterQuality = FilterQuality.high,
    );
    final maskPaint = Paint()..blendMode = BlendMode.dstIn;
    maskPaint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(size.width, 0),
      [edgeResidue, opaque, opaque, edgeResidue],
      const [0, edgeBand, 1 - edgeBand, 1],
    );
    canvas.drawRect(bounds, maskPaint);
    maskPaint.shader = ui.Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      [edgeResidue, opaque, opaque, edgeResidue],
      const [0, edgeBand, 1 - edgeBand, 1],
    );
    canvas.drawRect(bounds, maskPaint);
    _eraseDetachedFragments(canvas, size, grid, dissolve);
    canvas.restore();
  }

  /// 从原封面上挖走已经飞出的碎片。挖孔与粒子使用同一个 UV、尺寸和出现
  /// 进度，因此看到的是材质从原位置剥落，而不是完整矩形外另撒一圈点。
  void _eraseDetachedFragments(
    Canvas canvas,
    Size size,
    _CoverGrid grid,
    double dissolve,
  ) {
    final density = math.min(devicePixelRatio, 1.8);
    final transforms = <RSTransform>[];
    final textureRects = <Rect>[];
    final colors = <Color>[];
    for (final particle in grid.edgeParticles) {
      final localProgress = _particleProgress(particle, dissolve);
      if (localProgress <= 0.002) continue;
      final home = Offset(
        (particle.home.dx + 1) * 0.5 * size.width,
        (1 - particle.home.dy) * 0.5 * size.height,
      );
      final shardSize = _particleLogicalSize(particle, density);
      transforms.add(
        RSTransform.fromComponents(
          rotation: 0,
          scale: shardSize * (0.9 + 0.35 * localProgress),
          anchorX: 0.5,
          anchorY: 0.5,
          translateX: home.dx,
          translateY: home.dy,
        ),
      );
      textureRects.add(_particleSourceRect(particle, grid.image));
      colors.add(
        Color.fromRGBO(
          255,
          255,
          255,
          localProgress * (0.72 + 0.28 * particle.edgeWeight),
        ),
      );
    }
    if (transforms.isEmpty) return;
    canvas.drawAtlas(
      grid.image,
      transforms,
      textureRects,
      colors,
      BlendMode.modulate,
      null,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..isAntiAlias = false
        ..filterQuality = FilterQuality.none,
    );
  }

  /// 用原仓库 buildEdgeParticles() 的分布生成候选碎片，再经簇状门控后覆盖
  /// 渐隐区。颜色严格采样各自 UV，不再用白点或黑点替代。
  void _drawEdgeParticles(
    Canvas canvas,
    Size size,
    _CoverGrid grid,
    double dissolve,
    double motionPhase,
  ) {
    final particles = grid.edgeParticles;
    if (particles.isEmpty) return;
    final density = math.min(devicePixelRatio, 1.8);
    final transforms = <RSTransform>[];
    final textureRects = <Rect>[];
    final colors = <Color>[];
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    for (final particle in particles) {
      final localProgress = _particleProgress(particle, dissolve);
      final visibility = localProgress;
      if (visibility <= 0.002) continue;

      // 大部分碎片停留在剥落边缘附近，少量碎片飞到更远处形成游离尘屑，
      // 不再把所有点挤在同一圈宽度里。
      final flightScale = 0.72 + 2.28 * math.pow(particle.seed, 2.6).toDouble();
      final basePosition =
          particle.home +
          (particle.scatter - particle.home) *
              (_outCubic(localProgress) * flightScale);
      // 频率必须是整数，9 秒循环首尾才不会跳帧。两个不同频率组成轻微的
      // 椭圆漂移，不是所有粒子一起呼吸。
      final xCycles = 1 + (particle.seed * 3).floor();
      final yCycles = 2 + (particle.seed * 4).floor();
      final xAngle = 2 * math.pi * (motionPhase * xCycles + particle.seed);
      final yAngle =
          2 * math.pi * (motionPhase * yCycles + particle.seed * 1.73);
      final flutterRadius = (0.005 + 0.017 * particle.edgeWeight) * visibility;
      final position =
          basePosition +
          Offset(
            math.cos(xAngle) * flutterRadius,
            math.sin(yAngle) * flutterRadius * 0.78,
          );
      final fragmentPos = Offset(
        (position.dx + 1) * 0.5 * size.width,
        (1 - position.dy) * 0.5 * size.height,
      );
      final shardSize =
          _particleLogicalSize(particle, density) *
          (0.48 + 0.38 * localProgress);
      transforms.add(
        RSTransform.fromComponents(
          rotation: 0,
          scale: shardSize,
          anchorX: 0.5,
          anchorY: 0.5,
          translateX: fragmentPos.dx,
          translateY: fragmentPos.dy,
        ),
      );
      textureRects.add(_particleSourceRect(particle, grid.image));
      // 原仓库 StableEdgeResidueAlpha=0.38。
      final distanceFade = 1 - 0.24 * math.pow(particle.seed, 2).toDouble();
      final alpha =
          0.33 *
          (0.72 + 0.28 * particle.edgeWeight) *
          visibility *
          distanceFade;
      colors.add(Color.fromRGBO(255, 255, 255, alpha));
    }
    canvas.drawAtlas(
      grid.image,
      transforms,
      textureRects,
      colors,
      BlendMode.modulate,
      null,
      paint,
    );
  }

  double _particleProgress(_EdgeParticle particle, double dissolve) {
    // 外侧先剥落、内侧后剥落；最早阈值仍大于 0，确保开局绝对完整。
    final revealAt =
        0.015 + (1 - particle.edgeWeight) * 0.78 + particle.seed * 0.18;
    return _smoothstep(revealAt, math.min(1, revealAt + 0.12), dissolve);
  }

  double _particleLogicalSize(_EdgeParticle particle, double density) {
    return math.max(
      1 / devicePixelRatio,
      particle.size * 0.83 * density / devicePixelRatio,
    );
  }

  Rect _particleSourceRect(_EdgeParticle particle, ui.Image image) {
    final sourceX = (particle.uv.dx * image.width).floor().clamp(
      0,
      image.width - 1,
    );
    final sourceY = (particle.uv.dy * image.height).floor().clamp(
      0,
      image.height - 1,
    );
    return Rect.fromLTWH(sourceX.toDouble(), sourceY.toDouble(), 1, 1);
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
        transition != oldDelegate.transition ||
        motion != oldDelegate.motion ||
        playbackProgress != oldDelegate.playbackProgress ||
        devicePixelRatio != oldDelegate.devicePixelRatio;
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

@visibleForTesting
Future<ui.Image> renderParticleCoverSteadyForTesting(
  Uint8List encodedArtwork, {
  int side = 320,
  double devicePixelRatio = 3,
  double playbackProgress = 1,
  double motionPhase = 0,
}) async {
  final codec = await ui.instantiateImageCodec(
    encodedArtwork,
    targetWidth: side,
    targetHeight: side,
  );
  final frame = await codec.getNextFrame();
  codec.dispose();
  final grid = await _buildGrid(
    frame.image,
    _ParticleCoverState._transitionGridSize,
    _ParticleCoverState._edgeParticleCount,
  );
  if (grid == null) {
    frame.image.dispose();
    throw StateError('Unable to sample particle-cover artwork');
  }

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size.square(side.toDouble());
  _CoverPainter(
    steady: grid,
    outgoing: null,
    transition: const AlwaysStoppedAnimation(0),
    motion: AlwaysStoppedAnimation(motionPhase),
    playbackProgress: playbackProgress,
    devicePixelRatio: devicePixelRatio,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(side, side);
  picture.dispose();
  frame.image.dispose();
  return rendered;
}
