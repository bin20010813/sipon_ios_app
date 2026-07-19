import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'pages/home_page.dart';
import 'pages/language_transform.dart';
import 'pages/map_page.dart';
import 'pages/profile_page.dart';

const String _mapboxAccessToken = String.fromEnvironment(
  'MAPBOX_ACCESS_TOKEN',
  defaultValue:
      'pk.eyJ1IjoiYnNndWl2enNxIiwiYSI6ImNtbmpxYjdzZzBtajcycXM0aG1xNDdoN2YifQ.WjHfteUnM7ZBkihAhI1TUw',
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  mapbox.MapboxOptions.setAccessToken(_mapboxAccessToken);
  runApp(const SiponApp());
}

class SiponApp extends StatefulWidget {
  const SiponApp({super.key});

  @override
  State<SiponApp> createState() => _SiponAppState();
}

class _SiponAppState extends State<SiponApp> {
  final SiponLanguageController _languageController = SiponLanguageController();

  @override
  void dispose() {
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SiponLanguageScope(
      controller: _languageController,
      child: Builder(
        builder: (context) {
          final text = SiponLanguageScope.textOf(context);

          return MaterialApp(
            title: text.appTitle,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF9A3D78),
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: const Color(0xFFFBF8F9),
              useMaterial3: true,
            ),
            home: const _SiponShell(),
          );
        },
      ),
    );
  }
}

class _SiponShell extends StatefulWidget {
  const _SiponShell();

  @override
  State<_SiponShell> createState() => _SiponShellState();
}

class _SiponShellState extends State<_SiponShell> {
  static const double _navigationReserveHeight = 106;

  int _currentIndex = 0;

  void _selectTab(int index) {
    if (index == _currentIndex) {
      return;
    }

    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: const [
              HomePage(bottomOverlayInset: _navigationReserveHeight),
              MapPage(bottomOverlayInset: _navigationReserveHeight),
              ProfilePage(bottomOverlayInset: _navigationReserveHeight),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(48, 0, 48, 10),
              child: _SiponBottomJumpBar(
                currentIndex: _currentIndex,
                onTabSelected: _selectTab,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SiponBottomJumpBar extends StatelessWidget {
  const _SiponBottomJumpBar({
    required this.currentIndex,
    required this.onTabSelected,
  });

  static const Color _activeColor = Color(0xFF9A3D78);
  static const Color _inactiveColor = Color(0xFF7F7F85);

  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F9A3D78),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: SizedBox(
          height: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SiponBottomJumpItem(
                tooltip: text.homeTab,
                iconAsset: 'assest/首页/首页.png',
                selectedIconAsset: 'assest/首页/首页sel.png',
                selected: currentIndex == 0,
                activeColor: _activeColor,
                inactiveColor: _inactiveColor,
                onPressed: () => onTabSelected(0),
              ),
              _SiponBottomJumpItem(
                tooltip: text.mapTab,
                iconAsset: 'assest/首页/地图.png',
                selectedIconAsset: 'assest/首页/地图 sel.png',
                selected: currentIndex == 1,
                activeColor: _activeColor,
                inactiveColor: _inactiveColor,
                onPressed: () => onTabSelected(1),
              ),
              _SiponBottomJumpItem(
                tooltip: text.profileTab,
                iconAsset: 'assest/首页/口袋.png',
                selectedIconAsset: 'assest/首页/口袋sel.png',
                selected: currentIndex == 2,
                activeColor: _activeColor,
                inactiveColor: _inactiveColor,
                onPressed: () => onTabSelected(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiponBottomJumpItem extends StatelessWidget {
  const _SiponBottomJumpItem({
    required this.tooltip,
    required this.iconAsset,
    required this.selectedIconAsset,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onPressed,
  });

  final String tooltip;
  final String iconAsset;
  final String selectedIconAsset;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize: const Size(48, 48),
            backgroundColor: selected ? activeColor : Colors.transparent,
            foregroundColor: selected ? Colors.white : inactiveColor,
            shape: const CircleBorder(),
          ),
          icon: Image.asset(
            selected ? selectedIconAsset : iconAsset,
            width: 25,
            height: 25,
            color: selected ? Colors.white : inactiveColor,
          ),
        ),
      ),
    );
  }
}
