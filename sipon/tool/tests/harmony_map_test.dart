import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/map/controllers/map_scene_controller.dart';
import 'package:sipon/features/map/controllers/mapkit_scene_controller.dart';
import 'package:sipon/features/map/models/map_viewport.dart';
import 'package:sipon/features/map/platform/map_engine.dart';
import 'package:sipon/features/map/platform/sipon_map_host.dart';
import 'package:sipon/features/map/platform/sipon_map_protocol.dart';

class _Host implements SiponMapHost {
  final calls = <MapEntry<String, Map<String, Object?>>>[];
  void Function(String, Object?)? handler;
  Object? routeResult = true;

  @override
  void onNativeCall(void Function(String, Object?) handler) {
    this.handler = handler;
  }

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls.add(MapEntry(method, args));
    if (method == SiponMapCommands.setup) {
      handler?.call(SiponMapEvents.onMapReady, null);
    }
    if (method == SiponMapCommands.drawRoute) return routeResult;
    if (method == SiponMapCommands.searchPlaces) {
      return [
        {
          'name': '测试地点',
          'address': '测试地址',
          'city': '上海',
          'lat': 31.2,
          'lng': 121.4,
        },
        {'name': '无效地点', 'lat': double.nan, 'lng': 121.4},
      ];
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('map routing and per-view channels remain isolated', () {
    expect(
      selectMapEngine(platform: TargetPlatform.iOS, isWeb: false),
      MapEngine.mapKit,
    );
    expect(
      selectMapEngine(platform: TargetPlatform.android, isWeb: false),
      MapEngine.tianditu,
    );
    expect(selectMapEngine(isWeb: true), MapEngine.unsupported);
    for (final platform in TargetPlatform.values.where(
      (value) => value.name == 'ohos',
    )) {
      expect(
        selectMapEngine(platform: platform, isWeb: false),
        MapEngine.petal,
      );
    }
    expect(siponChannelName(MapEngine.petal, 7), 'sipon/petal_7');
    expect(siponChannelName(MapEngine.petal, 8), 'sipon/petal_8');
    expect(siponChannelName(MapEngine.mapKit, 7), 'sipon/mapkit_7');
  });

  testWidgets(
    'Petal initializes the requested city and handles native events',
    (tester) async {
      final tapped = <String>[];
      final host = _Host();
      final scene = MapSceneController.create(
        engine: MapEngine.petal,
        onViewportSettled: (_) {},
        onVenueTapped: tapped.add,
        onBlankTapped: () {},
      );
      await tester.runAsync(() => scene.attach(host, city: '北京'));
      expect(scene.isAttached, isTrue);
      final setup = host.calls
          .firstWhere((call) => call.key == SiponMapCommands.setup)
          .value;
      final city = mapCenterForCity('北京');
      expect(setup['lng'], city.longitude);
      expect(setup['lat'], city.latitude);
      host.handler!(
        SiponMapEvents.onMapReady,
        null,
      ); // A duplicate ready must not throw.
      host.handler!(SiponMapEvents.onVenueTapped, {'venueId': 'venue-1'});
      expect(tapped, ['venue-1']);
      final places = await scene.searchPlaces('测试');
      expect(places.map((place) => place.name), ['测试地点']);
      const stops = [
        MapLatLng(longitude: 121.4, latitude: 31.2),
        MapLatLng(longitude: 121.5, latitude: 31.3),
      ];
      expect(await scene.planRoute(points: stops), isTrue);
      host.routeResult = false;
      expect(await scene.planRoute(points: stops), isFalse);
      scene.detach();
      expect(scene.isAttached, isFalse);
    },
  );

  testWidgets('iOS setup retains native city resolution', (tester) async {
    final scene = MapkitSceneController(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    final host = _Host();
    await tester.runAsync(() => scene.attach(host, city: '北京'));
    final setup = host.calls
        .firstWhere((call) => call.key == SiponMapCommands.setup)
        .value;
    expect(setup.containsKey('lat'), isFalse);
    expect(setup.containsKey('lng'), isFalse);
    scene.detach();
  });
}
