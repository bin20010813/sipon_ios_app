import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/features/reviews/pages/check_in_page.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_config.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';

class _SearchCity extends SiponCityController {
  _SearchCity() : super(initialCity: '郑州', initialProvince: '河南省');

  @override
  Future<SiponLocateResult> locateCurrentCity({
    SiponLocationPurpose purpose = SiponLocationPurpose.citySuggestion,
  }) async => const SiponLocateResult(
    status: SiponLocateStatus.success,
    position: SiponLocationPoint(113.8, 34.8),
  );
}

http.Response _jsonResponse(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200);

Future<void> _openPage(
  WidgetTester tester, {
  required Future<http.Response> Function(http.Request) search,
  ThemeData? theme,
}) async {
  final city = _SearchCity();
  addTearDown(city.dispose);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(375, 700);
  addTearDown(() => tester.view.reset());
  final api = SiponApiService(
    apiClient: SiponApiClient(
      config: const SiponApiConfig(baseUrl: 'https://api.example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/bars/nearby') {
          return _jsonResponse([
            {'id': 1, 'name': '附近酒吧', 'longitude': 113.801, 'latitude': 34.801},
          ]);
        }
        return search(request);
      }),
    ),
  );
  await tester.pumpWidget(
    SiponCityScope(
      controller: city,
      child: MaterialApp(
        theme: theme ?? SiponTheme.light,
        home: Scaffold(body: CheckInPage(apiService: api)),
      ),
    ),
  );
  await tester.pump();
}

void _expectAboveSearch(WidgetTester tester, Finder content) {
  expect(
    tester.getBottomLeft(content).dy,
    lessThan(tester.getTopLeft(find.byType(TextField)).dy),
  );
  expect(tester.takeException(), isNull);
}

void _testOnIos(
  String description,
  Future<void> Function(WidgetTester) callback,
) {
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

  for (final brightness in Brightness.values) {
    _testOnIos('搜索结果在 $brightness 模式向上展开，可滚动和清空', (tester) async {
      await _openPage(
        tester,
        theme: brightness == Brightness.dark
            ? SiponTheme.dark
            : SiponTheme.light,
        search: (_) async => _jsonResponse([
          for (var index = 0; index < 8; index++)
            {'id': 100 + index, 'name': '搜索酒吧$index', 'address': '测试地址'},
        ]),
      );
      final nearbyPosition = tester.getTopLeft(find.text('附近酒吧'));
      await tester.enterText(find.byType(TextField), '搜索酒吧');
      await tester.pump();
      _expectAboveSearch(tester, find.text('正在搜索…'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      _expectAboveSearch(tester, find.text('搜索结果'));
      _expectAboveSearch(tester, find.text('搜索酒吧0'));
      expect(tester.getTopLeft(find.text('附近酒吧')), nearbyPosition);
      final resultsList = find.ancestor(
        of: find.text('搜索酒吧0'),
        matching: find.byType(ListView),
      );
      await tester.drag(resultsList, const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(find.text('搜索酒吧7').hitTestable(), findsOneWidget);
      _expectAboveSearch(tester, find.text('搜索酒吧7'));

      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pump();
      expect(find.text('搜索结果'), findsNothing);
      expect(find.text('附近酒吧'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  _testOnIos('搜索失败和空结果也显示在搜索框上方，支持重试', (tester) async {
    var requests = 0;
    await _openPage(
      tester,
      search: (_) async {
        requests++;
        return requests == 1 ? http.Response('', 500) : _jsonResponse([]);
      },
    );
    await tester.enterText(find.byType(TextField), '没有结果');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    _expectAboveSearch(tester, find.text('重试搜索'));

    await tester.tap(find.text('重试搜索'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    _expectAboveSearch(tester, find.text('没有找到匹配的酒吧'));
    expect(requests, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
