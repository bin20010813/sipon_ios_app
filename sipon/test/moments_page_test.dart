import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/language_transform.dart';
import 'package:sipon/pages/moments_page.dart';
import 'package:sipon/services/sipon_city_controller.dart';
import 'package:sipon/widgets/sipon_city_picker.dart';

void main() {
  testWidgets(
    'standalone feed fits a narrow phone and shows compact photo and video thumbnails',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final city = SiponCityController();
      final language = SiponLanguageController();
      addTearDown(city.dispose);
      addTearDown(language.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: SiponLanguageScope(
            controller: language,
            child: SiponCityScope(
              controller: city,
              child: const Scaffold(body: MomentsPage(bottomOverlayInset: 90)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('酒友动态'), findsOneWidget);
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
      expect(tester.takeException(), isNull);
    },
  );
}
