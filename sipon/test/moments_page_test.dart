import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/moments/pages/moments_page.dart';
import 'package:sipon/shared/services/home_moments_repository.dart';
import 'package:sipon/shared/services/mock_home_moments_repository.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} feed fits a narrow phone, refreshes and keeps preview interactions local',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final city = SiponCityController();
        final language = SiponLanguageController();
        final repository = _TrackingRepository();
        final pageKey = GlobalKey<MomentsPageState>();
        addTearDown(city.dispose);
        addTearDown(language.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? SiponTheme.dark : SiponTheme.light,
            home: SiponLanguageScope(
              controller: language,
              child: SiponCityScope(
                controller: city,
                child: Scaffold(
                  body: MomentsPage(
                    key: pageKey,
                    bottomOverlayInset: 90,
                    repository: repository,
                    onCheckInPressed: () async {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('酒友动态'), findsOneWidget);
        expect(find.text('发布动态'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('全部品类'), findsNothing);
        final media = find.byKey(const ValueKey('moment-photos--100'));
        expect(tester.getSize(media).width, 104);
        expect(tester.getSize(media).height, 104);
        final author = find.text('微醺的阿柚');
        final venue = find.text('巷口小酒馆');
        final comment = find.text('今晚的快乐是这杯柑橘特调，酸甜刚好。和朋友慢慢聊到打烊。');
        expect(
          tester.getBottomLeft(author).dy,
          lessThan(tester.getTopLeft(media).dy),
        );
        expect(
          tester.getTopLeft(venue).dx,
          greaterThan(tester.getTopRight(media).dx),
        );
        expect(tester.getTopLeft(comment).dx, tester.getTopLeft(venue).dx);
        expect(
          tester.getTopLeft(comment).dy,
          greaterThan(tester.getBottomLeft(venue).dy),
        );

        final video = find.byKey(const ValueKey('moment-photos--101'));
        expect(tester.getSize(video), const Size(104, 104));
        expect(find.byIcon(Icons.play_circle_fill_rounded), findsWidgets);
        expect(repository.loadCount, 1);
        await tester.tap(find.byIcon(Icons.favorite_border_rounded).first);
        await tester.pumpAndSettle();
        expect(find.text('模拟动态，仅供预览展示'), findsOneWidget);
        await pageKey.currentState!.refresh();
        await tester.pumpAndSettle();
        expect(repository.loadCount, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _TrackingRepository extends MockHomeMomentsRepository {
  int loadCount = 0;

  @override
  Future<HomeFeedPage> load(HomeFeedQuery query) {
    loadCount++;
    return super.load(query);
  }
}
