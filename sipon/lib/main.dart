import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'pages/drink_record_page.dart';
import 'pages/home_page.dart';
import 'pages/language_transform.dart';
import 'pages/map_page.dart';
import 'pages/profile_page.dart';
import 'services/drink_budget_store.dart';
import 'services/sipon_city_controller.dart';
import 'widgets/sipon_city_picker.dart';

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
  final SiponCityController _cityController = SiponCityController();

  @override
  void initState() {
    super.initState();
    DrinkBudgetStore.instance.ensureLoaded();
  }

  @override
  void dispose() {
    _cityController.dispose();
    _languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SiponCityScope(
      controller: _cityController,
      child: SiponLanguageScope(
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
              home: _StartupGate(cityController: _cityController),
            );
          },
        ),
      ),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate({required this.cityController});

  final SiponCityController cityController;

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;
  bool _showShell = false;
  bool _openRecordInitially = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      widget.cityController.load(),
      Future<void>.delayed(const Duration(milliseconds: 1300)),
    ]);

    if (!mounted) {
      return;
    }

    setState(() => _ready = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));

    if (mounted && !_showShell) {
      setState(() => _showShell = true);
    }
  }

  void _openRecord() {
    if (!_ready || _showShell) {
      return;
    }

    setState(() {
      _openRecordInitially = true;
      _showShell = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showShell) {
      return _SiponShell(openRecordInitially: _openRecordInitially);
    }

    return _SiponSplashScreen(ready: _ready, onRecordPressed: _openRecord);
  }
}

class _SiponShell extends StatefulWidget {
  const _SiponShell({this.openRecordInitially = false});

  final bool openRecordInitially;

  @override
  State<_SiponShell> createState() => _SiponShellState();
}

class _SiponShellState extends State<_SiponShell> {
  static const double _navigationReserveHeight = 86;

  int _currentIndex = 0;
  bool _recordRouteOpening = false;

  @override
  void initState() {
    super.initState();
    if (widget.openRecordInitially) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openDrinkRecord());
    }
  }

  void _selectTab(int index) {
    if (index == _currentIndex) {
      return;
    }

    setState(() => _currentIndex = index);
  }

  Future<void> _openDrinkRecord() async {
    if (_recordRouteOpening) {
      return;
    }

    _recordRouteOpening = true;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DrinkRecordPage()));
    _recordRouteOpening = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              HomePage(
                bottomOverlayInset: _navigationReserveHeight,
                onRecordPressed: _openDrinkRecord,
              ),
              const MapPage(bottomOverlayInset: _navigationReserveHeight),
              ProfilePage(
                bottomOverlayInset: _navigationReserveHeight,
                onRecordPressed: _openDrinkRecord,
              ),
            ],
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(34, 0, 34, 4),
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
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0x14FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F9A3D78),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: SizedBox(
          height: 62,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SiponBottomJumpItem(
                tooltip: text.homeTab,
                icon: Icons.home_rounded,
                selected: currentIndex == 0,
                activeColor: _activeColor,
                inactiveColor: _inactiveColor,
                onPressed: () => onTabSelected(0),
              ),
              _SiponBottomJumpItem(
                tooltip: text.mapTab,
                icon: Icons.map_rounded,
                selected: currentIndex == 1,
                activeColor: _activeColor,
                inactiveColor: _inactiveColor,
                onPressed: () => onTabSelected(1),
              ),
              _SiponBottomJumpItem(
                tooltip: text.profileTab,
                icon: Icons.person_rounded,
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
    required this.icon,
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
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
            fixedSize: const Size(70, 52),
            backgroundColor: Colors.transparent,
            foregroundColor: selected ? Colors.white : inactiveColor,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          icon: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 58,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 23),
                const SizedBox(height: 1),
                Text(
                  tooltip,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SiponSplashScreen extends StatelessWidget {
  const _SiponSplashScreen({
    required this.ready,
    required this.onRecordPressed,
  });

  final bool ready;
  final VoidCallback onRecordPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  const Text(
                    'SipOn',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF9A3D78),
                      fontSize: 46,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    text.t('记录每一次微醺'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF9A3D78),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    text.t('看见你的饮酒习惯'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF252229),
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    text.t('记录每一次饮酒，了解频率、偏好和变化趋势。'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8F8790),
                      fontSize: 13,
                      height: 1.42,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                  const Spacer(flex: 2),
                  FilledButton.icon(
                    onPressed: ready ? onRecordPressed : null,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(text.t('记一笔')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: const Color(0xFF9A3D78),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE6D3DF),
                      disabledForegroundColor: Colors.white,
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: ready
                            ? const Icon(
                                Icons.check_circle_rounded,
                                size: 14,
                                color: Color(0xFF9A3D78),
                              )
                            : const CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF9A3D78),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        text.t(ready ? '载入完成' : '正在整理你的饮酒记录...'),
                        style: const TextStyle(
                          color: Color(0xFF8F8790),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
