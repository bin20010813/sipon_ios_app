import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/sipon_app.dart';
import 'app/theme/sipon_theme_controller.dart';
export 'app/sipon_app.dart' show SiponApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final themeController = await SiponThemeController.load();
  runApp(SiponApp(themeController: themeController));
}
