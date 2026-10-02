import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/features/routes/pages/route_planning_page.dart';
import 'package:sipon/features/map/platform/sipon_map_host.dart';
import 'package:sipon/features/map/platform/sipon_map_protocol.dart';
import 'package:sipon/features/map/widgets/sipon_map_widget.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_config.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';

class _LocatedCity extends SiponCityController {
  _LocatedCity() : super(initialCity: '郑州', initialProvince: '河南省');

  Future<SiponLocateResult> Function() locate = () async =>
      const SiponLocateResult(
        status: SiponLocateStatus.success,
        position: SiponLocationPoint(113.8, 34.8),
      );

  @override
  Future<SiponLocateResult> locateCurrentCity({
    SiponLocationPurpose purpose = SiponLocationPurpose.citySuggestion,
  }) => locate();
}

class _Host implements SiponMapHost {
  late void Function(String, Object?) handler;
  final calls = <String, Map<String, Object?>>{};

  @override
  void onNativeCall(void Function(String, Object?) handler) {
    this.handler = handler;
  }

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls[method] = args;
    if (method == SiponMapCommands.setup) {
      handler(SiponMapEvents.onMapReady, null);
    }
    return null;
  }
}

/// 本分支在 Android 上走天地图引擎，平台视图在测试环境无法创建；
/// 这些用例验证的是业务定位/相机逻辑，固定为 MapKit 引擎路径。
void testOnIos(String description, Future<void> Function(WidgetTester) callback) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') return Completer<Object?>().future;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> openPage(WidgetTester tester, _LocatedCity city) async {
    final api = SiponApiService(
      apiClient: SiponApiClient(
        config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      ),
    );
    await tester.pumpWidget(
      SiponCityScope(
        controller: city,
        child: MaterialApp(home: RoutePlanningPage(apiService: api)),
      ),
    );
    await tester.pump();
  }

  testOnIos('路线预览首帧等待定位，并以个人点为中心', (tester) async {
    final pending = Completer<SiponLocateResult>();
    final city = _LocatedCity()..locate = () => pending.future;
    addTearDown(city.dispose);
    await openPage(tester, city);

    expect(find.text('正在获取当前位置…'), findsOneWidget);
    expect(find.byType(SiponMapWidget), findsNothing);

    pending.complete(
      const SiponLocateResult(
        status: SiponLocateStatus.success,
        position: SiponLocationPoint(113.8, 34.8),
      ),
    );
    await tester.pump();
    final map = tester.widget<SiponMapWidget>(find.byType(SiponMapWidget));
    final host = _Host();
    await tester.runAsync(() async {
      await (map.onHostReady as Future<void> Function(SiponMapHost))(host);
    });
    expect(host.calls[SiponMapCommands.setup]!['lng'], 113.8);
    expect(host.calls[SiponMapCommands.setup]!['lat'], 34.8);
    expect(host.calls[SiponMapCommands.centerOnUser]!['lng'], 113.8);
    expect(host.calls[SiponMapCommands.centerOnUser]!['lat'], 34.8);

    await city.selectCity('北京');
    await tester.pump();
    expect(host.calls[SiponMapCommands.flyToCity], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testOnIos('定位失败时预览仍可退回城市地图', (tester) async {
    final city = _LocatedCity()
      ..locate = () async =>
          const SiponLocateResult(status: SiponLocateStatus.permissionDenied);
    addTearDown(city.dispose);
    await openPage(tester, city);

    final map = tester.widget<SiponMapWidget>(find.byType(SiponMapWidget));
    final host = _Host();
    await tester.runAsync(() async {
      await (map.onHostReady as Future<void> Function(SiponMapHost))(host);
    });
    expect(host.calls[SiponMapCommands.setup]!['city'], '郑州');
    expect(host.calls[SiponMapCommands.setup]!.containsKey('lng'), isFalse);
    expect(host.calls[SiponMapCommands.centerOnUser], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
