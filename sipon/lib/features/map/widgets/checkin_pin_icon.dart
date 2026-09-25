import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// 打卡页地图浮标的保留分类 key。原生按 `category` 查图标缓存，这个 key
/// 不对应任何 PNG 资产，而是 attach 时用 [buildCheckInPinImage] 现画注册。
const String checkInPinCategory = 'checkinPin';

/// 图钉逻辑尺寸（pt）。与原生 annotation 视图普通态一致（22×28），
/// 底部中点对齐坐标，所以针尖落点必须压在底边中点上。
const Size checkInPinSize = Size(22, 28);

/// 打卡图钉画笔：红色小球 + 下面一根圆头针 + 落点阴影。
///
/// 与 `assets/map/checkin_pin.svg`（设计源，未打包）同一套图形参数；
/// 原生 MapKit 不能直接渲染 SVG，运行时用它在离屏画布上绘制成 PNG
/// 注册给原生图标缓存，也可以直接挂 `CustomPaint` 做 Flutter 侧预览。
class CheckInPinPainter extends CustomPainter {
  const CheckInPinPainter();

  static const Color pinRed = Color(0xFFE8453C);

  /// 设计稿坐标系（与 SVG viewBox 对应）。
  static const Size _designSize = Size(22, 28);
  static const Offset _ballCenter = Offset(11, 8.5);
  static const double _ballRadius = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(
      size.width / _designSize.width,
      size.height / _designSize.height,
    );
    canvas
      ..save()
      ..scale(scale);

    // 落点阴影。
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(11, 26.4), width: 9, height: 3),
      Paint()..color = const Color(0x2E000000),
    );
    // 针：上端藏进球底（球底 y=15.5），圆头收尾。
    canvas.drawLine(
      const Offset(11, 14.5),
      const Offset(11, 25.6),
      Paint()
        ..color = pinRed
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    // 球：红底 + 白描边，任何地图底色上都看得清。
    canvas
      ..drawCircle(_ballCenter, _ballRadius, Paint()..color = pinRed)
      ..drawCircle(
        _ballCenter,
        _ballRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = const Color(0xFFFFFFFF),
      )
      // 左上高光，让球有体积感。
      ..drawCircle(
        const Offset(8.6, 6.1),
        2.1,
        Paint()..color = const Color(0x8CFFFFFF),
      );

    canvas.restore();
  }

  @override
  bool shouldRepaint(CheckInPinPainter oldDelegate) => false;
}

/// 把图钉离屏绘制成 PNG 字节。原生按 scale=3 解码（见 SiponMapView 的
/// `UIImage(data:scale:3)`），所以默认按 3x 出图，清晰度和分类图标一致。
Future<Uint8List> buildCheckInPinImage({double pixelRatio = 3}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  const CheckInPinPainter().paint(canvas, checkInPinSize);

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (checkInPinSize.width * pixelRatio).round(),
    (checkInPinSize.height * pixelRatio).round(),
  );
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('打卡图钉 PNG 编码失败');
    }
    return Uint8List.sublistView(bytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
