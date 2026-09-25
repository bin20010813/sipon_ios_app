import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sipon/features/map/pages/add_venue_page.dart';
import 'package:sipon/features/drinks/records/pages/drink_record_page.dart';
import 'package:sipon/features/home/pages/home_page.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/map/pages/map_page.dart';
import 'package:sipon/features/reviews/pages/check_in_page.dart';
import 'package:sipon/features/profile/pages/profile_page.dart';
import 'package:sipon/features/routes/pages/route_planning_page.dart';
import 'pages/sipon_launch_page.dart';
import 'package:sipon/features/auth/pages/sms_login_page.dart';
import 'package:sipon/features/drinks/records/data/drink_budget_store.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/shared/services/sipon_auth_service.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/services/sipon_search_preferences.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';

part 'shell/sipon_shell.dart';
part 'widgets/shell_components.dart';

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

