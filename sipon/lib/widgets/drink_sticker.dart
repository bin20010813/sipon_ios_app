import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../services/drink_budget_store.dart';
import '../services/sticker_physics.dart';
import 'sipon_network_image.dart';

Color drinkStickerColorForType(String type) {
  return switch (type) {
    '鸡尾酒' => const Color(0xFFCC4C8B),
    '啤酒' => const Color(0xFFE7A73E),
    '威士忌' => const Color(0xFFB66A2C),
    '红酒' => const Color(0xFF8E2E50),
    '香槟' => const Color(0xFFD2A63F),
    '清酒' => const Color(0xFF7E9AB8),
    '烈酒' => const Color(0xFF6450A8),
    '咖啡' => const Color(0xFF8A5B3D),
    '无酒精' => const Color(0xFF3FA66A),
    _ => const Color(0xFF9A3D78),
  };
}

IconData drinkStickerIconForType(String type) {
  return switch (type) {
    '啤酒' => Icons.sports_bar_rounded,
    '威士忌' => Icons.liquor_rounded,
    '红酒' => Icons.wine_bar_rounded,
    '香槟' => Icons.celebration_rounded,
    '清酒' => Icons.local_drink_rounded,
    '烈酒' => Icons.flash_on_rounded,
    '咖啡' => Icons.coffee_rounded,
    '无酒精' => Icons.spa_rounded,
    _ => Icons.local_bar_rounded,
  };
}

String drinkStickerTitle(DrinkBudgetRecord record) {
  final name = record.drinkName.trim();
  return name.isNotEmpty ? name : record.drinkType;
}

class DrinkSticker extends StatelessWidget {
  const DrinkSticker({
    super.key,
    required this.record,
    this.size = 62,
    this.showLabel = false,
    this.rotation = 0,
    this.onTap,
  });

  final DrinkBudgetRecord record;
  final double size;
  final bool showLabel;
  final double rotation;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = record.stickerColor == null
        ? drinkStickerColorForType(record.drinkType)
        : Color(record.stickerColor!);
    final photoPath = record.photoPath;
    final stickerImagePath = record.stickerImagePath;
    final hasPhoto = _imagePathAvailable(photoPath);
    final hasCutout = _imagePathAvailable(stickerImagePath);

    final sticker = Transform.rotate(
      angle: rotation,
      child: SizedBox(
        width: size,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DrinkStickerVisual(
              size: size,
              color: color,
              icon: drinkStickerIconForType(record.drinkType),
              photoPath: hasPhoto ? photoPath : null,
              cutoutPath: hasCutout ? stickerImagePath : null,
            ),
            if (showLabel) ...[
              const SizedBox(height: 5),
              Text(
                drinkStickerTitle(record),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF3A3338),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return sticker;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size * 0.28),
        child: sticker,
      ),
    );
  }
}

class _DrinkStickerVisual extends StatelessWidget {
  const _DrinkStickerVisual({
    required this.size,
    required this.color,
    required this.icon,
    required this.photoPath,
    required this.cutoutPath,
  });

  final double size;
  final Color color;
  final IconData icon;
  final String? photoPath;
  final String? cutoutPath;

  @override
  Widget build(BuildContext context) {
    final cutoutPath = this.cutoutPath;
    if (cutoutPath != null) {
      return SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size * 0.07),
          child: _CutoutStickerImage(path: cutoutPath),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.20),
        child: photoPath != null
            ? _StickerPathImage(path: photoPath!, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.96),
                      Color.lerp(color, Colors.black, 0.18)!,
                    ],
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      right: -size * 0.12,
                      top: -size * 0.12,
                      child: Container(
                        width: size * 0.45,
                        height: size * 0.45,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Center(
                      child: Icon(icon, color: Colors.white, size: size * 0.48),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CutoutStickerImage extends StatelessWidget {
  const _CutoutStickerImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    const outlineOffsets = [
      Offset(-2, -2),
      Offset(0, -2),
      Offset(2, -2),
      Offset(-2, 0),
      Offset(2, 0),
      Offset(-2, 2),
      Offset(0, 2),
      Offset(2, 2),
    ];
    Widget image({Color? color, BlendMode? blendMode}) {
      return _StickerPathImage(
        path: path,
        fit: BoxFit.contain,
        color: color,
        colorBlendMode: blendMode,
      );
    }

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        for (final offset in outlineOffsets)
          Transform.translate(
            offset: offset,
            child: image(color: Colors.white, blendMode: BlendMode.srcIn),
          ),
        image(),
      ],
    );
  }
}

bool _imagePathAvailable(String? path) {
  if (path == null || path.isEmpty) return false;
  final uri = Uri.tryParse(path);
  if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
    return true;
  }
  return File(path).existsSync();
}

class _StickerPathImage extends StatelessWidget {
  const _StickerPathImage({
    required this.path,
    required this.fit,
    this.color,
    this.colorBlendMode,
  });

  final String path;
  final BoxFit fit;
  final Color? color;
  final BlendMode? colorBlendMode;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(path);
    final imageProvider =
        uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? CachedNetworkImageProvider(path, headers: siponImageAuthHeaders(path))
        : FileImage(File(path)) as ImageProvider;
    return Image(
      image: imageProvider,
      fit: fit,
      color: color,
      colorBlendMode: colorBlendMode,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

class DrinkStickerGravityPool extends StatefulWidget {
  const DrinkStickerGravityPool({
    super.key,
    required this.records,
    this.height = 180,
    this.onStickerTap,
  });

  final List<DrinkBudgetRecord> records;
  final double height;
  final ValueChanged<DrinkBudgetRecord>? onStickerTap;

  @override
  State<DrinkStickerGravityPool> createState() =>
      _DrinkStickerGravityPoolState();
}

class _DrinkStickerGravityPoolState extends State<DrinkStickerGravityPool>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _motion = EventChannel('sipon/sticker_motion');

  final _physics = StickerPhysics();
  late final Ticker _ticker;

  StreamSubscription<dynamic>? _subscription;
  Timer? _detailTimer;
  Offset _filtered = Offset.zero;
  Duration? _last;
  double _floatTime = 0;
  final Map<int, double> _bursts = {};

  List<DrinkBudgetRecord> _records = const [];
  Size _bounds = Size.zero;
  bool _initialized = false;
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotionSubscription();
  }

  @override
  void didUpdateWidget(covariant DrinkStickerGravityPool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_idsChanged(oldWidget.records, widget.records)) {
      _initialized = false;
      _bounds = Size.zero;
      _bursts.clear();
      _floatTime = 0;
      _detailTimer?.cancel();
      if (widget.records.isEmpty) {
        _ticker.stop();
        _last = null;
        _physics.reset(const []);
        _records = const [];
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
      _syncMotionSubscription();
      _wake();
    } else if (state == AppLifecycleState.paused) {
      _appActive = false;
      _syncMotionSubscription();
      _ticker.stop();
      _last = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _subscription = null;
    _detailTimer?.cancel();
    _ticker
      ..stop()
      ..dispose();
    super.dispose();
  }

  bool _idsChanged(List<DrinkBudgetRecord> a, List<DrinkBudgetRecord> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return true;
    }
    return false;
  }

  bool get _sensorEnabled => _appActive && TickerMode.valuesOf(context).enabled;

  void _syncMotionSubscription() {
    if (!mounted) return;
    final shouldListen = _sensorEnabled;
    if (shouldListen && _subscription == null) {
      _subscription = _motion.receiveBroadcastStream().listen(
        _onMotionEvent,
        onError: (Object _) {},
      );
    } else if (!shouldListen && _subscription != null) {
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _onMotionEvent(dynamic event) {
    if (!mounted || event is! List || event.length < 2) return;
    final x = (event[0] as num).toDouble();
    final y = (event[1] as num).toDouble();

    final target = Offset(
      x.abs() < .04 ? 0 : x * 1100,
      y.abs() < .08 ? 825 : y * 1100,
    );

    _filtered = Offset.lerp(_filtered, target, .18)!;

    if ((_filtered - _physics.gravity).distance > 35) {
      _physics.gravity = _filtered;
      _wake();
    }
  }

  void _wake() {
    if (!mounted) return;
    _physics.wake();
    if (!_ticker.isActive) {
      _last = null;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    final last = _last;
    _last = elapsed;
    if (last == null) return;

    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) return;

    _floatTime += dt;
    _bursts.updateAll((_, age) => age + dt);
    _bursts.removeWhere((_, age) => age >= 0.38);

    // 两个原步长的子步实现两倍播放速度，并保持碰撞模拟的稳定性。
    for (var step = 0; step < 2; step++) {
      _physics.step(dt, _bounds);
      if (_physics.sleeping) break;
    }

    if (_physics.sleeping &&
        _bursts.isEmpty &&
        !_physics.bodies.any((body) => body.floating)) {
      _ticker.stop();
      _last = null;
    } else {
      setState(() {});
    }
  }

  void _ensureBodies(Size size) {
    if (_initialized && _bounds == size) return;
    _bounds = size;
    _initialized = true;

    final visible = widget.records.take(36).toList();
    _records = visible;
    final scale = _poolScale(visible.length, size);
    final columns = _floatColumns(visible.length, size);
    final rows = (visible.length / columns).ceil();
    final maxBubble = 52 * scale * 1.25;
    final rowPitch = math.min((size.height - 54) / rows, maxBubble + 8);

    _physics.reset([
      for (var index = 0; index < visible.length; index++)
        _createBody(visible[index], index, scale, columns, rowPitch, size),
    ]);
    _wake();
  }

  StickerBody _createBody(
    DrinkBudgetRecord record,
    int index,
    double scale,
    int columns,
    double rowPitch,
    Size bounds,
  ) {
    final diameter = stickerSizeForAmount(record.amount) * scale;
    final row = index ~/ columns;
    final countInRow = math.min(columns, _records.length - row * columns);
    final column = index % columns;
    return StickerBody(
      position: Offset(
        bounds.width * (column + 0.5) / countInRow,
        48 + rowPitch * (row + 0.5),
      ),
      velocity: Offset.zero,
      size: diameter,
      angle: 0,
      floating: true,
    );
  }

  int _floatColumns(int count, Size bounds) {
    if (count <= 1) return 1;
    final usableHeight = math.max(1.0, bounds.height - 54);
    return math
        .sqrt(count * bounds.width / usableHeight)
        .ceil()
        .clamp(1, count);
  }

  double _poolScale(int count, Size bounds) {
    if (count == 0) return 1;
    final columns = _floatColumns(count, bounds);
    final rows = (count / columns).ceil();
    final cellWidth = bounds.width / columns;
    final cellHeight = (bounds.height - 54) / rows;
    return (math.min(cellWidth, cellHeight) - 6).clamp(18.0, 66.0) /
        (52 * 1.25);
  }

  void _popBubble(int index) {
    final body = _physics.bodies[index];
    final record = _records[index];
    if (!body.floating) {
      _detailTimer?.cancel();
      widget.onStickerTap?.call(record);
      return;
    }

    final phase = _floatTime * 1.7 + index * 1.9;
    body.position += Offset(math.sin(phase) * 2, math.cos(phase) * 4);
    body.floating = false;
    body.velocity = const Offset(0, 28);
    body.angularVelocity = index.isEven ? 0.32 : -0.32;
    _bursts[index] = 0;
    _wake();
    setState(() {});

    if (widget.onStickerTap != null) {
      _detailTimer?.cancel();
      _detailTimer = Timer(const Duration(milliseconds: 850), () {
        if (mounted &&
            index < _records.length &&
            _records[index].id == record.id) {
          widget.onStickerTap?.call(record);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) {
      return Container(
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFFBF8FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFF0E3EB)),
        ),
        child: const Text(
          '还没有贴纸记录',
          style: TextStyle(
            color: Color(0xFF8E8790),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        _ensureBodies(size);
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFF8FB), Color(0xFFF7EEF5)],
              ),
              border: Border.all(color: const Color(0xFFF0E3EB)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 16,
                  top: 13,
                  child: Text(
                    '${widget.records.length} 枚贴纸',
                    style: const TextStyle(
                      color: Color(0xFF8E8790),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                for (var index = 0; index < _records.length; index++)
                  _buildSticker(index),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSticker(int index) {
    final body = _physics.bodies[index];
    final record = _records[index];
    final floating = body.floating;
    final burstAge = _bursts[index];
    final bubbleSize = body.size * 1.25;
    final visualSize = floating
        ? bubbleSize
        : burstAge != null
        ? bubbleSize * 1.6
        : body.size;
    final phase = _floatTime * 1.7 + index * 1.9;
    final bob = floating
        ? Offset(math.sin(phase) * 2, math.cos(phase) * 4)
        : Offset.zero;

    return Positioned(
      left: body.position.dx + bob.dx - visualSize / 2,
      top: body.position.dy + bob.dy - visualSize / 2,
      child: Transform.rotate(
        angle: body.angle,
        child: RepaintBoundary(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _popBubble(index),
            child: CustomPaint(
              painter: _StickerBubblePainter(
                floating: floating,
                bubbleRadius: bubbleSize * 0.48,
                burstProgress: burstAge == null ? null : burstAge / 0.38,
              ),
              child: SizedBox.square(
                dimension: visualSize,
                child: Center(
                  child: DrinkSticker(
                    record: record,
                    size: floating ? body.size * 0.78 : body.size,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StickerBubblePainter extends CustomPainter {
  const _StickerBubblePainter({
    required this.floating,
    required this.bubbleRadius,
    this.burstProgress,
  });

  final bool floating;
  final double bubbleRadius;
  final double? burstProgress;

  @override
  void paint(Canvas canvas, Size size) {
    if (!floating && burstProgress == null) return;
    final center = size.center(Offset.zero);
    final radius = bubbleRadius;

    if (floating) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.45, -0.5),
            radius: 0.95,
            colors: [
              Colors.white.withValues(alpha: 0.32),
              const Color(0xFFBDEDEB).withValues(alpha: 0.16),
              const Color(0xFFD8B1EA).withValues(alpha: 0.24),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0xFFC9E9F0).withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.7,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        -2.75,
        0.95,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.94)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3,
      );
      canvas.drawCircle(
        center + Offset(radius * 0.58, radius * 0.55),
        radius * 0.065,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    final progress = burstProgress;
    if (progress != null) {
      final alpha = (1 - progress).clamp(0.0, 1.0);
      final burstRadius = radius * (1 + progress * 0.5);
      final paint = Paint()
        ..color = const Color(0xFFB8DBE7).withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * alpha;
      canvas.drawCircle(center, burstRadius, paint);
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * (burstRadius + 2),
          center + direction * (burstRadius + 7 + progress * 8),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StickerBubblePainter oldDelegate) =>
      oldDelegate.floating != floating ||
      oldDelegate.bubbleRadius != bubbleRadius ||
      oldDelegate.burstProgress != burstProgress;
}
