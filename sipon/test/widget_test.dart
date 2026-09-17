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

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('语言/Language'), findsOneWidget);

    await tester.tap(find.text('En'));
    await tester.pumpAndSettle();

    expect(controller.language, SiponLanguage.en);
    expect(find.text('语言/Language'), findsOneWidget);
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

  test('map bounds query uses integer zoom for backend validation', () {
    final query = const SiponMapBounds(
      west: 121.45,
      south: 31.20,
      east: 121.49,
      north: 31.24,
    ).toQueryParameters(15.05);

    expect(query['west'], 121.45);
    expect(query['south'], 31.20);
    expect(query['east'], 121.49);
    expect(query['north'], 31.24);
    expect(query['zoom'], 15);
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

  test('cocktail detail preserves ingredient identity and amount', () {
    final detail = CocktailDetailInfo.fromJson({
      'id': 1,
      'name': '莫吉托',
      'ingredients': [
        {
          'id': 2,
          'code': 'rum',
          'name': '朗姆酒',
          'nameEn': 'Rum',
          'amountText': '45ml',
          'sortOrder': 1,
        },
      ],
    });

    expect(detail.sortedIngredients.single.name, '朗姆酒');
    expect(detail.sortedIngredients.single.nameEn, 'Rum');
    expect(detail.sortedIngredients.single.code, 'rum');
    expect(detail.sortedIngredients.single.amountText, '45ml');
  });

  test('cocktail lists keep only cocktails with Chinese names', () {
    final cocktails = CocktailInfo.listFromJson([
      {'id': 21, 'name': '伏特加蔓越莓', 'nameEn': 'Cape Codder'},
      {'id': 22, 'name': 'Mojito', 'nameEn': 'Mojito'},
      {'id': 23, 'name': null, 'nameEn': 'Gin Tonic'},
    ]);

    expect(cocktails.map((cocktail) => cocktail.id), [21]);
  });

  test('cocktail image falls back to the cocktail API asset', () {
    final cocktail = CocktailInfo.fromJson({
      'id': 21,
      'code': 'cape_codder',
      'name': '伏特加蔓越莓',
    });

    expect(
      cocktail.resolvedImageUrl(
        const SiponApiConfig(baseUrl: 'https://api.example.test'),
      ),
      'https://api.example.test/api/cocktails/cape_codder.png',
    );
  });
}
