import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/drink_budget_store.dart';

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
        ? NetworkImage(path)
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<_StickerParticle> _particles = const [];
  Size _lastSize = Size.zero;
  bool _playScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didUpdateWidget(covariant DrinkStickerGravityPool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records.map((r) => r.id).join(',') !=
        widget.records.map((r) => r.id).join(',')) {
      _particles = const [];
      _lastSize = Size.zero;
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureParticles(Size size) {
    if (_particles.isNotEmpty && _lastSize == size) return;
    _lastSize = size;
    final visible = widget.records.take(36).toList();
    final random = math.Random(visible.length * 19 + 7);
    _particles = [
      for (var index = 0; index < visible.length; index++)
        _StickerParticle(
          record: visible[index],
          size: 40 + random.nextDouble() * 18,
          x: 14 + random.nextDouble() * math.max(24, size.width - 70),
          y: -90 - random.nextDouble() * 180 - index * 9,
          drift: -18 + random.nextDouble() * 36,
          rotation: -0.25 + random.nextDouble() * 0.5,
          angularVelocity: -0.18 + random.nextDouble() * 0.36,
          delay: visible.length <= 1
              ? 0
              : index / (visible.length - 1) * 0.32,
        ),
    ];
    _schedulePlayOnce();
  }

  void _schedulePlayOnce() {
    if (_playScheduled) return;
    _playScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playScheduled = false;
      if (!mounted || _particles.isEmpty) return;
      _controller.forward(from: 0);
    });
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
        _ensureParticles(size);
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
                for (final particle in _particles)
                  _AnimatedStickerParticle(
                    particle: particle,
                    animation: _controller,
                    bounds: size,
                    onTap: widget.onStickerTap == null
                        ? null
                        : () => widget.onStickerTap!(particle.record),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedStickerParticle extends StatelessWidget {
  const _AnimatedStickerParticle({
    required this.particle,
    required this.animation,
    required this.bounds,
    this.onTap,
  });

  final _StickerParticle particle;
  final Animation<double> animation;
  final Size bounds;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      child: AnimatedBuilder(
        animation: animation,
        child: RepaintBoundary(
          child: DrinkSticker(
            record: particle.record,
            size: particle.size,
            onTap: onTap,
          ),
        ),
        builder: (context, child) {
          final progress = ((animation.value - particle.delay) /
                  math.max(0.001, 1 - particle.delay))
              .clamp(0.0, 1.0);
          final fallProgress = Curves.bounceOut.transform(progress);
          final landingY = bounds.height - particle.size - 8;
          final y = particle.y + (landingY - particle.y) * fallProgress;
          final settleFactor = 1 - progress;
          final x = (particle.x +
                  math.sin(progress * math.pi) *
                      particle.drift *
                      settleFactor)
              .clamp(8.0, bounds.width - particle.size - 8);
          final rotation =
              particle.rotation +
              particle.angularVelocity *
                  math.sin(progress * math.pi * 3) *
                  settleFactor;

          return Transform.translate(
            offset: Offset(x, y),
            child: Transform.rotate(angle: rotation, child: child),
          );
        },
      ),
    );
  }
}

class _StickerParticle {
  _StickerParticle({
    required this.record,
    required this.size,
    required this.x,
    required this.y,
    required this.drift,
    required this.rotation,
    required this.angularVelocity,
    required this.delay,
  });

  final DrinkBudgetRecord record;
  final double size;
  final double x;
  final double y;
  final double drift;
  final double rotation;
  final double angularVelocity;
  final double delay;
}
