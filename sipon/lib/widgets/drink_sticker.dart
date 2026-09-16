import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/drink_budget_store.dart';

Color drinkStickerColor(DrinkBudgetRecord record) {
  if (record.stickerColor != null) {
    return Color(record.stickerColor!);
  }
  return drinkStickerColorForType(record.drinkType);
}

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
    this.size = 68,
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
    final color = drinkStickerColor(record);
    final photoPath = record.photoPath;
    final hasPhoto = photoPath != null && File(photoPath).existsSync();
    final title = drinkStickerTitle(record);
    final sticker = Transform.rotate(
      angle: rotation,
      child: Container(
        width: size,
        constraints: BoxConstraints(minHeight: showLabel ? size + 18 : size),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
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
                child: hasPhoto
                    ? Image.file(File(photoPath), fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: 0.94),
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
                              child: Icon(
                                drinkStickerIconForType(record.drinkType),
                                color: Colors.white,
                                size: size * 0.46,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 5),
              Text(
                title,
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

    if (onTap == null) {
      return sticker;
    }
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

class DrinkStickerGravityPool extends StatefulWidget {
  const DrinkStickerGravityPool({
    super.key,
    required this.records,
    this.height = 190,
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(() => setState(() {}))
      ..repeat(min: 0, max: 1, period: const Duration(milliseconds: 1800));
  }

  @override
  void didUpdateWidget(covariant DrinkStickerGravityPool oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records.map((r) => r.id).join(',') !=
        widget.records.map((r) => r.id).join(',')) {
      _particles = const [];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ensureParticles(Size size) {
    if (_particles.isNotEmpty && _lastSize == size) {
      return;
    }
    _lastSize = size;
    final visible = widget.records.take(36).toList();
    final random = math.Random(visible.length * 17 + 9);
    _particles = [
      for (var index = 0; index < visible.length; index++)
        _StickerParticle(
          record: visible[index],
          size: 42 + random.nextDouble() * 18,
          x: 16 + random.nextDouble() * math.max(24, size.width - 72),
          y: -80 - random.nextDouble() * 160 - index * 9,
          velocity: 34 + random.nextDouble() * 28,
          drift: -18 + random.nextDouble() * 36,
          rotation: -0.25 + random.nextDouble() * 0.5,
          angularVelocity: -0.18 + random.nextDouble() * 0.36,
        ),
    ];
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
        final t = _controller.value;
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
                    '${widget.records.length} 枚本月贴纸',
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
                    time: t,
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
    required this.time,
    required this.bounds,
    this.onTap,
  });

  final _StickerParticle particle;
  final double time;
  final Size bounds;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fallDistance = bounds.height + 180;
    final cycle = (time + particle.seed) % 1;
    final eased = Curves.easeInOut.transform(cycle);
    final rawY = particle.y + fallDistance * eased;
    final y = rawY > bounds.height - particle.size - 8
        ? bounds.height - particle.size - 8 - math.sin(cycle * math.pi * 8) * 5
        : rawY;
    final x = (particle.x + math.sin(cycle * math.pi * 2) * particle.drift)
        .clamp(8.0, bounds.width - particle.size - 8);
    final rotation =
        particle.rotation +
        particle.angularVelocity * math.sin(cycle * math.pi * 2);

    return Positioned(
      left: x,
      top: y,
      child: DrinkSticker(
        record: particle.record,
        size: particle.size,
        rotation: rotation,
        onTap: onTap,
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
    required this.velocity,
    required this.drift,
    required this.rotation,
    required this.angularVelocity,
  }) : seed = ((record.id.hashCode & 0xffff) / 0xffff);

  final DrinkBudgetRecord record;
  final double size;
  final double x;
  final double y;
  final double velocity;
  final double drift;
  final double rotation;
  final double angularVelocity;
  final double seed;
}
