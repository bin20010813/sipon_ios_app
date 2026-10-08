import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sipon/features/drinks/records/data/drink_budget_store.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/features/profile/data/profile_bar_images.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_auth_service.dart';
import 'package:sipon/features/profile/data/user_profile_data.dart';
import 'package:sipon/shared/widgets/bottom_clamping_bouncing_scroll_physics.dart';
import 'package:sipon/features/drinks/records/widgets/drink_sticker.dart';
import 'package:sipon/shared/widgets/sipon_network_image.dart';
import 'package:sipon/shared/widgets/sipon_message.dart';
import 'package:sipon/features/drinks/records/pages/drink_sticker_calendar_page.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';
import 'profile_edit_page.dart';
import 'profile_notifications_page.dart';
import 'package:sipon/features/routes/pages/route_detail_map_page.dart';
import 'package:sipon/features/map/pages/venue_map_half_page.dart';
import 'public_profile_page.dart';
import 'package:sipon/features/reviews/pages/review_detail_page.dart';
import 'settings_support_page.dart';

part '../widgets/profile_header.dart';
part '../widgets/profile_lists.dart';
part '../widgets/budget_card.dart';
part '../widgets/budget_bill.dart';

String _formatCurrency(double value) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final intPart = fixed.substring(0, dot);
  final decimals = fixed.substring(dot);
  final buffer = StringBuffer();
  var count = 0;
  for (var index = intPart.length - 1; index >= 0; index--) {
    if (count > 0 && count % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(intPart[index]);
    count++;
  }
  final reversed = buffer.toString().split('').reversed.join();
  return '${negative ? '-' : ''}¥$reversed$decimals';
}

void _showProfileMessage(BuildContext context, String message) {
  showSiponMessage(context, message);
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.bottomOverlayInset = 0,
    this.onRecordPressed,
    this.onLogoutSucceeded,
  });

  final double bottomOverlayInset;
  final VoidCallback? onRecordPressed;
  final VoidCallback? onLogoutSucceeded;

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);

  static const String _avatarAsset = 'assest/首页/图片素材/Bharat Balami.png';
  static const String _drunkAsset = 'assest/我的/我喝过的@3x.png';
  static const String _wishAsset = 'assest/我的/我想喝的@3x.png';
  static const String _routeAsset = 'assest/我的/酒鬼线路@3x.png';
  // static const String _achievementAsset = 'assest/我的/成就勋章@3x.png';

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

/// 我的页状态；通过 [ProfilePageState.refreshCounts] 供外部（切回 tab、
/// 规划路线/打卡返回后）触发「喝过 / 想喝 / 酒鬼路线」计数刷新。
class ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final GlobalKey<_QuickEntryCardState> _quickEntryKey = GlobalKey();
  final SiponApiService _api = SiponApiService();
  UserProfileData? _profile;
  bool _profileLoading = true;
  bool _hasUnreadNotifications = false;
  Timer? _notificationTimer;
  bool _unreadRequestInFlight = false;
  bool _unreadRefreshQueued = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        _loadUnreadNotifications();
      }
    });
    _loadProfile();
    _loadUnreadNotifications();
  }

  /// 资料和概览分开请求；概览失败不会阻塞用户基础信息展示。
  Future<void> _loadProfile() async {
    UserProfileData? profile;
    try {
      final rawProfile = await _api.getMyProfile();
      profile = UserProfileData.fromJson(rawProfile);
      try {
        profile = profile.mergeOverview(await _api.getMyOverview());
      } on Exception {
        // 概览接口暂不可用时，仍展示 GET /users/me 的资料。
      }
    } on Exception {
      final cachedUser = SiponAuthService.instance.session?.user;
      if (cachedUser != null && cachedUser.isNotEmpty) {
        profile = UserProfileData.fromJson(cachedUser);
      }
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _profileLoading = false;
    });
  }

  Future<void> _editProfile() async {
    final current = _profile;
    if (current == null) {
      _showProfileMessage(context, '资料仍在加载，请稍后重试。');
      return;
    }
    final updated = await Navigator.of(context).push<UserProfileData>(
      MaterialPageRoute(builder: (_) => ProfileEditPage(profile: current)),
    );
    if (updated != null && mounted) {
      setState(() => _profile = updated);
      _loadUnreadNotifications();
      // PATCH 成功后立即 GET 可能命中后端的短暂旧缓存，不能用旧响应覆盖
      // 刚刚提交的头像；下次进入页面时再按正常流程刷新即可。
    }
  }

  Future<void> _loadUnreadNotifications() async {
    if (!mounted) return;
    if (_unreadRequestInFlight) {
      _unreadRefreshQueued = true;
      return;
    }
    _unreadRequestInFlight = true;
    try {
      final response = await _api.getUnreadNotificationCount();
      final value = response is Map
          ? response['unreadCount'] ?? response['count']
          : response;
      final count = value is num ? value.toInt() : int.tryParse('$value');
      if (mounted) {
        setState(() => _hasUnreadNotifications = (count ?? 0) > 0);
      }
    } on Exception {
      // The bell stays available when the count endpoint is unavailable.
    } finally {
      _unreadRequestInFlight = false;
      if (_unreadRefreshQueued && mounted) {
        _unreadRefreshQueued = false;
        unawaited(_loadUnreadNotifications());
      }
    }
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUnreadNotifications();
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfileNotificationsPage(profile: _profile),
      ),
    );
    if (mounted) {
      _loadProfile();
      _loadUnreadNotifications();
    }
  }

  void _openPublicProfile() {
    final id = _profile?.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(userId: id, isCurrentUser: true),
      ),
    );
  }

  /// 重新拉取三个快捷入口的计数，保证与后端最新数据一致。
  void refreshCounts() {
    _quickEntryKey.currentState?._loadCounts();
  }

  /// 切回「我的」页时重新拉取资料，避免后端变更用户 ID 后继续展示旧实例。
  Future<void> refreshProfile() async {
    await _loadProfile();
    await _loadUnreadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.siponColors;
    final bottomOverlayInset = widget.bottomOverlayInset;
    final onRecordPressed = widget.onRecordPressed;
    final onLogoutSucceeded = widget.onLogoutSucceeded;

    return Scaffold(
      // 背景显式设为渐变末端同色（白色），保证底部安全区不再露出米白底色条带。
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: themeColors.pageGradient,
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          // 底部不进安全区：渐变背景自然延伸到底，避免安全区露出一条
          // 与渐变脱节的底色带；底部空间由 bottomOverlayInset 预留。
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                physics: const BottomClampingBouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      10,
                      24,
                      26 + bottomOverlayInset,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _ProfileTopActions(
                          onLogoutSucceeded: onLogoutSucceeded,
                          onNotificationsPressed: _openNotifications,
                          hasUnreadNotifications: _hasUnreadNotifications,
                        ),
                        const SizedBox(height: 22),
                        _ProfileHeader(
                          profile: _profile,
                          loading: _profileLoading,
                          onEdit: _editProfile,
                          onViewPublicProfile: _profile?.id == null
                              ? null
                              : _openPublicProfile,
                        ),
                        const SizedBox(height: 22),
                        _QuickEntryCard(key: _quickEntryKey),
                        const SizedBox(height: 18),
                        _BudgetCard(onRecordPressed: onRecordPressed),
                      ],
                    ),
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
