import 'dart:math' as math;

/// Coordinate contract for Sipon API payloads and shared map data.
///
/// Device positions and the built-in city table remain WGS-84 at their source.
/// Convert them once on entry; never convert an API/MapKit/Petal business point
/// again. The regional bounds match Android's MapCoordinateAdapter.
abstract final class BusinessCoordinates {
  static const crs = 'GCJ02';
  static const _semiMajorAxis = 6378245.0;
  static const _eccentricitySquared = 0.006693421622965943;

  static ({double longitude, double latitude}) fromWgs84({
    required double longitude,
    required double latitude,
  }) {
    if (!longitude.isFinite ||
        !latitude.isFinite ||
        longitude.abs() > 180 ||
        latitude.abs() > 90) {
      throw ArgumentError('Invalid WGS-84 coordinate');
    }
    if (longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271) {
      return (longitude: longitude, latitude: latitude);
    }
    final x = longitude - 105;
    final y = latitude - 35;
    var dLat =
        -100 +
        2 * x +
        3 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    dLat +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    dLat +=
        (20 * math.sin(y * math.pi) + 40 * math.sin(y / 3 * math.pi)) * 2 / 3;
    dLat +=
        (160 * math.sin(y / 12 * math.pi) + 320 * math.sin(y * math.pi / 30)) *
        2 /
        3;
    var dLng =
        300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    dLng +=
        (20 * math.sin(6 * x * math.pi) + 20 * math.sin(2 * x * math.pi)) *
        2 /
        3;
    dLng +=
        (20 * math.sin(x * math.pi) + 40 * math.sin(x / 3 * math.pi)) * 2 / 3;
    dLng +=
        (150 * math.sin(x / 12 * math.pi) + 300 * math.sin(x / 30 * math.pi)) *
        2 /
        3;
    final radLat = latitude / 180 * math.pi;
    final sinLat = math.sin(radLat);
    final magic = 1 - _eccentricitySquared * sinLat * sinLat;
    final sqrtMagic = math.sqrt(magic);
    dLat =
        dLat *
        180 /
        ((_semiMajorAxis * (1 - _eccentricitySquared) / (magic * sqrtMagic)) *
            math.pi);
    dLng =
        dLng *
        180 /
        ((_semiMajorAxis / sqrtMagic * math.cos(radLat)) * math.pi);
    return (longitude: longitude + dLng, latitude: latitude + dLat);
  }
}
