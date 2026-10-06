part of '../sipon_app.dart';

class _SiponShell extends StatefulWidget {
  const _SiponShell({required this.onLogoutSucceeded});

  final VoidCallback onLogoutSucceeded;

  @override
  State<_SiponShell> createState() => _SiponShellState();
}

class _SiponShellState extends State<_SiponShell> {
  static const double _navigationBarHeight = 62;

  // viewPadding 表示固定安全区；键盘出现时仍用它计算底栏位置。
  double get _bottomBarBottomGap =>
      _bottomBarBottomGapFor(MediaQuery.viewPaddingOf(context).bottom);

  /// 页面列表底部为悬浮导航栏预留的高度。
  double get _effectiveNavigationReserveHeight =>
      _navigationBarHeight + _bottomBarBottomGap;

  /// 返回个人页或完成打卡、路线规划后刷新个人页数据。
  final GlobalKey<ProfilePageState> _profilePageKey =
      GlobalKey<ProfilePageState>();

  final _momentsPageKey = GlobalKey<MomentsPageState>();
  int _currentIndex = 0;
  MapVenue? _mapRequestedVenue;
  bool _recordRouteOpening = false;
  // IndexedStack 会立即构建全部 children；动态流首帧要发网络请求，
  // 首次切到该 tab 前先用占位，避免启动即请求（测试环境也会因此挂起）。
  bool _momentsVisited = false;
  final ValueNotifier<double> _mapSheetProgress = ValueNotifier<double>(0);
  // 与首页共享搜索展开状态，用于同步隐藏底栏。
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
      // 再次点击当前 tab 时手动刷新。
      if (index == 2) _momentsPageKey.currentState?.refresh();
      if (index == 3) {
        _profilePageKey.currentState?.refreshProfile();
        _profilePageKey.currentState?.refreshCounts();
      }
      return;
    }

    setState(() {
      _currentIndex = index;
      _mapRequestedVenue = null;
      if (index == 2) {
        _momentsVisited = true;
      }
    });
    if (index == 3) {
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

  /// 路线规划返回后刷新个人页计数。
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
    showSiponMessage(
      context,
      '酒吧信息已提交，审核通过后会显示在地图中',
      type: SiponMessageType.success,
    );
  }

  /// 关闭打卡面板后刷新个人页计数和动态列表。
  Future<void> _openCheckIn() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      builder: (_) => const CheckInPage(),
    );
    _profilePageKey.currentState?.refreshCounts();
    _momentsPageKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    // 键盘高度变化仅在底栏内监听，避免整个页面栈逐帧重建。
    return Scaffold(
      // 搜索时保持页面高度；底栏会在键盘显示期间隐藏。
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
                child: _momentsVisited
                    ? MomentsPage(
                        key: _momentsPageKey,
                        bottomOverlayInset: _effectiveNavigationReserveHeight,
                        onCheckInPressed: _openCheckIn,
                      )
                    : const SizedBox.shrink(),
              ),
              TickerMode(
                enabled: _currentIndex == 3,
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
