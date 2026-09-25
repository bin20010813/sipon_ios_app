import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/main.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/profile/pages/profile_page.dart';
import 'package:sipon/shared/services/sipon_api_config.dart';
import 'package:sipon/shared/services/sipon_api_models.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/features/map/data/api_venue_detail_repository.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/features/map/models/venue_detail_models.dart';
import 'package:sipon/features/map/widgets/venue_common.dart';
import 'package:sipon/features/map/widgets/venue_detail_view.dart';

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

  test('bar cards use the first sorted image thumbnail', () {
    final bar = SiponBarMapItem.fromJson({
      'id': 42,
      'name': 'Test Bar',
      'lng': 121.4,
      'lat': 31.2,
      'images': [
        {
          'sortOrder': 2,
          'imageUrl': '/original/2',
          'thumbnailUrl': '/thumb/2',
          'mediumImageUrl': '/medium/2',
        },
        {
          'sortOrder': 0,
          'imageUrl': '/original/0',
          'thumbnailUrl': '/thumb/0',
          'mediumImageUrl': '/medium/0',
        },
      ],
    });

    expect(bar.hasImage, isTrue);
    expect(bar.resolvedThumbnailUrl, '/thumb/0');
    expect(bar.resolvedMediumImageUrl, '/medium/0');
    expect(bar.imageUrl, '/original/0');
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

  test('venue detail sorts images and keeps medium/original pairs', () async {
    final detail = await SiponApiVenueDetailRepository(api: _BarImagesApi())
        .fetchDetail(
          const MapVenue(
            id: '42',
            name: 'Test Bar',
            longitude: 121.4,
            latitude: 31.2,
            kind: MapVenueKind.pub,
            rating: 4.8,
            address: 'Test address',
            distance: '1km',
            tags: [],
            imageAsset: 'assets/images/bar-placeholder.png',
          ),
        );

    expect(detail.gallery.map((image) => image.mediumImageUrl), [
      '/api/bars/42/images/medium/0',
      '/api/bars/42/images/medium/1',
      '/api/bars/42/images/medium/2',
    ]);
    expect(detail.gallery.map((image) => image.imageUrl), [
      '/api/bars/42/images/original/0',
      '/api/bars/42/images/original/1',
      '/api/bars/42/images/original/2',
    ]);
  });

  testWidgets('venue detail scrolls from the image while data is loading', (
    tester,
  ) async {
    final languageController = SiponLanguageController();
    addTearDown(languageController.dispose);
    late ScrollController scrollController;

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: languageController,
        child: MaterialApp(
          home: Scaffold(
            body: DraggableScrollableSheet(
              initialChildSize: 1,
              minChildSize: 0.999,
              maxChildSize: 1,
              builder: (context, controller) {
                scrollController = controller;
                return VenueDetailContent(
                  venue: const MapVenue(
                    id: '42',
                    name: 'Test Bar',
                    longitude: 121.4,
                    latitude: 31.2,
                    kind: MapVenueKind.pub,
                    rating: 4.8,
                    address: 'Test address',
                    distance: '1km',
                    tags: [],
                    imageAsset: 'assest/首页/图片素材/酒吧1.png',
                  ),
                  scrollController: controller,
                  opacity: 1,
                  topInset: 0,
                  bottomOverlayInset: 0,
                  onClose: () {},
                  repository: _PendingVenueDetailRepository(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(scrollController.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(VenueImage).first, const Offset(0, -300));
    await tester.pump();

    expect(scrollController.offset, greaterThan(0));
  });
}

class _BarImagesApi extends SiponApiService {
  @override
  Future<dynamic> getBarById(int id) async => {
    'id': id,
    'name': 'Test Bar',
    'images': [
      {
        'sortOrder': 2,
        'imageUrl': '/api/bars/42/images/original/2',
        'thumbnailUrl': '/api/bars/42/images/thumb/2',
        'mediumImageUrl': '/api/bars/42/images/medium/2',
      },
      {
        'sortOrder': 0,
        'imageUrl': '/api/bars/42/images/original/0',
        'thumbnailUrl': '/api/bars/42/images/thumb/0',
        'mediumImageUrl': '/api/bars/42/images/medium/0',
      },
      {
        'sortOrder': 1,
        'imageUrl': '/api/bars/42/images/original/1',
        'thumbnailUrl': '/api/bars/42/images/thumb/1',
        'mediumImageUrl': '/api/bars/42/images/medium/1',
      },
    ],
  };

  @override
  Future<List<dynamic>> getBarReviews(
    int id, {
    SiponPage page = const SiponPage(),
  }) async => const [];

  @override
  Future<List<dynamic>> getBarHours(int id) async => const [];

  @override
  Future<List<dynamic>> getBarDrinks(
    int id, {
    SiponPage page = const SiponPage(),
  }) async => const [];

  @override
  Future<List<dynamic>> getBarMedia(int id) async => const [];
}

class _PendingVenueDetailRepository implements VenueDetailRepository {
  final Completer<VenueDetail> _detail = Completer<VenueDetail>();

  @override
  Future<VenueDetail> fetchDetail(MapVenue venue) => _detail.future;

  @override
  Future<VenueReviewPage> fetchReviews(
    MapVenue venue, {
    int offset = 0,
    int limit = 10,
  }) async => const VenueReviewPage(reviews: [], totalCount: 0, hasMore: false);
}
