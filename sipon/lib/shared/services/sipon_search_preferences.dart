import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 附近酒吧搜索的全局偏好。
///
/// 目前只承载 `radiusMeters`：偏好设置页的滑块写入这里，
/// 打卡页、路线规划页等所有调用 /api/bars/nearby 的入口统一读取，
/// 改动后通过 [ChangeNotifier] 广播，页面可即时刷新结果。
class SiponSearchPreferences extends ChangeNotifier {
  SiponSearchPreferences._();

  static final SiponSearchPreferences instance = SiponSearchPreferences._();

  static const String _radiusKey = 'sipon.search_radius_meters';

  /// 接口文档约定 radiusMeters 下限 1000，产品要求上限 3km。
  static const int minRadiusMeters = 1000;
  static const int maxRadiusMeters = 3000;
  static const int defaultRadiusMeters = maxRadiusMeters;

  /// 滑块步进（米）：1 / 1.5 / 2 / 2.5 / 3 km 共 5 档。
  static const int radiusStepMeters = 500;

  int _radiusMeters = defaultRadiusMeters;
  bool _loaded = false;

  int get radiusMeters => _radiusMeters;
  bool get loaded => _loaded;

  /// 启动时调用一次；重复调用直接返回。
  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _radiusMeters = _clamp(
      prefs.getInt(_radiusKey) ?? defaultRadiusMeters,
    );
    _loaded = true;
    notifyListeners();
  }

  Future<void> setRadiusMeters(int value) async {
    final clamped = _clamp(value);
    if (clamped == _radiusMeters) {
      return;
    }
    _radiusMeters = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_radiusKey, clamped);
  }

  static int _clamp(int value) =>
      value.clamp(minRadiusMeters, maxRadiusMeters);
}

/// 半径展示文案：不足 1km 显示米，否则按 0.1km 精度显示公里。
String siponFormatRadiusMeters(int meters) {
  if (meters < 1000) {
    return '$meters m';
  }
  final km = meters / 1000;
  final rounded = km.roundToDouble();
  return km == rounded ? '${rounded.toInt()} km' : '${km.toStringAsFixed(1)} km';
}
