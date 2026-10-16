import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/map/controllers/map_scene_controller.dart';
import 'package:sipon/features/map/controllers/petal_android_scene_controller.dart';
import 'package:sipon/features/map/models/map_viewport.dart';
import 'package:sipon/features/map/platform/map_engine.dart';
import 'package:sipon/features/map/platform/sipon_map_host.dart';
import 'package:sipon/features/map/platform/sipon_map_protocol.dart';

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData(0);
}

class _Host implements SiponMapHost {
  void Function(String, Object?)? handler;
  final calls = <String>[];
  final route = Completer<Object?>();

  @override
  void onNativeCall(void Function(String, Object?) handler) =>
      this.handler = handler;

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls.add(method);
    if (method == SiponMapCommands.setup)
      handler?.call(SiponMapEvents.onMapReady, null);
    if (method == SiponMapCommands.planRoadRoute) return route.future;
    if (method == SiponMapCommands.setRouteGeometry) return true;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const points = [
    MapLatLng(longitude: 116.4, latitude: 39.9),
    MapLatLng(longitude: 116.5, latitude: 39.95),
  ];

  PetalAndroidSceneController scene() => PetalAndroidSceneController(
    onViewportSettled: (_) {},
    onVenueTapped: (_) {},
    onBlankTapped: () {},
    assetBundle: _Assets(),
  );

  test('Android creates its native Petal controller and isolated channel', () {
    final controller = MapSceneController.create(
      engine: MapEngine.petalAndroid,
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    expect(controller, isA<PetalAndroidSceneController>());
    expect(siponChannelName(MapEngine.petalAndroid, 12), 'sipon/petal_12');
  });

  test(
    'late route result after detach cannot draw into a disposed map',
    () async {
      final host = _Host();
      final controller = scene();
      await controller.attach(host, city: '北京');
      final pending = controller.planRoute(points: points);
      controller.detach();
      host.route.complete({
        'crs': 'GCJ02',
        'legs': [
          {
            'coordinates': [
              [116.4, 39.9],
              [116.5, 39.95],
            ],
          },
        ],
      });
      expect(await pending, isFalse);
      expect(host.calls, isNot(contains(SiponMapCommands.setRouteGeometry)));
    },
  );

  test('provider WGS84 result is rejected at shared GCJ02 boundary', () async {
    final host = _Host();
    final controller = scene();
    await controller.attach(host, city: '北京');
    host.route.complete({
      'crs': 'WGS84',
      'legs': [
        {
          'coordinates': [
            [116.4, 39.9],
            [116.5, 39.95],
          ],
        },
      ],
    });
    expect(await controller.planRoute(points: points), isFalse);
    expect(host.calls, isNot(contains(SiponMapCommands.setRouteGeometry)));
    expect(controller.routeErrorMessage, isNotNull);
    controller.detach();
  });
}
