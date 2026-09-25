import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sipon/app/theme/sipon_theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('SiponThemeController', () {
    test('maps persisted values to theme modes', () {
      expect(SiponThemeController.modeFromStorage('light'), ThemeMode.light);
      expect(SiponThemeController.modeFromStorage('dark'), ThemeMode.dark);
      expect(SiponThemeController.modeFromStorage('system'), ThemeMode.system);
      expect(SiponThemeController.modeFromStorage(null), ThemeMode.system);
      expect(
        SiponThemeController.modeFromStorage('unsupported'),
        ThemeMode.system,
      );
    });

    test('loads the persisted mode', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SiponThemeController.preferenceKey: 'dark',
      });

      final controller = await SiponThemeController.load();

      expect(controller.mode, ThemeMode.dark);
    });

    test('setMode updates and notifies synchronously', () async {
      final controller = SiponThemeController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final save = controller.setMode(ThemeMode.dark);

      expect(controller.mode, ThemeMode.dark);
      expect(notifications, 1);
      await save;
    });

    test('setMode persists each supported value', () async {
      final controller = SiponThemeController();

      for (final mode in <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
        ThemeMode.system,
      ]) {
        await controller.setMode(mode);
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getString(SiponThemeController.preferenceKey),
          mode.name,
        );
      }
    });

    test('setting the current mode does not notify again', () async {
      final controller = SiponThemeController(initialMode: ThemeMode.dark);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setMode(ThemeMode.dark);

      expect(notifications, 0);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.containsKey(SiponThemeController.preferenceKey),
        isFalse,
      );
    });
  });
}
