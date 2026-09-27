import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';

class _LocationPlatform extends GeolocatorPlatform {
  Position? cached;
  int currentRequests = 0;
  LocationPermission permission = LocationPermission.whileInUse;
  bool enabled = true;
  LocationSettings? settings;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => cached;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    currentRequests++;
    settings = locationSettings;
    return position();
  }
}

Position position({Duration age = Duration.zero, double accuracy = 20}) =>
    Position(
      longitude: 113.8,
      latitude: 34.8,
      timestamp: DateTime.now().subtract(age),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  late _LocationPlatform platform;
  late SiponCityController controller;
  final original = GeolocatorPlatform.instance;

  setUp(() {
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
    controller = SiponCityController();
  });
  tearDown(() {
    controller.dispose();
    GeolocatorPlatform.instance = original;
  });

  test('recent accurate device location avoids another GPS request', () async {
    platform.cached = position(age: const Duration(seconds: 30));
    final result = await controller.locateCurrentCity(
      purpose: SiponLocationPurpose.checkIn,
    );
    expect(result.position, const SiponLocationPoint(113.8, 34.8));
    expect(platform.currentRequests, 0);
  });

  for (final entry in <String, Position?>{
    'missing': null,
    'stale': position(age: const Duration(minutes: 3)),
    'inaccurate': position(accuracy: 500),
    'unknown accuracy': position(accuracy: 0),
    'future timestamp': position(age: const Duration(minutes: -1)),
  }.entries) {
    test(
      '${entry.key} cache requests current location with bounded wait',
      () async {
        platform.cached = entry.value;
        final result = await controller.locateCurrentCity(
          purpose: SiponLocationPurpose.checkIn,
        );
        expect(result.position, isNotNull);
        expect(platform.currentRequests, 1);
        expect(platform.settings!.timeLimit, const Duration(seconds: 5));
      },
    );
  }

  test('cached location does not bypass revoked permission', () async {
    platform.cached = position();
    platform.permission = LocationPermission.deniedForever;
    final result = await controller.locateCurrentCity(
      purpose: SiponLocationPurpose.checkIn,
    );
    expect(result.status, SiponLocateStatus.permissionDeniedForever);
    expect(result.position, isNull);
    expect(platform.currentRequests, 0);
  });
}
