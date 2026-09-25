part of '../sipon_app.dart';

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
