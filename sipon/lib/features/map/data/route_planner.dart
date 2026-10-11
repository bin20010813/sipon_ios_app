import '../../../shared/services/sipon_api_client.dart';
import '../../../shared/services/map/business_coordinates.dart';
import '../models/map_viewport.dart';

/// A road leg normalized to GCJ-02 business coordinates.
class RouteLeg {
  const RouteLeg(this.coordinates);

  final List<MapLatLng> coordinates;
}

/// Calls the proposed Sipon route proxy. Supplier credentials stay on the server.
/// The proxy must return one ordered road leg for each adjacent pair of stops.
class RoutePlanner {
  RoutePlanner({SiponApiClient? apiClient})
    : _apiClient = apiClient ?? SiponApiClient();

  final SiponApiClient _apiClient;

  Future<List<RouteLeg>> plan({
    required List<MapLatLng> points,
    required String requestId,
  }) async {
    if (points.length < 2 || points.any((point) => !_valid(point))) {
      throw const FormatException(
        'Route stops must contain valid GCJ-02 business coordinates',
      );
    }
    if (requestId.trim().isEmpty) {
      throw const FormatException('Route requestId is required');
    }

    final response = await _apiClient.postJson(
      '/api/map/routes/plan',
      body: {
        'requestId': requestId,
        'crs': BusinessCoordinates.crs,
        'mode': 'driving',
        'stops': [
          for (final point in points)
            {'lng': point.longitude, 'lat': point.latitude},
        ],
      },
    );

    if (response is! Map || response['crs'] != BusinessCoordinates.crs) {
      throw const FormatException('Route proxy did not return GCJ-02');
    }
    return parseLegs(response['legs'], expectedLegs: points.length - 1);
  }

  /// Validates the native Tianditu response before it reaches the map layer.
  static List<RouteLeg> parseLegs(
    Object? rawLegs, {
    required int expectedLegs,
  }) {
    if (rawLegs is! List || rawLegs.length != expectedLegs) {
      throw const FormatException('Route service returned incomplete legs');
    }

    return [for (final rawLeg in rawLegs) _parseLeg(rawLeg)];
  }

  static RouteLeg _parseLeg(Object? rawLeg) {
    if (rawLeg is! Map || rawLeg['coordinates'] is! List) {
      throw const FormatException('Invalid route leg');
    }
    final coordinates = <MapLatLng>[];
    for (final rawPoint in rawLeg['coordinates'] as List) {
      if (rawPoint is! List ||
          rawPoint.length != 2 ||
          rawPoint[0] is! num ||
          rawPoint[1] is! num) {
        throw const FormatException('Invalid route coordinate');
      }
      final point = MapLatLng(
        longitude: (rawPoint[0] as num).toDouble(),
        latitude: (rawPoint[1] as num).toDouble(),
      );
      if (!_valid(point)) {
        throw const FormatException(
          'Route coordinate outside longitude/latitude range',
        );
      }
      coordinates.add(point);
    }
    if (coordinates.length < 2) {
      throw const FormatException('Route leg has no road geometry');
    }
    return RouteLeg(List.unmodifiable(coordinates));
  }

  static bool _valid(MapLatLng point) =>
      point.longitude.isFinite &&
      point.latitude.isFinite &&
      point.longitude.abs() <= 180 &&
      point.latitude.abs() <= 90 &&
      (point.longitude != 0 || point.latitude != 0);
}
