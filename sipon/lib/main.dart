import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/add_venue_page.dart';
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
import 'services/map/map_models.dart';
import 'services/sipon_auth_service.dart';
import 'services/sipon_city_controller.dart';
import 'services/sipon_search_preferences.dart';
import 'widgets/sipon_city_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
  );
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
    SiponSearchPreferences.instance.ensureLoaded();
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
  bool _showShell = false;
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
    bool isLoggedIn;
    try {
      isLoggedIn = await SiponAuthService.instance.restoreSession();
    } catch (error, stackTrace) {
      debugPrint('Sipon: restoring the saved session failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      isLoggedIn = SiponAuthService.instance.session != null;
    }
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
    _bootstrap();
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
      _showShell = false;
      _isLoggedIn = false;
      _launchCompleted = false;
    });
  }

  Future<void> _bootstrap() async {
    await widget.cityController.load();

    if (!mounted) {
      return;
    }
    setState(() => _showShell = true);
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
      return _SiponShell(onLogoutSucceeded: _onLogoutSucceeded);
    }

    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Color(0xFF9A3D78),
        ),
      ),
    );
  }
}

/// 鎮诞搴曟爮涓?Plus 寮瑰眰搴曡竟璺濈灞忓箷搴曡竟鐨勯棿璺濄€?
///
/// iOS 涓庡畨鍗撶殑绯荤粺搴曢儴瀹夊叏鍖哄樊寮傚緢澶э紙iPhone 鎭掍负 34pt锛屽畨鍗撴墜鍔垮鑸€氬父
/// 0~24dp銆佷笁閿鑸害 48dp锛夛紝鍥犳鎷嗘垚涓や釜鐙珛鏃嬮挳锛?
/// - iOS 璋冨噺鏁?`- 20`锛堣秺灏忓簳鏍忚秺楂橈紝iPhone 涓婄搴?= 34 - 鍑忔暟锛夛紱
/// - 瀹夊崜璋冨姞鏁?`+ 0`锛堣秺澶у簳鏍忚秺楂橈紱鍔犳硶鍦ㄤ换浣曞畨鍗撴満鍨嬮兘鐢熸晥锛?
///   鑰屽噺娉曠粨鏋滀細钀藉埌搴曢儴涓嬮檺涔嬩笅锛岀湅璧锋潵灏辨槸"鏀逛簡娌″弽搴?锛夈€?
double _bottomBarBottomGapFor(double safeBottom) {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return math.max(safeBottom - 18, 10);
  }
  return math.max(safeBottom + 2, 12);
}

class _SiponShell extends StatefulWidget {
  const _SiponShell({required this.onLogoutSucceeded});

  final VoidCallback onLogoutSucceeded;

  @override
  State<_SiponShell> createState() => _SiponShellState();
}

class _SiponShellState extends State<_SiponShell> {
  static const double _navigationBarHeight = 62;

  // viewPadding 鏄澶囩殑鍥哄畾绯荤粺瀹夊叏鍖猴紱padding 浼氬湪閿洏鍑虹幇鏃舵墸鎺?
  // viewInsets锛屽洜姝や笉鑳界敤瀹冩潵鍐冲畾鍏ㄥ眬鎮诞瀵艰埅鐨勫熀绾夸綅缃€傞棿璺濇寜骞冲彴
  // 鐨勫叿浣撴棆閽 _bottomBarBottomGapFor 鐨勬枃妗ｆ敞閲娿€?
  double get _bottomBarBottomGap =>
      _bottomBarBottomGapFor(MediaQuery.viewPaddingOf(context).bottom);

  /// 搴曟爮鍗犳嵁鐨勬€婚珮搴︼紝鍚勯〉闈㈢敤瀹冨仛鍒楄〃搴曢儴鐨勬粴鍔ㄩ鐣欍€?
  double get _effectiveNavigationReserveHeight =>
      _navigationBarHeight + _bottomBarBottomGap;

  /// 鎴戠殑椤电姸鎬佸紩鐢紝鐢ㄤ簬鍒囧洖 tab / 瑙勫垝璺嚎 / 鎵撳崱杩斿洖鍚庡埛鏂板揩鎹峰叆鍙ｈ鏁般€?
  final GlobalKey<ProfilePageState> _profilePageKey =
      GlobalKey<ProfilePageState>();

  int _currentIndex = 0;
  MapVenue? _mapRequestedVenue;
  bool _recordRouteOpening = false;
  final ValueNotifier<double> _mapSheetProgress = ValueNotifier<double>(0);
  // 棣栭〉鎼滅储閬僵灞曞紑鐘舵€侊細娉ㄥ叆 HomePage锛屽苟鐢辨偓娴簳鏍忕洃鍚互鍚屾闅愯棌銆?
  final ValueNotifier<bool> _homeSearchExpanded = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _mapSheetProgress.dispose();
    _homeSearchExpanded.dispose();
    super.dispose();
  }

  void _handleMapSheetProgress(double progress) {
    if (_mapSheetProgress.value != progress) {
      _mapSheetProgress.value = progress;
    }
  }

  void _selectTab(int index) {
    if (index == _currentIndex) {
      // 閲嶅鐐瑰嚮褰撳墠 tab锛氳涓烘墜鍔ㄥ埛鏂般€?
      if (index == 2) {
        _profilePageKey.currentState?.refreshProfile();
        _profilePageKey.currentState?.refreshCounts();
      }
      return;
    }

    setState(() {
      _currentIndex = index;
      _mapRequestedVenue = null;
    });
    if (index == 2) {
      _profilePageKey.currentState?.refreshProfile();
      _profilePageKey.currentState?.refreshCounts();
    }
  }

  void _showVenueOnMap(MapVenue venue) {
    setState(() {
      _mapRequestedVenue = venue;
      _currentIndex = 1;
    });
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
        barrierColor: Colors.transparent,
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => _SiponPlusSheet(
          onPlanRoute: _openRoutePlanning,
          onCheckIn: _openCheckIn,
          onAddVenue: _openAddVenue,
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

  /// 鎵撳紑璺嚎瑙勫垝锛涜繑鍥炲悗鍒锋柊鎴戠殑椤佃鏁帮紙鏂板/鍙樺寲鐨勮矾绾跨珛鍗冲弽鏄狅級銆?
  Future<void> _openRoutePlanning() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RoutePlanningPage()));
    _profilePageKey.currentState?.refreshCounts();
  }

  Future<void> _openAddVenue() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddVenuePage()));
    if (!mounted || created != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('閰掗淇℃伅宸叉彁浜わ紝瀹℃牳閫氳繃鍚庝細鏄剧ず鍦ㄥ湴鍥句腑'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 鎵撳紑鎵撳崱寮圭獥锛涘叧闂悗鍒锋柊鎴戠殑椤佃鏁帮紙鎵撳崱璁板綍鍙兘鏂板锛夈€?
  Future<void> _openCheckIn() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      builder: (_) => const CheckInPage(),
    );
    _profilePageKey.currentState?.refreshCounts();
  }

  @override
  Widget build(BuildContext context) {
    // 娉ㄦ剰锛氫笉瑕佸湪鏈眰璇诲彇 MediaQuery.viewInsets 鈥斺€?閿洏婊戝叆鍔ㄧ敾鏈熼棿瀹冮€愬抚
    // 鍙樺寲锛屼細瀵艰嚧澹冲眰涓?IndexedStack 鍐呬笁涓〉闈㈤€愬抚閲嶅缓锛堥敭鐩樻帀甯х殑鏉ユ簮锛夈€?
    // 搴曟爮瀵归敭鐩樼殑鍝嶅簲宸查殧绂诲埌 _ShellBottomBar 鍐呴儴銆?
    return Scaffold(
      // 鎼滅储妗嗚幏鍙栫劍鐐规椂锛屼笉璁?Scaffold 缂╃煭 Stack 鐨勫彲鐢ㄩ珮搴︼紱鍚﹀垯搴曟爮浼?
      // 琚敭鐩橀《璧枫€傞敭鐩樻湡闂村簳鏍忎細闅愯棌锛屾悳绱㈡浠嶄綅浜庡睆骞曢《閮ㄥ彲姝ｅ父杈撳叆銆?
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              HomePage(
                bottomOverlayInset: _effectiveNavigationReserveHeight,
                onRecordPressed: _openDrinkRecord,
                onVenueMapRequested: _showVenueOnMap,
                searchExpanded: _homeSearchExpanded,
              ),
              MapPage(
                bottomOverlayInset: _effectiveNavigationReserveHeight,
                active: _currentIndex == 1,
                requestedVenue: _mapRequestedVenue,
                onSheetProgressChanged: _handleMapSheetProgress,
              ),
              TickerMode(
                enabled: _currentIndex == 2,
                child: ProfilePage(
                  key: _profilePageKey,
                  bottomOverlayInset: _effectiveNavigationReserveHeight,
                  onRecordPressed: _openDrinkRecord,
                  onLogoutSucceeded: widget.onLogoutSucceeded,
                ),
              ),
            ],
          ),
          _ShellBottomBar(
            mapSheetProgress: _mapSheetProgress,
            searchOverlayActive: _homeSearchExpanded,
            currentIndex: _currentIndex,
            reserveHeight: _effectiveNavigationReserveHeight,
            bottomGap: _bottomBarBottomGap,
            onTabSelected: _selectTab,
            onPlusPressed: _openPlusSheet,
          ),
        ],
      ),
    );
  }
}

/// 澹冲眰鎮诞搴曟爮銆傚閿洏 viewInsets 鐨勪緷璧栬鍒绘剰闅旂鍦ㄦ湰缁勪欢鍐咃細iOS 閿洏
/// 婊戝叆鍔ㄧ敾鏈熼棿 engine 閫愬抚鏇存柊 viewInsets锛岃嫢鍦ㄥ３灞?build 璇诲彇浼氳
/// IndexedStack 閲屼笁涓〉闈㈣窡鐫€閫愬抚閲嶅缓锛涘湪杩欓噷璇诲彇锛屾瘡甯у彧閲嶅缓杩欎竴灏忓潡銆?
class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.mapSheetProgress,
    required this.searchOverlayActive,
    required this.currentIndex,
    required this.reserveHeight,
    required this.bottomGap,
    required this.onTabSelected,
    required this.onPlusPressed,
  });

  final ValueListenable<double> mapSheetProgress;
  final ValueListenable<bool> searchOverlayActive;
  final int currentIndex;
  final double reserveHeight;
  final double bottomGap;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onPlusPressed;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ValueListenableBuilder<double>(
      valueListenable: mapSheetProgress,
      builder: (context, sheetProgress, _) => ValueListenableBuilder<bool>(
        valueListenable: searchOverlayActive,
        builder: (context, searchActive, _) {
          final progress = currentIndex == 1 ? sheetProgress : 0.0;
          // 棣栭〉鎼滅储閬僵灞曞紑鏃跺悓姝ラ殣钘忓簳鏍忥細鏃㈤伩鍏嶅簳鏍忔诞鍦ㄦā绯婂眰涔嬩笂锛?
          // 涔熼槻姝㈡悳绱㈡ā寮忎笅璇偣 tab 鍒囬〉鍚庨椤垫畫鐣欐悳绱㈢姸鎬併€?
          final hidden = keyboardVisible || searchActive;
          return Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              ignoring: hidden || progress > 0.05,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: hidden ? const Offset(0, 1.25) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: hidden ? 0 : 1,
                  child: Transform.translate(
                    offset: Offset(0, (reserveHeight + 12) * progress),
                    child: Opacity(
                      opacity: 1 - progress,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(34, 0, 34, bottomGap),
                        child: _SiponBottomJumpBar(
                          currentIndex: currentIndex,
                          onTabSelected: onTabSelected,
                          onPlusPressed: onPlusPressed,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
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
      label: '鏇村鎿嶄綔',
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

class _SiponPlusSheet extends StatelessWidget {
  const _SiponPlusSheet({
    required this.onPlanRoute,
    required this.onCheckIn,
    required this.onAddVenue,
  });

  static const Color _cardBg = Colors.white;
  static const Color _muted = Color(0xFF8F8790);

  final VoidCallback onPlanRoute;
  final VoidCallback onCheckIn;
  final VoidCallback onAddVenue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final mediaQuery = MediaQuery.of(context);
    final viewInsets = mediaQuery.viewInsets.bottom;
    final bottomSafeInset = _bottomBarBottomGapFor(
      mediaQuery.viewPadding.bottom,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: const ColoredBox(color: Color(0x1A1B1219)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: viewInsets + bottomSafeInset,
            child: Padding(
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0x66FFFFFF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: ColoredBox(
                      color: const Color(0xBFF7F2F5),
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: Padding(
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
                                onAddVenue: onAddVenue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
    required this.onAddVenue,
  });

  final VoidCallback onPlanRoute;
  final VoidCallback onCheckIn;
  final VoidCallback onAddVenue;

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
                  icon: Icons.location_on_rounded,
                  title: text.plusCheckInBar,
                  accent: Color(0xFFE08A3C),
                  onTap: widget.onCheckIn,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _animatedCard(
          index: 2,
          child: _SiponPlusActionCard(
            icon: Icons.add_business_rounded,
            title: text.plusAddVenue,
            accent: Color(0xFF5E9B67),
            onTap: widget.onAddVenue,
          ),
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
