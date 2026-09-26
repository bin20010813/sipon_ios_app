import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/map/data/route_planner.dart';
import 'package:sipon/features/map/models/map_viewport.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';

class _FakeRouteApi extends SiponApiClient {
  _FakeRouteApi(this.response);

  final Object? response;
  String? path;
  Object? body;

  @override
  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    this.path = path;
    this.body = body;
    return response;
  }
}

void main() {
  const stops = [
    MapLatLng(longitude: 121.1, latitude: 31.1),
    MapLatLng(longitude: 121.2, latitude: 31.2),
    MapLatLng(longitude: 121.3, latitude: 31.3),
  ];

  test(
    'requests WGS-84 driving legs and preserves intermediate stop order',
    () async {
      final api = _FakeRouteApi({
        'crs': 'WGS84',
        'legs': [
          {
            'coordinates': [
              [121.1, 31.1],
              [121.15, 31.15],
              [121.2, 31.2],
            ],
          },
          {
            'coordinates': [
              [121.2, 31.2],
              [121.25, 31.25],
              [121.3, 31.3],
            ],
          },
        ],
      });
      final legs = await RoutePlanner(
        apiClient: api,
      ).plan(points: stops, requestId: 'map-1');

      expect(api.path, '/api/map/routes/plan');
      expect(api.body, {
        'requestId': 'map-1',
        'crs': 'WGS84',
        'mode': 'driving',
        'stops': [
          {'lng': 121.1, 'lat': 31.1},
          {'lng': 121.2, 'lat': 31.2},
          {'lng': 121.3, 'lat': 31.3},
        ],
      });
      expect(legs.length, 2);
      expect(
        legs.first.coordinates[1],
        const MapLatLng(longitude: 121.15, latitude: 31.15),
      );
    },
  );

  test('rejects missing legs, invalid coordinates and wrong CRS', () async {
    for (final response in [
      {'crs': 'WGS84', 'legs': []},
      {'crs': 'CGCS2000', 'legs': []},
      {
        'crs': 'WGS84',
        'legs': [
          {
            'coordinates': [
              [121.1, 31.1],
              [200, 31.2],
            ],
          },
          {
            'coordinates': [
              [121.2, 31.2],
              [121.3, 31.3],
            ],
          },
        ],
      },
    ]) {
      await expectLater(
        RoutePlanner(
          apiClient: _FakeRouteApi(response),
        ).plan(points: stops, requestId: 'map-2'),
        throwsFormatException,
      );
    }
  });
}
