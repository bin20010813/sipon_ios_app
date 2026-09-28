import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/sticker_physics.dart';

void main() {
  test(
    'bubble rises to the top while a popped sticker falls to the bottom',
    () {
      final physics = StickerPhysics();
      final bubble = StickerBody(
        position: const Offset(70, 110),
        velocity: Offset.zero,
        size: 40,
        floating: true,
      );
      final falling = StickerBody(
        position: const Offset(190, 70),
        velocity: Offset.zero,
        size: 40,
      );
      physics.reset([bubble, falling]);

      for (var i = 0; i < 240; i++) {
        physics.step(1 / 60, const Size(260, 180));
      }

      expect(bubble.position.dy, closeTo(bubble.collisionSize / 2, 0.1));
      expect(falling.position.dy, closeTo(160, 0.1));
    },
  );

  test('tilt moves bubbles opposite to falling stickers at a slower speed', () {
    final physics = StickerPhysics(gravity: const Offset(450, 825));
    final bubble = StickerBody(
      position: const Offset(140, 100),
      velocity: Offset.zero,
      size: 36,
      floating: true,
    );
    final falling = StickerBody(
      position: const Offset(140, 100),
      velocity: Offset.zero,
      size: 36,
    );
    // Keep them in separate simulations so their collision does not affect speed.
    physics.reset([bubble]);
    for (var i = 0; i < 30; i++) {
      physics.step(1 / 60, const Size(400, 400));
    }
    final bubbleShift = bubble.position.dx - 140;
    physics.reset([falling]);
    for (var i = 0; i < 30; i++) {
      physics.step(1 / 60, const Size(400, 400));
    }
    final fallingShift = falling.position.dx - 140;

    expect(bubbleShift, lessThan(0));
    expect(fallingShift, greaterThan(0));
    expect(bubbleShift.abs(), lessThan(fallingShift));
  });

  test('a crowded mix stays inside the pool without overlapping', () {
    final physics = StickerPhysics();
    final bodies = [
      for (var i = 0; i < 13; i++)
        StickerBody(
          position: Offset(28.0 + (i % 5) * 55, 38.0 + (i ~/ 5) * 52),
          velocity: Offset.zero,
          size: 36,
          floating: i.isEven,
        ),
    ];
    physics.reset(bodies);
    const bounds = Size(300, 180);

    for (var frame = 0; frame < 180; frame++) {
      physics.step(1 / 60, bounds);
    }

    for (var i = 0; i < bodies.length; i++) {
      final a = bodies[i];
      final half = a.collisionSize / 2;
      expect(a.position.dx, inInclusiveRange(half, bounds.width - half));
      expect(a.position.dy, inInclusiveRange(half, bounds.height - half));
      for (var j = i + 1; j < bodies.length; j++) {
        final b = bodies[j];
        expect(
          (a.position - b.position).distance,
          greaterThanOrEqualTo((a.collisionSize + b.collisionSize) / 2 - 0.5),
        );
      }
    }
  });

  test('rising bubble and falling sticker do not overlap after contact', () {
    final physics = StickerPhysics();
    final bubble = StickerBody(
      position: const Offset(100, 130),
      velocity: Offset.zero,
      size: 40,
      floating: true,
    );
    final falling = StickerBody(
      position: const Offset(100, 50),
      velocity: Offset.zero,
      size: 40,
    );
    physics.reset([bubble, falling]);

    for (var i = 0; i < 180; i++) {
      physics.step(1 / 60, const Size(200, 180));
      final requiredDistance =
          (bubble.collisionSize + falling.collisionSize) / 2;
      expect(
        (bubble.position - falling.position).distance,
        greaterThanOrEqualTo(requiredDistance - 0.1),
      );
    }
  });
}
