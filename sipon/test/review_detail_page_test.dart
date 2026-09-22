import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/review_detail_page.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/services/sipon_api_service.dart';
import 'package:sipon/services/user_profile_data.dart';

class _Api extends SiponApiService {
  @override
  Future<dynamic> getBarById(int id) async => {
    'id': id, 'address': '愚园路 128 号',
  };
}

void main() {
  test('visit upload IDs take precedence over legacy images and bar cover', () {
    expect(reviewPhotoUrls({
      'mediaIds': ['one', 'two'],
      'mediaUrls': ['legacy'],
      'profileThumbnailUrl': 'bar-cover',
    }), ['/api/uploads/one/content', '/api/uploads/two/content']);
    expect(reviewPhotoUrls({'media': ['first', {'url': 'second'}, {}]}), ['first', 'second']);
    expect(reviewPhotoUrls({'profileThumbnailUrl': 'bar-cover'}), isEmpty);
  });

  testWidgets('shows visit rating, photos and opens selected photo', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ReviewDetailPage(
      apiService: _Api(),
      author: const UserProfileData(displayName: '微醺日记'),
      entry: const {'rating': 4, 'visitedAt': '2026-09-22', 'content': '氛围很好', 'mediaIds': ['one', 'two']},
      venue: const MapVenue(id: '1', name: '隐巷酒吧', longitude: 0, latitude: 0,
        kind: MapVenueKind.pub, rating: 2, address: '', distance: '', tags: [],
        imageAsset: 'assest/首页/图片素材/酒吧1.png'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('评价详情'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('2.0'), findsNothing);
    expect(find.text('氛围很好'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('打卡照片 2，共 2 张'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
