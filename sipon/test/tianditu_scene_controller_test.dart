import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
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
  Object? plannedRoute = {
    'crs': 'CGCS2000',
    'legs': [
      {
        'coordinates': [
          [121.1, 31.1],
          [121.15, 31.15],
          [121.2, 31.2],
        ],
      },
    ],
  };

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
    if (method == SiponMapCommands.planRoadRoute) {
      if (plannedRoute is PlatformException) throw plannedRoute!;
      return plannedRoute;
    }
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
  test(
    'user centering uses native position and clears sheet padding',
    () async {
      final host = _Host();
      final controller = TiandituSceneController(
        onViewportSettled: (_) {},
        onVenueTapped: (_) {},
        onBlankTapped: () {},
      );
      addTearDown(controller.detach);
      await controller.attach(host, city: '上海');
      await controller.applyStage(
        cameraBottomPadding: 240,
        ornamentBottomMargin: 240,
      );
      await controller.centerOnUser(longitude: 121.1, latitude: 31.1);
      final camera = host.arguments[SiponMapCommands.centerOnUser]!;
      expect(camera['lng'], 121.1);
      expect(camera['lat'], 31.1);
      expect(camera['bottomPadding'], 0);
    },
  );
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

  test('default Android route uses Tianditu driving service', () async {
    final host = _Host();
    const viaPoints = [
      MapLatLng(longitude: 121.1, latitude: 31.1),
      MapLatLng(longitude: 121.15, latitude: 31.15),
      MapLatLng(longitude: 121.18, latitude: 31.18),
      MapLatLng(longitude: 121.2, latitude: 31.2),
    ];
    host.plannedRoute = {
      'crs': 'CGCS2000',
      'legs': [
        {
          'coordinates': [
            [121.1, 31.1],
            [121.15, 31.15],
            [121.18, 31.18],
            [121.2, 31.2],
          ],
        },
      ],
    };
    final controller = TiandituSceneController(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    addTearDown(controller.detach);
    await controller.attach(host, city: '上海');

    expect(await controller.planRoute(points: viaPoints), isTrue);
    expect(host.arguments[SiponMapCommands.planRoadRoute], {
      'points': [
        {'lat': 31.1, 'lng': 121.1},
        {'lat': 31.15, 'lng': 121.15},
        {'lat': 31.18, 'lng': 121.18},
        {'lat': 31.2, 'lng': 121.2},
      ],
    });
    expect(host.calls, contains(SiponMapCommands.setRouteGeometry));
    expect(
      (host.arguments[SiponMapCommands.setRouteGeometry]!['legs'] as List),
      hasLength(1),
    );

    host.plannedRoute = {'crs': 'CGCS2000', 'legs': []};
    expect(await controller.planRoute(points: viaPoints), isFalse);
    expect(host.calls, contains(SiponMapCommands.clearRoute));
  });

  test('route preview fits every selected stop in order', () async {
    final host = _Host();
    final controller = TiandituSceneController(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    addTearDown(controller.detach);
    await controller.attach(host, city: '上海');

    await controller.fitRouteStops([
      ...points,
      const MapLatLng(longitude: 121.3, latitude: 31.3),
    ]);
    expect(host.arguments[SiponMapCommands.fitRouteStops], {
      'points': [
        {'lat': 31.1, 'lng': 121.1},
        {'lat': 31.2, 'lng': 121.2},
        {'lat': 31.3, 'lng': 121.3},
      ],
    });
  });

  test(
    'route key failures are explained instead of reported as bad legs',
    () async {
      final host = _Host();
      final controller = TiandituSceneController(
        onViewportSettled: (_) {},
        onVenueTapped: (_) {},
        onBlankTapped: () {},
      );
      addTearDown(controller.detach);
      await controller.attach(host, city: '上海');

      host.plannedRoute = PlatformException(
        code: 'route_service',
        message: 'TDT_ROUTE_KEY is missing',
      );
      expect(await controller.planRoute(points: points), isFalse);
      expect(controller.routeErrorMessage, contains('TDT_ROUTE_KEY'));

      host.plannedRoute = PlatformException(
        code: 'route_service',
        message: 'Tianditu driving HTTP 403: 301012: 权限类型错误',
      );
      expect(await controller.planRoute(points: points), isFalse);
      expect(controller.routeErrorMessage, contains('权限类型错误'));

      host.plannedRoute = PlatformException(
        code: 'route_service',
        message: 'Tianditu driving HTTP 403: 301018: 不支持的key类型',
      );
      expect(await controller.planRoute(points: points), isFalse);
      expect(controller.routeErrorMessage, contains('301018'));
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
