import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/map/controllers/tianditu_scene_controller.dart';
import 'package:sipon/features/map/data/route_planner.dart';
import 'package:sipon/features/map/models/map_display_options.dart';
import 'package:sipon/features/map/models/map_viewport.dart';
import 'package:sipon/features/map/platform/sipon_map_host.dart';
import 'package:sipon/features/map/platform/sipon_map_protocol.dart';

class _Host implements SiponMapHost {
  void Function(String, Object?)? handler;
  final calls = <String>[];
  final arguments = <String, Map<String, Object?>>{};
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
    calls.add(method);
    arguments[method] = args;
    if (method == SiponMapCommands.setup) {
      scheduleMicrotask(() => handler?.call(SiponMapEvents.onMapReady, null));
    }
    if (method == SiponMapCommands.setRouteGeometry) return routeResult;
    return null;
  }
}

class _Planner extends RoutePlanner {
  _Planner(this.result);
  final List<RouteLeg> result;

  @override
  Future<List<RouteLeg>> plan({
    required List<MapLatLng> points,
    required String requestId,
  }) async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const points = [
    MapLatLng(longitude: 121.1, latitude: 31.1),
    MapLatLng(longitude: 121.2, latitude: 31.2),
  ];

  test(
    'dark map style reaches the Android view on attach and style change',
    () async {
      final host = _Host();
      final controller = TiandituSceneController(
        onViewportSettled: (_) {},
        onVenueTapped: (_) {},
        onBlankTapped: () {},
      );
      addTearDown(controller.detach);
      await controller.attach(host, city: '上海', style: MapBaseStyle.muted);
      expect(host.arguments[SiponMapCommands.setup]?['styleId'], 'muted');

      await controller.setStyle(MapBaseStyle.standard);
      await controller.setStyle(MapBaseStyle.muted);
      expect(host.arguments[SiponMapCommands.setStyle]?['styleId'], 'muted');
    },
  );

  test(
    'road route succeeds only after native geometry acknowledgement',
    () async {
      final host = _Host();
      final controller = TiandituSceneController(
        onViewportSettled: (_) {},
        onVenueTapped: (_) {},
        onBlankTapped: () {},
        routePlanner: _Planner([
          const RouteLeg([
            MapLatLng(longitude: 121.1, latitude: 31.1),
            MapLatLng(longitude: 121.15, latitude: 31.15),
            MapLatLng(longitude: 121.2, latitude: 31.2),
          ]),
        ]),
      );
      addTearDown(controller.detach);
      await controller.attach(host, city: '上海');
      expect(controller.isAttached, isTrue);
      expect(await controller.planRoute(points: points), isTrue);
      expect(host.calls, contains(SiponMapCommands.setRouteGeometry));

      host.routeResult = false;
      expect(await controller.planRoute(points: points), isFalse);
      expect(host.calls, contains(SiponMapCommands.clearRoute));
    },
  );

  test(
    'late native ready after detach cannot reattach a disposed scene',
    () async {
      final host = _Host();
      final controller = TiandituSceneController(
        onViewportSettled: (_) {},
        onVenueTapped: (_) {},
        onBlankTapped: () {},
      );
      final attaching = controller.attach(host, city: '上海');
      controller.detach();
      host.handler?.call(SiponMapEvents.onMapReady, null);
      await attaching;
      expect(controller.isAttached, isFalse);
      expect(host.calls, isNot(contains(SiponMapCommands.registerAssets)));
    },
  );
}
