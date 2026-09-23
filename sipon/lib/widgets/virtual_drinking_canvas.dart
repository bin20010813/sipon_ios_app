import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/virtual_drinking_models.dart';

class VirtualSceneCanvas extends StatelessWidget {
  const VirtualSceneCanvas({
    super.key,
    required this.scene,
    required this.progress,
  });

  final VirtualScene scene;
  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ScenePainter(scene, progress),
    child: const SizedBox.expand(),
  );
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(this.scene, this.progress);

  final VirtualScene scene;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = scene.backgroundColors;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(Offset.zero & size),
    );
    if (scene.renderConfig['renderer'] != 'scene-v1') return;

    if (scene.code == 'rain_window') {
      _paintWindow(canvas, size);
    } else if (scene.code == 'sunset_beach') {
      _paintBeach(canvas, size);
    } else if (scene.code == 'night_bar') {
      _paintBar(canvas, size);
    }

    final table = Rect.fromLTWH(
      0,
      size.height * 0.76,
      size.width,
      size.height * 0.24,
    );
    canvas.drawRect(
      table,
      Paint()..color = const Color(0xFF291E1D).withValues(alpha: 0.57),
    );
    for (var i = 0; i < 8; i++) {
      final y = size.height * (0.78 + i * 0.035);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.025)
          ..strokeWidth = 1,
      );
    }
  }

  void _paintWindow(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(
      size.width * 0.1,
      size.height * 0.07,
      size.width * 0.8,
      size.height * 0.64,
    );
    canvas.drawRect(
      frame,
      Paint()..color = const Color(0xFF64707B).withValues(alpha: 0.3),
    );
    final pane = frame.deflate(9);
    canvas.drawRect(
      pane,
      Paint()..color = const Color(0xFF344455).withValues(alpha: 0.35),
    );
    final framePaint = Paint()
      ..color = const Color(0xFF7B6C61).withValues(alpha: 0.85)
      ..strokeWidth = 8;
    canvas.drawRect(
      frame,
      Paint()
        ..color = const Color(0xFF776A63).withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );
    canvas.drawLine(
      Offset(frame.center.dx, frame.top),
      Offset(frame.center.dx, frame.bottom),
      framePaint,
    );
    canvas.drawLine(
      Offset(frame.left, frame.top + frame.height * 0.43),
      Offset(frame.right, frame.top + frame.height * 0.43),
      framePaint,
    );

    final skyline = Paint()
      ..color = const Color(0xFF1C2635).withValues(alpha: 0.7);
    for (var i = 0; i < 15; i++) {
      final x = pane.left + i * pane.width / 15;
      final h = 38.0 + (i * 17 % 42);
      canvas.drawRect(
        Rect.fromLTWH(x, pane.bottom - h, pane.width / 18 + 2, h),
        skyline,
      );
    }
    final rain = Paint()
      ..color = const Color(0xFFC4D9E7).withValues(alpha: 0.3)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.clipRect(pane);
    for (var i = 0; i < 38; i++) {
      final x = pane.left + ((i * 73 + 19) % 101) / 101 * pane.width;
      final y = pane.top + ((i * 47 / 101 + progress) % 1) * pane.height;
      canvas.drawLine(Offset(x, y), Offset(x - 1, y + 11 + i % 8), rain);
    }
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.68, size.width, size.height * 0.1),
      Paint()..color = const Color(0xFF8B8073).withValues(alpha: 0.32),
    );
    _paintLamp(canvas, size);
  }

  void _paintLamp(Canvas canvas, Size size) {
    final x = size.width * 0.17;
    final y = size.height * 0.57;
    canvas.drawCircle(
      Offset(x, y),
      55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFE9A8).withValues(alpha: 0.24),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 55)),
    );
    final shade = Path()
      ..moveTo(x - 26, y)
      ..lineTo(x - 17, y - 43)
      ..lineTo(x + 17, y - 43)
      ..lineTo(x + 26, y)
      ..close();
    canvas.drawPath(shade, Paint()..color = const Color(0xFFD8B981));
    canvas.drawLine(
      Offset(x, y),
      Offset(x, size.height * 0.86),
      Paint()
        ..color = const Color(0xFFAE9881)
        ..strokeWidth = 5,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, size.height * 0.86),
        width: 64,
        height: 8,
      ),
      Paint()..color = const Color(0xFFB19B87),
    );
  }

  void _paintBeach(Canvas canvas, Size size) {
    final sun = Offset(size.width * 0.73, size.height * 0.28);
    canvas.drawCircle(
      sun,
      size.width * 0.12,
      Paint()..color = const Color(0xFFFFD294).withValues(alpha: 0.6),
    );
    final horizon = size.height * 0.59;
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, size.height * 0.18),
      Paint()..color = const Color(0xFF0A3548).withValues(alpha: 0.46),
    );
    for (var i = 0; i < 9; i++) {
      final y = horizon + 10 + i * 12;
      canvas.drawLine(
        Offset((i * 31) % 60, y),
        Offset(size.width - (i * 43) % 80, y),
        Paint()
          ..color = const Color(0xFFFFC69D).withValues(alpha: 0.1)
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintBar(Canvas canvas, Size size) {
    final shelfPaint = Paint()
      ..color = const Color(0xFF120F14).withValues(alpha: 0.62);
    for (var row = 0; row < 2; row++) {
      final y = size.height * (0.37 + row * 0.23);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 10), shelfPaint);
      for (var i = 0; i < 8; i++) {
        final x = size.width * (0.05 + i * 0.12);
        final height = 35.0 + (i * 13 % 35);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y - height, 17, height),
            const Radius.circular(3),
          ),
          Paint()
            ..color = Color.lerp(
              const Color(0xFF5E3A36),
              scene.accent,
              i / 12,
            )!.withValues(alpha: 0.56),
        );
      }
    }
    canvas.drawCircle(
      Offset(size.width * 0.67, size.height * 0.17),
      32,
      Paint()..color = scene.accent.withValues(alpha: 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.progress != progress;
}

class VirtualGlassCanvas extends StatelessWidget {
  const VirtualGlassCanvas({
    super.key,
    required this.drink,
    required this.glass,
    required this.iceCode,
    required this.remaining,
    required this.progress,
  });

  final VirtualDrink drink;
  final VirtualGlass glass;
  final String iceCode;
  final double remaining;
  final double progress;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GlassPainter(drink, glass, iceCode, remaining, progress),
    child: const SizedBox.expand(),
  );
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(
    this.drink,
    this.glass,
    this.iceCode,
    this.remaining,
    this.progress,
  );

  final VirtualDrink drink;
  final VirtualGlass glass;
  final String iceCode;
  final double remaining;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 250, size.height / 310);
    final shape = glass.renderConfig['renderer'] == 'glass-v1'
        ? glass.shape
        : 'highball';
    final bowl = _bowl(shape);
    final vessel = _vessel(shape);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(125, 292), width: 195, height: 20),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13),
    );
    canvas.drawPath(
      vessel,
      Paint()..color = Colors.white.withValues(alpha: 0.1),
    );

    if (remaining > 0) {
      final bounds = bowl.getBounds();
      final top =
          bounds.bottom - bounds.height * glass.maxFill * remaining.clamp(0, 1);
      canvas.save();
      canvas.clipPath(bowl);
      final fill = Rect.fromLTRB(
        bounds.left,
        top,
        bounds.right,
        bounds.bottom + 2,
      );
      canvas.drawRect(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              drink.liquidColor.withValues(alpha: drink.opacity * 0.82),
              drink.liquidColor.withValues(alpha: drink.opacity),
              Color.lerp(
                drink.liquidColor,
                Colors.black,
                0.18,
              )!.withValues(alpha: drink.opacity),
            ],
          ).createShader(fill),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(bounds.center.dx, top),
          width: bounds.width * 0.94,
          height: 16,
        ),
        Paint()
          ..color = Color.lerp(
            drink.liquidColor,
            Colors.white,
            0.28,
          )!.withValues(alpha: drink.opacity),
      );
      if (drink.bubbles) _paintBubbles(canvas, bounds, top);
      if (iceCode != 'none') _paintIce(canvas, bounds, top);
      if (drink.foam && remaining > 0.08) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(bounds.center.dx, top + 3),
            width: bounds.width * 0.88,
            height: 18,
          ),
          Paint()..color = drink.foamColor.withValues(alpha: 0.88),
        );
      }
      canvas.restore();
    }

    canvas.drawPath(
      vessel,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.68)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    final bowlBounds = bowl.getBounds();
    canvas.drawLine(
      Offset(bowlBounds.left + 11, bowlBounds.top + 22),
      Offset(bowlBounds.left + 17, bowlBounds.bottom - 22),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.26)
        ..strokeWidth = 3,
    );
    canvas.restore();
  }

  Path _bowl(String shape) {
    switch (shape) {
      case 'coupe':
        return Path()
          ..moveTo(25, 67)
          ..quadraticBezierTo(125, 58, 225, 67)
          ..quadraticBezierTo(220, 122, 125, 165)
          ..quadraticBezierTo(30, 122, 25, 67)
          ..close();
      case 'rocks':
        return Path()
          ..moveTo(43, 95)
          ..lineTo(207, 95)
          ..lineTo(190, 270)
          ..lineTo(60, 270)
          ..close();
      case 'beer_mug':
        return Path()
          ..moveTo(50, 54)
          ..lineTo(194, 54)
          ..lineTo(188, 273)
          ..lineTo(57, 273)
          ..close();
      default:
        return Path()
          ..moveTo(51, 34)
          ..lineTo(199, 34)
          ..lineTo(184, 275)
          ..lineTo(66, 275)
          ..close();
    }
  }

  Path _vessel(String shape) {
    final bowl = _bowl(shape);
    if (shape == 'coupe') {
      bowl.moveTo(125, 165);
      bowl.lineTo(125, 272);
      bowl.moveTo(72, 273);
      bowl.quadraticBezierTo(125, 260, 178, 273);
    } else if (shape == 'beer_mug') {
      bowl.moveTo(194, 80);
      bowl.quadraticBezierTo(245, 68, 225, 167);
      bowl.quadraticBezierTo(217, 186, 190, 185);
    }
    return bowl;
  }

  void _paintBubbles(Canvas canvas, Rect bounds, double top) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.28);
    for (var i = 0; i < 13; i++) {
      final x = bounds.left + bounds.width * (0.16 + (i * 29 % 71) / 100);
      final range = math.max(5.0, bounds.bottom - top - 12);
      final y = bounds.bottom - ((i * 31 + progress * 58) % range);
      if (y > top + 8) canvas.drawCircle(Offset(x, y), 1.6 + i % 3, paint);
    }
  }

  void _paintIce(Canvas canvas, Rect bounds, double top) {
    final count = iceCode == 'crushed'
        ? 6
        : iceCode == 'large'
        ? 1
        : 3;
    final width = iceCode == 'large'
        ? 38.0
        : iceCode == 'crushed'
        ? 13.0
        : 23.0;
    for (var i = 0; i < count; i++) {
      final x = bounds.left + bounds.width * (0.23 + (i * 23 % 52) / 100);
      final y = math.max(top + 14, bounds.bottom - 28.0 - (i % 3) * 26);
      final rect = Rect.fromCenter(
        center: Offset(x, y),
        width: width,
        height: width * 0.72,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassPainter oldDelegate) =>
      oldDelegate.drink != drink ||
      oldDelegate.glass != glass ||
      oldDelegate.iceCode != iceCode ||
      oldDelegate.remaining != remaining ||
      oldDelegate.progress != progress;
}
