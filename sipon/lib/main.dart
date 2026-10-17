import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/sipon_app.dart';
import 'app/theme/sipon_theme_controller.dart';
import 'shared/localization/language_transform.dart';
export 'app/sipon_app.dart' show SiponApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final themeController = await SiponThemeController.load();
  final languageController = await SiponLanguageController.load();
  runApp(
    SiponApp(
      themeController: themeController,
      languageController: languageController,
    ),
  );
}
