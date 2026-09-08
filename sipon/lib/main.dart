import 'package:flutter/material.dart';

import 'pages/drink_record_page.dart';
import 'pages/home_page.dart';
import 'pages/language_transform.dart';
import 'pages/map_page.dart';
import 'pages/check_in_page.dart';
import 'pages/profile_page.dart';
import 'pages/route_planning_page.dart';
import 'pages/sipon_launch_page.dart';
import 'pages/sms_login_page.dart';
import 'services/drink_budget_store.dart';
import 'services/sipon_auth_service.dart';
import 'services/sipon_city_controller.dart';
import 'widgets/sipon_city_picker.dart';

void main() {
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
  bool _sessionChecked = false;
  bool _isLoggedIn = false;
  bool _loginPageOpen = false;
  bool _launchCompleted = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final isLoggedIn = await SiponAuthService.instance.restoreSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoggedIn = isLoggedIn;
      _sessionChecked = true;
    });
  }

  void _onLoginSucceeded() {
    setState(() {
      _isLoggedIn = true;
      _launchCompleted = true;
    });
    _bootstrap();
  }

  void _onLaunchCompleted() {
    if (!_sessionChecked) {
      return;
    }
    if (!_isLoggedIn) {
      _openLoginPage();
      return;
    }

    setState(() => _launchCompleted = true);
    _bootstrap(showShellImmediately: true);
  }

  void _openLoginPage() {
    if (_loginPageOpen || !_sessionChecked || _isLoggedIn) {
      return;
    }

    _loginPageOpen = true;
    Navigator.of(context)
        .push<void>(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 620),
            reverseTransitionDuration: const Duration(milliseconds: 250),
            pageBuilder: (_, animation, _) => SmsLoginPage(
              onLoginSucceeded: () {
                Navigator.of(context).pop();
                _onLoginSucceeded();
              },
            ),
            transitionsBuilder: (_, animation, _, child) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            ),
          ),
        )
        .whenComplete(() {
          if (mounted) {
            _loginPageOpen = false;
          }
        });
  }

  void _onLogoutSucceeded() {
    setState(() {
      _ready = false;
      _showShell = false;
      _openRecordInitially = false;
      _isLoggedIn = false;
      _launchCompleted = false;
    });
  }

  Future<void> _bootstrap({bool showShellImmediately = false}) async {
    if (showShellImmediately) {
      await widget.cityController.load();
    } else {
      await Future.wait([
        widget.cityController.load(),
        Future<void>.delayed(const Duration(milliseconds: 1300)),
      ]);
    }

    if (!mounted) {
      return;
    }

    if (showShellImmediately) {
      setState(() {
        _ready = true;
        _showShell = true;
      });
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
    if (!_launchCompleted) {
      return SiponLaunchPage(
        readyToContinue: _sessionChecked,
        animateLogoToLogin: _sessionChecked && !_isLoggedIn,
        onContinue: _onLaunchCompleted,
      );
    }
    if (_showShell) {
      return _SiponShell(
        openRecordInitially: _openRecordInitially,
        onLogoutSucceeded: _onLogoutSucceeded,
      );
    }

    return _SiponSplashScreen(ready: _ready, onRecordPressed: _openRecord);
  }
}

class _SiponShell extends StatefulWidget {
  const _SiponShell({
    this.openRecordInitially = false,
    required this.onLogoutSucceeded,
  });

  final bool openRecordInitially;
  final VoidCallback onLogoutSucceeded;

  @override
  State<_SiponShell> createState() => _SiponShellState();
}

class _SiponShellState extends State<_SiponShell> {
  static const double _navigationReserveHeight = 86;

  double get _effectiveNavigationReserveHeight =>
      _navigationReserveHeight + MediaQuery.paddingOf(context).bottom;

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

  void _openPlusSheet() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: const Color(0x66000000),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => _SiponPlusSheet(
          onPlanRoute: _openRoutePlanning,
          onCheckIn: _openCheckIn,
        ),
        transitionsBuilder: (_, animation, _, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openRoutePlanning() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const RoutePlanningPage()));

  Future<void> _openCheckIn() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (_) => const CheckInPage(),
  );

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
                bottomOverlayInset: _effectiveNavigationReserveHeight,
                onRecordPressed: _openDrinkRecord,
              ),
              MapPage(bottomOverlayInset: _effectiveNavigationReserveHeight),
              ProfilePage(
                bottomOverlayInset: _effectiveNavigationReserveHeight,
                onRecordPressed: _openDrinkRecord,
                onLogoutSucceeded: widget.onLogoutSucceeded,
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
                onPlusPressed: _openPlusSheet,
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
    required this.onPlusPressed,
  });

  static const Color _activeColor = Color(0xFF9A3D78);
  static const Color _inactiveColor = Color(0xFF7F7F85);

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onPlusPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
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
          ),
          const SizedBox(width: 10),
          _SiponBottomPlusButton(onPressed: onPlusPressed),
        ],
      ),
    );
  }
}

class _SiponBottomPlusButton extends StatelessWidget {
  const _SiponBottomPlusButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '更多操作',
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onPressed,
          radius: 32,
          highlightShape: BoxShape.circle,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xFF8F8790),
              size: 28,
            ),
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
            child: Center(child: Icon(icon, size: 28)),
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

class _SiponPlusSheet extends StatelessWidget {
  const _SiponPlusSheet({required this.onPlanRoute, required this.onCheckIn});

  static const Color _cardBg = Colors.white;
  static const Color _muted = Color(0xFF8F8790);

  final VoidCallback onPlanRoute;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final mediaQuery = MediaQuery.of(context);
    final viewInsets = mediaQuery.viewInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F2F5),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0x22000000),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        text.plusSheetTitle,
                        style: TextStyle(
                          color: Color(0xFF252229),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text.plusSheetHint,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _SiponPlusSheetGrid(
                        onPlanRoute: onPlanRoute,
                        onCheckIn: onCheckIn,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SiponPlusSheetGrid extends StatefulWidget {
  const _SiponPlusSheetGrid({
    required this.onPlanRoute,
    required this.onCheckIn,
  });

  final VoidCallback onPlanRoute;
  final VoidCallback onCheckIn;

  @override
  State<_SiponPlusSheetGrid> createState() => _SiponPlusSheetGridState();
}

class _SiponPlusSheetGridState extends State<_SiponPlusSheetGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _animatedCard({required int index, required Widget child}) {
    final start = index * 0.16;
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 0.72 + index * 0.1, curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - progress)),
            child: Transform.scale(
              scale: 0.9 + progress * 0.1,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _animatedCard(
                index: 0,
                child: _SiponPlusActionCard(
                  icon: Icons.alt_route_rounded,
                  title: text.plusPlanRoute,
                  accent: Color(0xFF3F7CA8),
                  onTap: widget.onPlanRoute,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _animatedCard(
                index: 1,
                child: _SiponPlusActionCard(
                  icon: Icons.local_bar_rounded,
                  title: text.plusCheckInBar,
                  accent: Color(0xFFE08A3C),
                  onTap: widget.onCheckIn,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SiponPlusActionCard extends StatelessWidget {
  const _SiponPlusActionCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: Material(
        color: _SiponPlusSheet._cardBg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).pop();
            Future<void>.delayed(Duration.zero, onTap);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _SiponPlusSheet._cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x11000000)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _PlusIconBubble(icon: icon, color: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF252229),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
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

class _PlusIconBubble extends StatelessWidget {
  const _PlusIconBubble({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
