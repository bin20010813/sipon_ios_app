import 'dart:math' as math;
import 'dart:ui';

/// 按单条记录总金额（元）分档。
/// 非法金额使用中号；拥挤时由贴纸池统一等比例缩小。
double stickerSizeForAmount(double amount) {
  if (!amount.isFinite || amount < 0) return 44;
  if (amount < 50) return 36;
  if (amount < 100) return 44;
  return 52;
}

/// 贴纸池物理引擎。
///
/// 负责贴纸的位置、速度、圆形碰撞、边界限制与静止休眠：
/// - 每个贴纸对应一个 [StickerBody]，受重力、空气阻尼、池壁与池底约束；
/// - 连续多帧速度与角速度都低于阈值后进入 [sleeping]，由调用方停止逐帧刷新；
/// - 重力方向改变或外部扰动时调用 [wake] 重新唤醒。
class StickerPhysics {
  StickerPhysics({
    this.gravity = const Offset(0, 550),
    this.damping = 0.86,
    this.wallRestitution = 0.34,
    this.floorRestitution = 0.26,
    this.sleepThresholdFrames = 30,
  });

  /// 当前重力（像素/秒²，屏幕坐标：y 向下为正）。
  Offset gravity;

  /// 每帧速度衰减系数（0~1），模拟空气阻力。
  final double damping;

  /// 池壁弹性系数。
  final double wallRestitution;

  /// 池底弹性系数。
  final double floorRestitution;

  /// 连续多少帧接近静止后进入休眠。
  final int sleepThresholdFrames;

  /// 所有贴纸的物理状态。
  final List<StickerBody> bodies = [];

  bool _sleeping = false;
  int _sleepFrames = 0;

  /// 是否所有贴纸都已静止休眠。
  bool get sleeping => _sleeping;

  /// 用新的贴纸列表整体替换，并唤醒物理引擎。
  void reset(Iterable<StickerBody> next) {
    bodies
      ..clear()
      ..addAll(next);
    _sleeping = false;
    _sleepFrames = 0;
  }

  /// 强制唤醒，退出休眠。
  void wake() {
    _sleeping = false;
    _sleepFrames = 0;
  }

  /// 推进一帧物理模拟。[dt] 单位为秒；[bounds] 为贴纸池可用区域。
  void step(double dt, Size bounds) {
    if (bodies.isEmpty) {
      _sleeping = true;
      return;
    }

    final clamped = dt.clamp(0.0, 1.0 / 20.0);
    final drag = math.pow(damping, clamped * 60).toDouble();

    for (final body in bodies) {
      body.velocity += gravity * clamped;
      body.velocity *= drag;
      body.position += body.velocity * clamped;
      body.angle += body.angularVelocity * clamped;
    }

    _clampToBounds(bounds);
    _resolvePairCollisions();
    _updateSleep();
  }

  void _clampToBounds(Size bounds) {
    for (final body in bodies) {
      final half = body.size / 2;
      final minX = half;
      final maxX = math.max(half, bounds.width - half);
      final minY = half;
      final maxY = math.max(half, bounds.height - half);

      if (body.position.dx < minX) {
        body.position = Offset(minX, body.position.dy);
        body.velocity = Offset(
          -body.velocity.dx * wallRestitution,
          body.velocity.dy,
        );
      } else if (body.position.dx > maxX) {
        body.position = Offset(maxX, body.position.dy);
        body.velocity = Offset(
          -body.velocity.dx * wallRestitution,
          body.velocity.dy,
        );
      }

      if (body.position.dy < minY) {
        body.position = Offset(body.position.dx, minY);
        body.velocity = Offset(
          body.velocity.dx,
          -body.velocity.dy * wallRestitution,
        );
      } else if (body.position.dy > maxY) {
        body.position = Offset(body.position.dx, maxY);
        body.velocity = Offset(
          body.velocity.dx * 0.94,
          -body.velocity.dy * floorRestitution,
        );
        if (body.velocity.dy.abs() < 30) {
          body.velocity = Offset(body.velocity.dx, 0);
        }
      }
    }
  }

  void _resolvePairCollisions() {
    for (var i = 0; i < bodies.length; i++) {
      for (var j = i + 1; j < bodies.length; j++) {
        _resolveCollision(bodies[i], bodies[j]);
      }
    }
  }

  void _resolveCollision(StickerBody a, StickerBody b) {
    final minDist = (a.size + b.size) / 2;
    final dx = b.position.dx - a.position.dx;
    final dy = b.position.dy - a.position.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist >= minDist || dist <= 0.001) {
      return;
    }

    final nx = dx / dist;
    final ny = dy / dist;

    // 位置分离，消除重叠。
    final overlap = minDist - dist;
    a.position = Offset(
      a.position.dx - nx * overlap / 2,
      a.position.dy - ny * overlap / 2,
    );
    b.position = Offset(
      b.position.dx + nx * overlap / 2,
      b.position.dy + ny * overlap / 2,
    );

    // 等质量法向冲量，带恢复系数。
    final relNormal =
        (b.velocity.dx - a.velocity.dx) * nx +
        (b.velocity.dy - a.velocity.dy) * ny;
    if (relNormal > 0) {
      return;
    }

    const restitution = 0.5;
    final impulse = -(1 + restitution) * relNormal / 2;
    a.velocity = Offset(
      a.velocity.dx - impulse * nx,
      a.velocity.dy - impulse * ny,
    );
    b.velocity = Offset(
      b.velocity.dx + impulse * nx,
      b.velocity.dy + impulse * ny,
    );
  }

  void _updateSleep() {
    var moving = false;
    for (final body in bodies) {
      if (body.velocity.distanceSquared > 0.5 ||
          body.angularVelocity.abs() > 0.02) {
        moving = true;
        break;
      }
    }

    if (moving) {
      _sleepFrames = 0;
      _sleeping = false;
      return;
    }

    _sleepFrames++;
    if (_sleepFrames >= sleepThresholdFrames) {
      _sleeping = true;
      for (final body in bodies) {
        body.velocity = Offset.zero;
        body.angularVelocity = 0;
      }
    }
  }
}

/// 单个贴纸的物理状态。
class StickerBody {
  StickerBody({
    required this.position,
    required this.velocity,
    required this.size,
    this.angle = 0,
    this.angularVelocity = 0,
  });

  /// 圆心位置（贴纸池坐标系，原点在池子左上角）。
  Offset position;

  /// 速度（像素/秒）。
  Offset velocity;

  /// 贴纸直径（像素）。
  double size;

  /// 旋转角（弧度）。
  double angle;

  /// 角速度（弧度/秒）。
  double angularVelocity;
}