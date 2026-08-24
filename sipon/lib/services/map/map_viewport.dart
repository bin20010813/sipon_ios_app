import 'dart:math' as math;

/// 一个经纬度点。纯 Dart，避免把 `mapbox_maps_flutter` 的 `Position` 渗到数据层。
class MapLatLng {
  const MapLatLng({required this.longitude, required this.latitude});

  final double longitude;
  final double latitude;

  @override
  bool operator ==(Object other) =>
      other is MapLatLng &&
      other.longitude == longitude &&
      other.latitude == latitude;

  @override
  int get hashCode => Object.hash(longitude, latitude);

  @override
  String toString() =>
      'MapLatLng(${longitude.toStringAsFixed(4)}, ${latitude.toStringAsFixed(4)})';
}

/// 经纬度矩形。不处理跨 180° 反日线的情况——业务只覆盖中国境内。
class MapBoundsBox {
  const MapBoundsBox({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  /// 相机还没就绪时 Mapbox 会给出无穷大范围，这时退回整个中国。
  const MapBoundsBox.china() : west = 73, south = 18, east = 135, north = 54;

  final double west;
  final double south;
  final double east;
  final double north;

  double get spanLongitude => east - west;
  double get spanLatitude => north - south;

  MapLatLng get center => MapLatLng(
    longitude: west + spanLongitude / 2,
    latitude: south + spanLatitude / 2,
  );

  bool get isValid =>
      west.isFinite &&
      south.isFinite &&
      east.isFinite &&
      north.isFinite &&
      spanLongitude > 0 &&
      spanLatitude > 0;

  bool containsPoint(double longitude, double latitude) =>
      longitude >= west &&
      longitude <= east &&
      latitude >= south &&
      latitude <= north;

  bool contains(MapBoundsBox other) =>
      other.west >= west &&
      other.east <= east &&
      other.south >= south &&
      other.north <= north;

  /// 按比例外扩。取数时多拿一圈，用户小幅平移就不会立刻贴边重新请求。
  MapBoundsBox inflated(double ratio) {
    final padLongitude = spanLongitude * ratio;
    final padLatitude = spanLatitude * ratio;

    return MapBoundsBox(
      west: west - padLongitude,
      south: south - padLatitude,
      east: east + padLongitude,
      north: north + padLatitude,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapBoundsBox &&
      other.west == west &&
      other.south == south &&
      other.east == east &&
      other.north == north;

  @override
  int get hashCode => Object.hash(west, south, east, north);
}

/// 相机当前看到的东西：范围 + 缩放。
///
/// 取代原来「每次 idle 都全量重拉 + 用 `_skipNextIdleReload` 挡掉自己那次
/// flyTo」的做法：是否重新取数由 [differsMateriallyFrom] 这个纯函数说了算，
/// 于是程序化移动和用户手势走同一条判定，不需要任何一次性标志位。
class MapViewport {
  const MapViewport({required this.bounds, required this.zoom});

  /// 跨过这个缩放差就重新取数：marker 抽样上限是分档的，跨档了得重算。
  static const double zoomEpsilon = 0.35;

  /// 取数时把范围外扩这个比例，作为「已加载范围」记下来。
  static const double prefetchRatio = 0.2;

  final MapBoundsBox bounds;
  final double zoom;

  MapLatLng get center => bounds.center;

  /// 实际请求用的范围（比屏幕可见范围大一圈）。
  MapBoundsBox get fetchBounds => bounds.inflated(prefetchRatio);

  /// 与上一次「已取数」的视野比较，判断这次相机停下值不值得重新请求。
  ///
  /// - 缩放跨档 → 重拉（marker 数量上限变了）；
  /// - 视野已经不被上次取数范围覆盖（用户平移出去了）→ 重拉；
  /// - 其余情况（聚焦某家酒吧、面板改了 padding 导致可视区变小、原地小幅平移）
  ///   都落在已加载范围内 → 不重拉。
  bool differsMateriallyFrom(MapViewport previous) {
    if (!bounds.isValid || !previous.bounds.isValid) {
      return true;
    }
    if ((zoom - previous.zoom).abs() >= zoomEpsilon) {
      return true;
    }

    return !previous.fetchBounds.contains(bounds);
  }
}

/// 支持的城市中心。与 [SiponCityController] 里的定位表保持一致。
const Map<String, MapLatLng> mapCityCenters = {
  '上海': MapLatLng(longitude: 121.4712, latitude: 31.2227),
  '北京': MapLatLng(longitude: 116.4074, latitude: 39.9042),
  '深圳': MapLatLng(longitude: 114.0579, latitude: 22.5431),
  '广州': MapLatLng(longitude: 113.2644, latitude: 23.1291),
  '成都': MapLatLng(longitude: 104.0668, latitude: 30.5728),
  '杭州': MapLatLng(longitude: 120.1551, latitude: 30.2741),
};

const MapLatLng mapFallbackCityCenter = MapLatLng(
  longitude: 121.4712,
  latitude: 31.2227,
);

MapLatLng mapCenterForCity(String city) =>
    mapCityCenters[city] ?? mapFallbackCityCenter;

/// 两点球面距离（米）。用来给 mock 数据算「约2.0km」这种距离文案。
double mapDistanceInMeters(MapLatLng from, MapLatLng to) {
  const earthRadius = 6371000.0;
  final deltaLatitude = _toRadians(to.latitude - from.latitude);
  final deltaLongitude = _toRadians(to.longitude - from.longitude);
  final a =
      math.sin(deltaLatitude / 2) * math.sin(deltaLatitude / 2) +
      math.cos(_toRadians(from.latitude)) *
          math.cos(_toRadians(to.latitude)) *
          math.sin(deltaLongitude / 2) *
          math.sin(deltaLongitude / 2);

  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

String mapFormatDistance(double? meters) {
  if (meters == null || !meters.isFinite) {
    return '距离待计算';
  }
  if (meters >= 1000) {
    return '约${(meters / 1000).toStringAsFixed(1)}km';
  }

  return '约${meters.round()}m';
}

double _toRadians(double degrees) => degrees * math.pi / 180;
