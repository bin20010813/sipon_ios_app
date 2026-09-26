import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/check_in_page.dart';
import 'package:sipon/services/sipon_api_client.dart';
import 'package:sipon/services/sipon_api_service.dart';
import 'package:sipon/widgets/review_composer.dart';

class _ReviewApi extends SiponApiService {
  final submissions = <Map<String, Object?>>[];

  @override
  Future<dynamic> createCheckIn(Map<String, Object?> body) async {
    submissions.add(Map.of(body));
    if (submissions.length == 1) {
      throw const SiponApiException(
        statusCode: 400,
        message: 'Unknown rating field',
      );
    }
    return {'id': 1};
  }
}

void main() {
  test('aspect scores are available as fields and readable review text', () {
    const ratings = ReviewAspectRatings(
      drinks: 4,
      food: 3,
      service: 5,
      atmosphere: 4,
    );
    expect(ratings.toPayload(), {
      'drinkRating': 4,
      'foodRating': 3,
      'serviceRating': 5,
      'atmosphereRating': 4,
    });
    expect(
      ratings.prependToContent('会再来'),
      '酒水 4/5 · 食物 3/5 · 服务 5/5 · 氛围 4/5\n\n会再来',
    );
  });

  testWidgets('review form uploads aspect scores with a legacy fallback', (
    tester,
  ) async {
    final api = _ReviewApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CheckInCommentPage(
          barId: 42,
          venueName: '测试酒馆',
          venueAddress: '测试地址',
          apiService: api,
        ),
      ),
    );

    for (final tooltip in ['4 星', '酒水 4 星', '食物 3 星', '服务 5 星', '氛围 4 星']) {
      final star = find.byTooltip(tooltip);
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();
    }
    final comment = find.byType(TextField);
    await tester.ensureVisible(comment);
    await tester.enterText(comment, '值得再来');
    final submit = find.text('完成打卡');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(api.submissions, hasLength(2));
    expect(api.submissions.first['drinkRating'], 4);
    expect(api.submissions.first['foodRating'], 3);
    expect(api.submissions.first['serviceRating'], 5);
    expect(api.submissions.first['atmosphereRating'], 4);
    expect(api.submissions.last.containsKey('drinkRating'), isFalse);
    expect(
      api.submissions.last['content'],
      '酒水 4/5 · 食物 3/5 · 服务 5/5 · 氛围 4/5\n\n值得再来',
    );
  });
}
