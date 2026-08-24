import 'package:flutter/material.dart' hide Visibility;

/// 地图页的色板。原来是 `map_page.dart` 里的私有 `_MapDesign`，
/// 拆成多个组件文件后需要共享，提到这里。
class MapDesign {
  const MapDesign._();

  static const Color brand = Color(0xFF9A3D78);
  static const Color ink = Color(0xFF252229);
  static const Color muted = Color(0xFF9B939B);

  /// 状态提示里表示「出错了」的红。
  static const Color alert = Color(0xFFB91C1C);

  /// 标签、按钮用的品牌浅底。
  static const Color brandSurface = Color(0xFFFFEDF7);
  static const Color tagSurface = Color(0xFFFFE8F6);
  static const Color hairline = Color(0xFFF0E7EE);
}
