import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/map/data/route_planner.dart';
import 'package:sipon/features/map/models/map_viewport.dart';
import 'package:sipon/features/map/platform/external_map_launcher.dart';
import 'package:sipon/shared/services/map/business_coordinates.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/services/sipon_region_data.dart';

class _RouteApi extends SiponApiClient {
  Object? sent;
  String responseCrs = BusinessCoordinates.crs;

  @override
  Future<dynamic> postJson(
    String path, {
    Object? body,
    Map<String, Object?> queryParameters = const {},
  }) async {
    sent = body;
    return {
      'crs': responseCrs,
      'legs': [
        {
          'coordinates': [
            [116.403372494, 39.917930749],
            [116.41, 39.92],
          ],
        },
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final cacheAgeSeconds in [5, 90]) {
    test(
      'map button cache age $cacheAgeSeconds uses recent fixes or direct Android location',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('flutter.baseflow.com/geolocator');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        var freshCalls = 0;
        Map<String, Object> fix(int age) => {
          'longitude': 116.397128,
          'latitude': 39.916527,
          'timestamp': DateTime.now()
              .subtract(Duration(seconds: age))
              .millisecondsSinceEpoch,
          'accuracy': 5.0,
          'altitude': 0.0,
          'heading': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
        };
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return true;
            case 'checkPermission':
              return 3;
            case 'getLastKnownPosition':
              return fix(cacheAgeSeconds);
            case 'getCurrentPosition':
              freshCalls++;
              expect((call.arguments as Map)['forceLocationManager'], isTrue);
              return fix(0);
            default:
              throw StateError('Unexpected call ${call.method}');
          }
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final controller = SiponCityController();
        addTearDown(controller.dispose);
        final result = await controller.locateCurrentCity(
          purpose: SiponLocationPurpose.mapCenter,
        );
        expect(result.position!.longitude, closeTo(116.403372494, 1e-8));
        expect(freshCalls, cacheAgeSeconds <= 30 ? 0 : 1);
        await controller.locateCurrentCity(
          purpose: SiponLocationPurpose.mapCenter,
        );
        expect(freshCalls, cacheAgeSeconds <= 30 ? 0 : 1);
      },
    );
  }

  test('GPS enters GCJ-02 using a fixed Beijing reference', () {
    final point = BusinessCoordinates.fromWgs84(
      longitude: 116.397128,
      latitude: 39.916527,
    );
    expect(point.longitude, closeTo(116.403372494, 1e-8));
    expect(point.latitude, closeTo(39.917930749, 1e-8));
  });

  test(
    'outside-region positions pass through and invalid input is rejected',
    () {
      expect(
        BusinessCoordinates.fromWgs84(longitude: -0.1276, latitude: 51.5072),
        (longitude: -0.1276, latitude: 51.5072),
      );
      for (final longitude in [double.nan, double.infinity, 181.0]) {
        expect(
          () =>
              BusinessCoordinates.fromWgs84(longitude: longitude, latitude: 31),
          throwsArgumentError,
        );
      }
    },
  );

  test('city query and non-featured map fallback convert the WGS-84 table', () {
    final entry = siponFindCity('南京')!;
    final expected = BusinessCoordinates.fromWgs84(
      longitude: entry.longitude,
      latitude: entry.latitude,
    );
    final controller = SiponCityController(initialCity: '南京');
    addTearDown(controller.dispose);
    expect(controller.queryAnchor!.longitude, expected.longitude);
    expect(controller.queryAnchor!.latitude, expected.latitude);
    expect(mapCenterForCity('南京').longitude, expected.longitude);
    expect(mapCenterForCity('南京').latitude, expected.latitude);
  });

  for (final platform in TargetPlatform.values.where(
    (value) =>
        value == TargetPlatform.iOS ||
        value == TargetPlatform.android ||
        value.name == 'ohos',
  )) {
    test(
      '${platform.name} fresh and cached GPS are converted exactly once',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('flutter.baseflow.com/geolocator');
        var freshCalls = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'isLocationServiceEnabled':
              return true;
            case 'checkPermission':
              return 3;
            case 'getCurrentPosition':
              freshCalls++;
              return {
                'longitude': 116.397128,
                'latitude': 39.916527,
                'timestamp': DateTime.now().millisecondsSinceEpoch,
                'accuracy': 5.0,
                'altitude': 0.0,
                'heading': 0.0,
                'speed': 0.0,
                'speed_accuracy': 0.0,
              };
            default:
              throw StateError('Unexpected location call ${call.method}');
          }
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        final controller = SiponCityController();
        addTearDown(controller.dispose);
        final first = await controller.locateCurrentCity();
        final cached = await controller.locateCurrentCity(
          purpose: SiponLocationPurpose.checkIn,
        );
        expect(first.status, SiponLocateStatus.success);
        expect(first.position!.longitude, closeTo(116.403372494, 1e-8));
        expect(first.position!.latitude, closeTo(39.917930749, 1e-8));
        expect(cached.position, first.position);
        expect(freshCalls, 1);
      },
    );
  }

  test(
    'route proxy preserves GCJ-02 points and rejects a different datum',
    () async {
      final api = _RouteApi();
      final planner = RoutePlanner(apiClient: api);
      const points = [
        MapLatLng(longitude: 116.403372494, latitude: 39.917930749),
        MapLatLng(longitude: 116.41, latitude: 39.92),
      ];
      final legs = await planner.plan(points: points, requestId: 'test-route');
      expect((api.sent as Map)['crs'], 'GCJ02');
      expect((api.sent as Map)['stops'], [
        {'lng': points.first.longitude, 'lat': points.first.latitude},
        {'lng': points.last.longitude, 'lat': points.last.latitude},
      ]);
      expect(legs.single.coordinates, points);
      for (final crs in ['WGS84', 'CGCS2000']) {
        api.responseCrs = crs;
        await expectLater(
          planner.plan(points: points, requestId: 'bad-datum'),
          throwsFormatException,
        );
      }
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test(
      '${platform.name} navigation declares GCJ-02 without altering destination',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        final launched = <Uri>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'canLaunch') return true;
          if (call.method == 'launch') {
            launched.add(Uri.parse((call.arguments as Map)['url'] as String));
            return true;
          }
          throw StateError('Unexpected URL call ${call.method}');
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        for (final app in [ExternalMapApp.amap, ExternalMapApp.baidu]) {
          final result = await ExternalMapLauncher.openNavigation(
            app: app,
            name: '测试 酒馆',
            longitude: 116.403372494,
            latitude: 39.917930749,
          );
          expect(result.opened, isTrue);
        }
        expect(launched[0].queryParameters['dev'], '0');
        expect(launched[0].queryParameters['dlon'], '116.40337249');
        expect(launched[0].queryParameters['dlat'], '39.91793075');
        expect(launched[1].queryParameters['coord_type'], 'gcj02');
        expect(
          launched[1].queryParameters['destination'],
          contains('39.91793075,116.40337249'),
        );
      },
    );
  }
}
