import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/main.dart';
import 'package:sipon/pages/language_transform.dart';
import 'package:sipon/pages/profile_page.dart';
import 'package:sipon/services/sipon_api_config.dart';
import 'package:sipon/services/sipon_api_models.dart';

void main() {
  testWidgets('Sipon app can be constructed', (WidgetTester tester) async {
    expect(const SiponApp(), isA<SiponApp>());
  });

  testWidgets('profile language switch updates global controller', (
    WidgetTester tester,
  ) async {
    final controller = SiponLanguageController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: controller,
        child: const MaterialApp(home: ProfilePage()),
      ),
    );

    expect(controller.language, SiponLanguage.zh);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('语言翻译'), findsOneWidget);

    await tester.tap(find.text('英文'));
    await tester.pumpAndSettle();

    expect(controller.language, SiponLanguage.en);
    expect(find.text('Language'), findsWidgets);
    expect(find.text('Account Security'), findsOneWidget);
  });

  test('bar map response parses API and GeoJSON shapes', () {
    final response = SiponBarMapResponse.fromJson({
      'mode': 'bars',
      'items': [
        {
          'id': 'bar-1',
          'name': 'Test Bar',
          'city': '上海市',
          'barSubtype': '精酿/啤酒吧',
          'lng': 121.1,
          'lat': 31.2,
          'rating': '4.7',
        },
        {
          'type': 'Feature',
          'properties': {
            'id': 'bar-2',
            'name': 'Feature Bar',
            'category': 'craft',
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [121.3, 31.4],
          },
        },
      ],
    });

    expect(response.mode, 'bars');
    expect(response.items, hasLength(2));
    expect(response.items.first.id, 'bar-1');
    expect(response.items.first.longitude, 121.1);
    expect(response.items.first.kind, 'craft');
    expect(response.items.first.address, '上海市');
    expect(response.items.first.tags, ['精酿', '啤酒吧']);
    expect(response.items.last.id, 'bar-2');
    expect(response.items.last.kind, 'craft');
    expect(response.items.last.latitude, 31.4);
  });

  test('api config keeps admin token out of normal headers', () {
    const config = SiponApiConfig(
      accessToken: 'access-token',
      adminToken: 'admin-token',
    );

    expect(config.headers(), {
      'Accept': 'application/json',
      'Authorization': 'Bearer access-token',
    });
    expect(config.headers(includeAuth: false, includeAdminToken: true), {
      'Accept': 'application/json',
      'X-Admin-Token': 'admin-token',
    });
  });
}
