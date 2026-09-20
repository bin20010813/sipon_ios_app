import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/language_transform.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/widgets/map/venue_detail_page.dart';

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
}

