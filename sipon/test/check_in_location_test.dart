import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/pages/check_in_page.dart';
import 'package:sipon/services/map/sipon_map_host.dart';
import 'package:sipon/services/map/sipon_map_protocol.dart';
import 'package:sipon/services/map/sipon_map_widget.dart';
import 'package:sipon/services/sipon_api_client.dart';
import 'package:sipon/services/sipon_api_config.dart';
import 'package:sipon/services/sipon_api_service.dart';
import 'package:sipon/services/sipon_city_controller.dart';
import 'package:sipon/widgets/sipon_city_picker.dart';

class _LocatedCity extends SiponCityController {
  _LocatedCity() : super(initialCity: '郑州', initialProvince: '河南省');
  Future<SiponLocateResult> Function() locate = () async =>
      const SiponLocateResult(
        status: SiponLocateStatus.success,
        position: SiponLocationPoint(113.8, 34.8),
      );
  int locationRequests = 0;

  @override
  Future<SiponLocateResult> locateCurrentCity() {
    locationRequests++;
    return locate();
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform_views,
          (call) async {
            // 测试手动注入地图宿主，不创建真正的 iOS 平台视图。
            if (call.method == 'create') return Completer<Object?>().future;
            return null;
          },
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> openPage(
    WidgetTester tester,
    _LocatedCity city,
    List<Uri> requests,
  ) async {
    final api = SiponApiService(
      apiClient: SiponApiClient(
        config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode([
                {
                  'id': 1,
                  'name': '用户附近酒吧',
                  'longitude': 113.801,
                  'latitude': 34.801,
                  'address': '测试地址',
                  'distanceMeters': 500,
                },
              ]),
            ),
            200,
          );
        }),
      ),
    );
    await tester.pumpWidget(
      SiponCityScope(
        controller: city,
        child: MaterialApp(
          home: Scaffold(body: CheckInPage(apiService: api)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('打卡地图首帧与推荐使用设备坐标，切换城市不覆盖用户位置', (tester) async {
    final city = _LocatedCity();
    addTearDown(city.dispose);
    final requests = <Uri>[];
    await openPage(tester, city, requests);
    expect(requests.single.path, '/api/bars/nearby');
    expect(requests.single.queryParameters, {
      'longitude': '113.8',
      'latitude': '34.8',
      'radiusMeters': '3000',
      'limit': '20',
    });
    expect(find.text('用户附近酒吧'), findsOneWidget);
    expect(find.text('约500m  ·  测试地址'), findsOneWidget);

    final host = _Host();
    final map = tester.widget<SiponMapWidget>(find.byType(SiponMapWidget));
    await tester.runAsync(() async {
      await (map.onHostReady as Future<void> Function(SiponMapHost))(host);
    });
    expect(host.calls[SiponMapCommands.setup]!['lng'], 113.8);
    expect(host.calls[SiponMapCommands.setup]!['lat'], 34.8);
    await city.selectCity('北京');
    await tester.pump();
    expect(requests, hasLength(1));
    expect(city.locationRequests, 1);
    expect(host.calls[SiponMapCommands.flyToCity], isNull);
    expect(host.calls[SiponMapCommands.focusOn], isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final status in [
    SiponLocateStatus.permissionDenied,
    SiponLocateStatus.serviceDisabled,
    SiponLocateStatus.failed,
  ]) {
    testWidgets('定位 $status 不回退城市中心，重试后使用实际位置', (tester) async {
      final city = _LocatedCity()
        ..locate = () async => SiponLocateResult(status: status);
      addTearDown(city.dispose);
      final requests = <Uri>[];
      await openPage(tester, city, requests);
      expect(requests, isEmpty);
      expect(find.byType(SiponMapWidget), findsNothing);
      expect(find.text('重新定位'), findsOneWidget);
      city.locate = () async => const SiponLocateResult(
        status: SiponLocateStatus.success,
        position: SiponLocationPoint(113.8, 34.8),
      );
      await tester.tap(find.text('重新定位'));
      await tester.pump();
      expect(requests.single.queryParameters['longitude'], '113.8');
      expect(find.byType(SiponMapWidget), findsOneWidget);
      expect(find.text('用户附近酒吧'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('定位未完成前不展示默认上海，页面关闭后忽略定位结果', (tester) async {
    final pending = Completer<SiponLocateResult>();
    final city = _LocatedCity()..locate = () => pending.future;
    addTearDown(city.dispose);
    final requests = <Uri>[];
    await openPage(tester, city, requests);
    expect(find.text('正在获取当前位置…'), findsOneWidget);
    expect(find.byType(SiponMapWidget), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(
      const SiponLocateResult(
        status: SiponLocateStatus.success,
        position: SiponLocationPoint(113.8, 34.8),
      ),
    );
    await tester.pump();
    expect(requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
