import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/map/data/api_venue_detail_repository.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/features/map/models/venue_detail_models.dart';
import 'package:sipon/features/map/widgets/venue_detail_view.dart';

/// 空详情数据：避免用例触达默认 Mock/网络数据源，
/// 也保证无 gallery 图（预加载会留下测试无法推进的计时器）。
class _EmptyVenueDetailRepository implements VenueDetailRepository {
  const _EmptyVenueDetailRepository();

  @override
  Future<VenueDetail> fetchDetail(MapVenue venue) async {
    return VenueDetail(
      venue: venue,
      description: const [],
      latestUpdates: const [],
      businessHours: const {},
      phone: '',
      priceLevel: '',
      features: const [],
      signatureDrinks: const [],
      reviews: const [],
      gallery: const [],
      openNow: false,
      todayKey: '',
      todayHoursLabel: '',
      reviewCount: 0,
    );
  }

  @override
  Future<VenueReviewPage> fetchReviews(
    MapVenue venue, {
    int offset = 0,
    int limit = 10,
  }) async {
    return const VenueReviewPage(reviews: [], totalCount: 0, hasMore: false);
  }
}

void main() {
  testWidgets('expand map button scrolls away with venue details', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var expansions = 0;

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: SiponLanguageController(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: VenueDetailContent(
                venue: const MapVenue(
                  id: 'preview',
                  name: 'Bar A',
                  longitude: 121.4,
                  latitude: 31.2,
                  kind: MapVenueKind.pub,
                  rating: 4.5,
                  address: 'Test address',
                  distance: '',
                  tags: [],
                  imageAsset: 'assest/首页/图片素材/酒吧1.png',
                ),
                scrollController: controller,
                opacity: 1,
                topInset: 0,
                bottomOverlayInset: 0,
                onClose: () {},
                repository: const _EmptyVenueDetailRepository(),
                onExpandMap: () => expansions++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final button = find.byKey(const ValueKey('expand-venue-map'));
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    expect(expansions, 1);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsNothing);
  });
}
