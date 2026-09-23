import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/language_transform.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/widgets/map/venue_detail_page.dart';
import 'package:sipon/pages/venue_fullscreen_map_page.dart';

void main() {
  testWidgets('详情页初始布局:内容应铺满全屏宽度', (tester) async {
    const venue = MapVenue(
      id: '191',
      name: '1919LiveHouse',
      longitude: 121.4,
      latitude: 31.2,
      kind: MapVenueKind.livehouse,
      rating: 4.8,
      address: '测试地址',
      distance: '',
      tags: [],
      imageAsset: 'assest/首页/图片素材/酒吧1.png',
    );

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: SiponLanguageController(),
        child: MaterialApp(home: VenueDetailPage(venue: venue)),
      ),
    );
    await tester.pump();

    final size = tester.getSize(find.byType(CustomScrollView).first);
    debugPrint('CustomScrollView size = $size');

    expect(size.width, greaterThan(300));
  });

  testWidgets('详情页半屏地图可放大并返回', (tester) async {
    const venue = MapVenue(
      id: 'map-preview',
      name: '测试酒吧',
      longitude: 121.4,
      latitude: 31.2,
      kind: MapVenueKind.pub,
      rating: 4.5,
      address: '测试地址',
      distance: '',
      tags: [],
      imageAsset: 'assest/首页/图片素材/酒吧1.png',
    );

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: SiponLanguageController(),
        child: const MaterialApp(home: VenueDetailPage(venue: venue)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    final mapAction = find.text('查看地图');
    await tester.ensureVisible(mapAction);
    await tester.tap(mapAction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 450));

    await tester.tap(find.byKey(const ValueKey('expand-venue-map')));
    await tester.pumpAndSettle();
    expect(find.byType(VenueFullscreenMapPage), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byType(VenueFullscreenMapPage), findsNothing);
    expect(find.byKey(const ValueKey('expand-venue-map')), findsOneWidget);

    await tester.tapAt(const Offset(400, 100));
    await tester.pumpAndSettle();
    expect(find.byType(VenueFullscreenMapPage), findsOneWidget);
  });
}
