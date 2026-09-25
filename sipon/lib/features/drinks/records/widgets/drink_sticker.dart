import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/drink_budget_store.dart';
import '../controllers/sticker_physics.dart';
import '../../../../shared/widgets/sipon_network_image.dart';

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
  Offset _filtered = Offset.zero;
  Duration? _last;

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

    // 两个原步长的子步实现两倍播放速度，并保持碰撞模拟的稳定性。
    for (var step = 0; step < 2; step++) {
      _physics.step(dt, _bounds);
      if (_physics.sleeping) break;
    }

    if (_physics.sleeping) {
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
    final random = math.Random(visible.length * 19 + 7);

    _physics.reset([
      for (var index = 0; index < visible.length; index++)
        _createBody(visible[index], scale, random, size),
    ]);
    _wake();
  }

  StickerBody _createBody(
    DrinkBudgetRecord record,
    double scale,
    math.Random random,
    Size bounds,
  ) {
    final diameter = stickerSizeForAmount(record.amount) * scale;
    final left = diameter / 2;
    final right = math.max(left, bounds.width - diameter / 2);
    return StickerBody(
      position: Offset(
        left + random.nextDouble() * (right - left),
        -diameter - random.nextDouble() * 140,
      ),
      velocity: Offset(
        -30 + random.nextDouble() * 60,
        -20 + random.nextDouble() * 40,
      ),
      size: diameter,
      angle: -0.25 + random.nextDouble() * 0.5,
      angularVelocity: -0.4 + random.nextDouble() * 0.8,
    );
  }

  double _poolScale(int count, Size bounds) {
    if (count <= 1) return 1;
    final area = math.max(1.0, bounds.width * bounds.height);
    final need = count * 46.0 * 46.0;
    final ratio = area * 0.78 / need;
    if (ratio >= 1) return 1;
    return math.sqrt(ratio).clamp(0.5, 1.0);
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

    return Positioned(
      left: body.position.dx - body.size / 2,
      top: body.position.dy - body.size / 2,
      child: Transform.rotate(
        angle: body.angle,
        child: RepaintBoundary(
          child: DrinkSticker(
            record: record,
            size: body.size,
            onTap: widget.onStickerTap == null
                ? null
                : () => widget.onStickerTap!(record),
          ),
        ),
      ),
    );
  }
}
