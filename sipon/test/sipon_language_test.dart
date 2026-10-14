import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/app/sipon_app.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/app/theme/sipon_theme_controller.dart';
import 'package:sipon/features/profile/pages/settings_support_page.dart';
import 'package:sipon/shared/localization/language_page.dart';
import 'package:sipon/shared/localization/language_transform.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sipon/language');

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('constructing an injected controller never queries the platform', () {
    final calls = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return 'zh';
    });
    final controller = SiponLanguageController(
      initialLanguage: SiponLanguage.en,
      platform: TargetPlatform.iOS,
    );
    addTearDown(controller.dispose);
    expect(controller.language, SiponLanguage.en);
    expect(controller.usesSystemLanguageSettings, isTrue);
    expect(calls, isEmpty);
  });

  for (final nativeLanguage in ['zh', 'en', 'unsupported', null]) {
    test('iOS startup reads native language $nativeLanguage', () async {
      final calls = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return nativeLanguage;
      });
      final controller = await SiponLanguageController.load(
        platform: TargetPlatform.iOS,
      );
      addTearDown(controller.dispose);
      expect(calls, ['getLanguage']);
      expect(
        controller.language,
        nativeLanguage == 'en' ? SiponLanguage.en : SiponLanguage.zh,
      );
      expect(
        controller.locale,
        nativeLanguage == 'en' ? const Locale('en') : const Locale('zh', 'CN'),
      );
    });
  }

  test('missing native channel preserves startup language', () async {
    final controller = await SiponLanguageController.load(
      platform: TargetPlatform.iOS,
    );
    addTearDown(controller.dispose);
    expect(controller.language, SiponLanguage.zh);
    await expectLater(
      controller.setLanguage(SiponLanguage.en),
      throwsA(isA<MissingPluginException>()),
    );
    expect(controller.language, SiponLanguage.zh);
  });

  test(
    'iOS request opens Settings without changing selected language',
    () async {
      final calls = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return true;
      });
      final controller = SiponLanguageController(platform: TargetPlatform.iOS);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      expect(await controller.setLanguage(SiponLanguage.en), isFalse);
      expect(calls, ['openSettings']);
      expect(controller.language, SiponLanguage.zh);
      expect(notifications, 0);
      expect(await controller.setLanguage(SiponLanguage.zh), isFalse);
      expect(calls, ['openSettings']);
    },
  );

  test('iOS Settings failure propagates and preserves language', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => false,
    );
    final controller = SiponLanguageController(platform: TargetPlatform.iOS);
    addTearDown(controller.dispose);
    await expectLater(
      controller.setLanguage(SiponLanguage.en),
      throwsA(isA<PlatformException>()),
    );
    expect(controller.language, SiponLanguage.zh);
  });

  test(
    'Android still changes immediately without calling native language APIs',
    () async {
      final calls = <String>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return 'en';
      });
      final controller = await SiponLanguageController.load(
        platform: TargetPlatform.android,
      );
      addTearDown(controller.dispose);
      expect(controller.usesSystemLanguageSettings, isFalse);
      final change = controller.setLanguage(SiponLanguage.en);
      expect(controller.language, SiponLanguage.en);
      expect(await change, isTrue);
      expect(calls, isEmpty);
    },
  );

  for (final settingsPage in [false, true]) {
    testWidgets(
      'iOS ${settingsPage ? 'settings' : 'language'} page retains actual language',
      (tester) async {
        var settingsOpens = 0;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          if (call.method == 'openSettings') settingsOpens++;
          return true;
        });
        final controller = SiponLanguageController(
          platform: TargetPlatform.iOS,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _languagePage(controller, settingsPage: settingsPage),
        );
        expect(
          find.text(const SiponAppText(SiponLanguage.zh).languageSettingsHint),
          findsOneWidget,
        );
        await tester.tap(find.text('En'));
        await tester.pumpAndSettle();
        expect(settingsOpens, 1);
        expect(controller.language, SiponLanguage.zh);
        expect(find.byType(SnackBar), findsNothing);
        if (!settingsPage) {
          expect(
            tester
                .widget<SegmentedButton<SiponLanguage>>(
                  find.byType(SegmentedButton<SiponLanguage>),
                )
                .selected,
            {SiponLanguage.zh},
          );
          await tester.tap(
            find.text(
              const SiponAppText(SiponLanguage.zh).languageOpenSettings,
            ),
          );
          await tester.pumpAndSettle();
          expect(settingsOpens, 2);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in SiponLanguage.values) {
    testWidgets('iOS Settings failure feedback is localized for $language', (
      tester,
    ) async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => false,
      );
      final controller = SiponLanguageController(
        initialLanguage: language,
        platform: TargetPlatform.iOS,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_languagePage(controller));
      await tester.tap(find.text(language == SiponLanguage.zh ? 'En' : '中文'));
      await tester.pumpAndSettle();
      expect(controller.language, language);
      expect(
        find.text(SiponAppText(language).languageSettingsOpenFailed),
        findsOneWidget,
      );
      expect(find.text('Language updated'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'Android language page preserves its translated success message',
    (tester) async {
      final controller = SiponLanguageController(
        platform: TargetPlatform.android,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(_languagePage(controller));
      await tester.tap(find.text('En'));
      await tester.pumpAndSettle();
      expect(controller.language, SiponLanguage.en);
      expect(find.text('Language updated'), findsOneWidget);
      await tester.tap(find.text('中文'));
      await tester.pumpAndSettle();
      expect(controller.language, SiponLanguage.zh);
      expect(find.text('语言已切换'), findsOneWidget);
      expect(find.text('Language updated'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'app resume reads actual native language and updates Flutter locale',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var nativeLanguage = 'zh';
      var reads = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getLanguage') {
          reads++;
          return nativeLanguage;
        }
        return true;
      });
      final controller = await SiponLanguageController.load(
        platform: TargetPlatform.iOS,
      );
      final themeController = SiponThemeController();
      addTearDown(controller.dispose);
      addTearDown(themeController.dispose);
      await tester.pumpWidget(
        SiponApp(
          languageController: controller,
          themeController: themeController,
        ),
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('zh', 'CN'),
      );
      expect(reads, 1);
      nativeLanguage = 'en';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(reads, 2);
      expect(controller.language, SiponLanguage.en);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.locale, const Locale('en'));
      expect(app.supportedLocales, contains(const Locale('zh', 'CN')));
      expect(app.localizationsDelegates, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      // The existing launch screen waits 2.35 seconds before checking mounted.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _languagePage(
  SiponLanguageController controller, {
  bool settingsPage = false,
}) {
  return SiponLanguageScope(
    controller: controller,
    child: MaterialApp(
      theme: SiponTheme.light,
      home: settingsPage ? const SettingsSupportPage() : const LanguagePage(),
    ),
  );
}
