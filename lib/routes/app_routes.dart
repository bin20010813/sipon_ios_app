import 'package:flutter/material.dart';
import '../pages/main_page.dart';
import '../pages/login_page.dart';
import '../pages/map_page.dart';
import '../pages/drink_discovery_page.dart';

class AppRoutes {
  static const String home = '/';
  static const String login = '/login';
  static const String map = '/map';
  static const String discovery = '/discovery';

  static final Map<String, WidgetBuilder> routes = {
    home: (context) => const MainPage(),
    login: (context) => const LoginPage(),
    map: (context) => const MapPage(),
    discovery: (context) => const DrinkDiscoveryPage(),
  };
}
