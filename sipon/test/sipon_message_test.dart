import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';
import 'package:sipon/features/profile/pages/settings_support_page.dart';
import 'package:sipon/shared/localization/language_page.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/shared/widgets/sipon_message.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    final isCupertino = platform == TargetPlatform.iOS;
    final successIcon = isCupertino
        ? CupertinoIcons.check_mark_circled
        : Icons.check_circle_outline_rounded;
    final errorIcon = isCupertino
        ? CupertinoIcons.exclamationmark_circle
        : Icons.error_outline_rounded;

    for (final isDark in [false, true]) {
      testWidgets('$platform ${isDark ? 'dark' : 'light'} message style', (
        tester,
      ) async {
        final theme = (isDark ? SiponTheme.dark : SiponTheme.light).copyWith(
          platform: platform,
        );
        late BuildContext messageContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  messageContext = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        showSiponMessage(
          messageContext,
          '语言已切换',
          type: SiponMessageType.success,
        );
        await tester.pumpAndSettle();

        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.width, 320);
        expect(snackBar.duration, const Duration(milliseconds: 1800));
        expect(find.byIcon(successIcon), findsOneWidget);
        if (isCupertino) {
          expect(snackBar.backgroundColor, Colors.transparent);
          expect(find.byType(CupertinoPopupSurface), findsOneWidget);
          final surfaceContext = tester.element(
            find.byType(CupertinoPopupSurface),
          );
          expect(CupertinoTheme.brightnessOf(surfaceContext), theme.brightness);
          expect(
            tester.widget<Text>(find.text('语言已切换')).style!.color,
            CupertinoColors.label.resolveFrom(surfaceContext),
          );
        } else {
          expect(find.byType(CupertinoPopupSurface), findsNothing);
          expect(snackBar.backgroundColor, Colors.transparent);
          final surface = tester.widget<Material>(
            find
                .ancestor(
                  of: find.text('语言已切换'),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(
            surface.color,
            theme.extension<SiponThemeColors>()!.elevatedSurface,
          );
          expect(
            tester.widget<Text>(find.text('语言已切换')).style!.color,
            theme.colorScheme.onSurface,
          );
        }

        showSiponMessage(
          messageContext,
          '保存失败，请重试',
          type: SiponMessageType.error,
        );
        await tester.pumpAndSettle();
        expect(find.text('语言已切换'), findsNothing);
        expect(find.byIcon(successIcon), findsNothing);
        expect(find.byIcon(errorIcon), findsOneWidget);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).duration,
          const Duration(seconds: 4),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('保存失败，请重试'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    for (final settingsPage in [false, true]) {
      testWidgets(
        '$platform ${settingsPage ? 'settings' : 'language'} feedback',
        (tester) async {
          final controller = SiponLanguageController();
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            SiponLanguageScope(
              controller: controller,
              child: MaterialApp(
                theme: SiponTheme.light.copyWith(platform: platform),
                home: settingsPage
                    ? const SettingsSupportPage()
                    : const LanguagePage(),
              ),
            ),
          );

          await tester.tap(find.text('En'));
          await tester.pumpAndSettle();
          expect(controller.language, SiponLanguage.en);
          expect(find.text('Language updated'), findsOneWidget);
          expect(find.byIcon(successIcon), findsOneWidget);

          await tester.tap(find.text('中文'));
          await tester.pumpAndSettle();
          expect(controller.language, SiponLanguage.zh);
          expect(find.text('语言已切换'), findsOneWidget);
          expect(find.text('Language updated'), findsNothing);

          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$platform long message, large text, keyboard and safe area', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late BuildContext messageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: SiponTheme.light.copyWith(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 34),
              viewInsets: const EdgeInsets.only(bottom: 250),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                messageContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      showSiponMessage(messageContext, '部分记录删除失败，请检查网络连接后重试。');
      await tester.pumpAndSettle();
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).width, 248);
      expect(find.text('部分记录删除失败，请检查网络连接后重试。'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(SnackBar)).dy,
        lessThanOrEqualTo(550),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final initialDark in [false, true]) {
    for (final animate in [false, true]) {
      testWidgets(
        'theme switch from ${initialDark ? 'dark' : 'light'}, animation: $animate keeps readable feedback',
        (tester) async {
          final mode = ValueNotifier(
            initialDark ? ThemeMode.dark : ThemeMode.light,
          );
          addTearDown(mode.dispose);
          late BuildContext messageContext;
          await tester.pumpWidget(
            ValueListenableBuilder<ThemeMode>(
              valueListenable: mode,
              builder: (context, mode, _) => MaterialApp(
                theme: SiponTheme.light.copyWith(
                  platform: TargetPlatform.android,
                ),
                darkTheme: SiponTheme.dark.copyWith(
                  platform: TargetPlatform.android,
                ),
                themeMode: mode,
                themeAnimationDuration: animate
                    ? const Duration(milliseconds: 300)
                    : Duration.zero,
                home: Scaffold(
                  body: Builder(
                    builder: (context) {
                      messageContext = context;
                      return const SizedBox();
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 与外观设置一致：先通知主题变更，再在下一帧前弹出提示。
          mode.value = initialDark ? ThemeMode.light : ThemeMode.dark;
          showSiponMessage(
            messageContext,
            '外观已切换',
            type: SiponMessageType.success,
          );
          await tester.pump();
          for (var frame = 0; frame < 8; frame++) {
            await tester.pump(const Duration(milliseconds: 50));
            final foreground = tester
                .widget<Text>(find.text('外观已切换'))
                .style!
                .color!;
            final surface = tester
                .widget<Material>(
                  find
                      .ancestor(
                        of: find.text('外观已切换'),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .color!;
            final ratio =
                (math.max(
                      foreground.computeLuminance(),
                      surface.computeLuminance(),
                    ) +
                    0.05) /
                (math.min(
                      foreground.computeLuminance(),
                      surface.computeLuminance(),
                    ) +
                    0.05);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: 'frame $frame: $foreground on $surface',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('latest feedback replaces existing and queued messages', (
    tester,
  ) async {
    late BuildContext messageContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: SiponTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              messageContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final messenger = ScaffoldMessenger.of(messageContext);
    messenger.showSnackBar(const SnackBar(content: Text('old')));
    messenger.showSnackBar(const SnackBar(content: Text('queued')));
    await tester.pumpAndSettle();

    showSiponMessage(
      messageContext,
      'latest',
      messenger: messenger,
      duration: const Duration(milliseconds: 1200),
    );
    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
    expect(find.text('queued'), findsNothing);
    expect(find.text('latest'), findsOneWidget);
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(milliseconds: 1200),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
