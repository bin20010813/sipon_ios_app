import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SiponThemeController extends ChangeNotifier {
  SiponThemeController({ThemeMode initialMode = ThemeMode.system})
    : _mode = initialMode;

  static const String preferenceKey = 'sipon.theme_mode.v1';

  ThemeMode _mode;
  Future<void> _saveQueue = Future<void>.value();

  ThemeMode get mode => _mode;

  static Future<SiponThemeController> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return SiponThemeController(
        initialMode: modeFromStorage(preferences.getString(preferenceKey)),
      );
    } catch (error, stackTrace) {
      debugPrint('Sipon: loading theme preference failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return SiponThemeController();
    }
  }

  Future<void> setMode(ThemeMode mode) {
    if (_mode == mode) return Future<void>.value();
    _mode = mode;
    notifyListeners();

    final value = mode.name;
    final completer = Completer<void>();
    _saveQueue = _saveQueue.catchError((_) {}).then((_) async {
      try {
        final preferences = await SharedPreferences.getInstance();
        final saved = await preferences.setString(preferenceKey, value);
        if (!saved) throw StateError('SharedPreferences rejected the write.');
        completer.complete();
      } catch (error, stackTrace) {
        debugPrint('Sipon: saving theme preference failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static ThemeMode modeFromStorage(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

class SiponThemeScope extends InheritedNotifier<SiponThemeController> {
  const SiponThemeScope({
    super.key,
    required SiponThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static SiponThemeController controllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SiponThemeScope>();
    assert(scope?.notifier != null, 'SiponThemeScope was not found.');
    return scope!.notifier!;
  }

  static SiponThemeController? maybeControllerOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SiponThemeScope>()
        ?.notifier;
  }
}
