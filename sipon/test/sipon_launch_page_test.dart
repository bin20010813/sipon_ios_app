
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/app/pages/sipon_launch_page.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Android launch fades in with $brightness background', (
      tester,
    ) async {
      var continued = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: SiponTheme.light,
          darkTheme: SiponTheme.dark,
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: SiponLaunchPage(
            readyToContinue: false,
            animateLogoToLogin: false,
            onContinue: () => continued = true,
          ),
        ),
      );

      final entryOpacity = find
          .descendant(
            of: find.byType(TweenAnimationBuilder<double>),
            matching: find.byType(Opacity),
          )
          .first;
      expect(tester.widget<Opacity>(entryOpacity).opacity, 0);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        brightness == Brightness.dark
            ? SiponThemeColors.dark.elevatedSurface
            : SiponThemeColors.light.elevatedSurface,
      );

      await tester.pump(const Duration(milliseconds: 110));
      expect(
        tester.widget<Opacity>(entryOpacity).opacity,
        inExclusiveRange(0, 1),
      );
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.widget<Opacity>(entryOpacity).opacity, 1);
      expect(find.text('Sip’On'), findsOneWidget);
      expect(find.text('酒吧地图'), findsOneWidget);
      expect(find.text('杭州探极科技有限公司'), findsOneWidget);
      expect(continued, isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets('iOS launch remains visible immediately', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SiponLaunchPage(
          readyToContinue: false,
          animateLogoToLogin: false,
          onContinue: () {},
        ),
      ),
    );
    final opacity = find
        .descendant(
          of: find.byType(TweenAnimationBuilder<double>),
          matching: find.byType(Opacity),
        )
        .first;
    expect(tester.widget<Opacity>(opacity).opacity, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
