import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/drink_budget_store.dart';
import '../services/map/map_models.dart';
import '../services/profile_bar_images.dart';
import '../services/sipon_api_service.dart';
import '../services/sipon_auth_service.dart';
import '../services/user_profile_data.dart';
import '../widgets/bottom_clamping_bouncing_scroll_physics.dart';
import '../widgets/drink_sticker.dart';
import '../widgets/sipon_network_image.dart';
import 'drink_sticker_calendar_page.dart';
import 'language_transform.dart';
import 'profile_edit_page.dart';
import 'route_detail_map_page.dart';
import 'venue_map_half_page.dart';
import 'public_profile_page.dart';
import 'settings_support_page.dart';

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
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
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
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);

  static const String _avatarAsset = 'assest/首页/图片素材/Bharat Balami.png';
  static const String _drunkAsset = 'assest/我的/我喝过的@3x.png';
  static const String _wishAsset = 'assest/我的/我想喝的@3x.png';
  static const String _routeAsset = 'assest/我的/酒鬼线路@3x.png';
  static const String _memberAsset = 'assest/我的/Sipon会员@3x.png';
  static const String _couponAsset = 'assest/我的/我的礼券@3x.png';
  // static const String _achievementAsset = 'assest/我的/成就勋章@3x.png';

  @override
  State<ProfilePage> createState() => ProfilePageState();
}

/// 我的页状态；通过 [ProfilePageState.refreshCounts] 供外部（切回 tab、
/// 规划路线/打卡返回后）触发「喝过 / 想喝 / 酒鬼路线」计数刷新。
class ProfilePageState extends State<ProfilePage> {
  final GlobalKey<_QuickEntryCardState> _quickEntryKey = GlobalKey();
  final SiponApiService _api = SiponApiService();
  UserProfileData? _profile;
  bool _profileLoading = true;

  /// 礼券数量；为 null 表示尚未加载或加载失败。
  int? _couponCount;

  // 成就勋章暂时隐藏，相关状态保留待后续启用。
  // /// 已解锁成就数量；为 null 表示尚未加载或加载失败。
  // int? _achievementCount;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadBenefits();
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
      // PATCH 成功后立即 GET 可能命中后端的短暂旧缓存，不能用旧响应覆盖
      // 刚刚提交的头像；下次进入页面时再按正常流程刷新即可。
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

  /// 拉取礼券数量；失败时不显示徽标。
  Future<void> _loadBenefits() async {
    int? couponCount;
    try {
      couponCount = (await _api.getCoupons()).length;
    } on Exception {
      couponCount = null;
    }

    // 成就勋章暂时隐藏，以下计数逻辑保留待后续启用。
    // // 成就接口同时返回已解锁与未解锁条目，这里只统计已解锁数量。
    // Future<int?> safeUnlockedCount() async {
    //   try {
    //     final list = await _api.getAchievements();
    //     return list
    //         .whereType<Map>()
    //         .where((item) {
    //           final map = item.cast<String, dynamic>();
    //           return map['unlocked'] == true ||
    //               map['achieved'] == true ||
    //               map['isUnlocked'] == true;
    //         })
    //         .length;
    //   } on Exception {
    //     return null;
    //   }
    // }

    if (!mounted) return;
    setState(() {
      _couponCount = couponCount;
    });
  }

  /// 礼券徽标文案：数量来自接口，无数据时显示 0 张。
  String? _voucherBadge(SiponAppText text) {
    final count = _couponCount;
    if (count == null) return null;
    return text.vouchersBadgeCount(count);
  }

  // 成就勋章暂时隐藏，以下文案方法保留待后续启用。
  // /// 成就文案：已解锁数量来自接口，无数据时显示 0 枚。
  // String? _achievementTrailing(SiponAppText text) {
  //   final count = _achievementCount;
  //   if (count == null) return null;
  //   return text.achievementsUnlockedCount(count);
  // }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final bottomOverlayInset = widget.bottomOverlayInset;
    final onRecordPressed = widget.onRecordPressed;
    final onLogoutSucceeded = widget.onLogoutSucceeded;

    return Scaffold(
      // 背景显式设为渐变末端同色（白色），保证底部安全区不再露出米白底色条带。
      backgroundColor: Colors.white,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFFFCFC), Colors.white],
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
                        const SizedBox(height: 22),
                        _SectionTitle(text.benefits),
                        const SizedBox(height: 12),
                        _ProfileListCard(
                          rows: [
                            _ProfileListRow(
                              assetPath: ProfilePage._memberAsset,
                              title: text.membership,
                              onTap: () => _showMembershipSheet(context),
                            ),
                            _ProfileListRow(
                              assetPath: ProfilePage._couponAsset,
                              title: text.vouchers,
                              badge: _voucherBadge(text),
                              onTap: () async {
                                await _showCouponList(context);
                                _loadBenefits();
                              },
                            ),
                            // 成就勋章暂时隐藏，保留逻辑待后续启用。
                            // _ProfileListRow(
                            //   assetPath: ProfilePage._achievementAsset,
                            //   title: text.achievements,
                            //   trailingText: _achievementTrailing(text),
                            //   onTap: () async {
                            //     await _showAchievementList(context);
                            //     _loadBenefits();
                            //   },
                            // ),
                          ],
                        ),
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

class _ProfileTopActions extends StatelessWidget {
  const _ProfileTopActions({this.onLogoutSucceeded});

  final VoidCallback? onLogoutSucceeded;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _TopIconButton(
          tooltip: text.messages,
          icon: Icons.notifications_none_rounded,
          showDot: true,
          onPressed: () {},
        ),
        const SizedBox(width: 10),
        _TopIconButton(
          tooltip: text.settings,
          icon: Icons.settings_outlined,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SettingsSupportPage(onLogoutSucceeded: onLogoutSucceeded),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.showDot = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              fixedSize: const Size(34, 34),
              padding: EdgeInsets.zero,
              foregroundColor: const Color(0xFF3A3B42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(icon, size: 25),
          ),
          if (showDot)
            const Positioned(
              right: 7,
              top: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ProfilePage._brand,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 7, height: 7),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.loading,
    required this.onEdit,
    this.onViewPublicProfile,
  });

  final UserProfileData? profile;
  final bool loading;
  final VoidCallback onEdit;

  /// 点击头像区域进入公开主页；为 null（无 id）时不响应点击。
  final VoidCallback? onViewPublicProfile;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final textTheme = Theme.of(context).textTheme;

    // 整块头像+资料区域可点进公开主页；编辑资料按钮保留在右侧，
    // 按钮自身消费点击，不会触发外层跳转。
    return InkWell(
      onTap: onViewPublicProfile,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ProfileAvatar(avatarUrl: profile?.avatarUrl),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading ? '加载中…' : (profile?.name ?? text.profileName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleLarge?.copyWith(
                    color: ProfilePage._ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  profile?.id == null
                      ? text.profileId
                      : 'Sipon ID: ${profile!.id}',
                  style: textTheme.bodySmall?.copyWith(
                    color: ProfilePage._muted,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      '查看我的主页',
                      style: textTheme.bodySmall?.copyWith(
                        color: ProfilePage._brand,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: ProfilePage._brand,
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: loading ? null : onEdit,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB7ABB3),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(64, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text.editProfile, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 17),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SizedBox(
      width: 70,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x269A3D78),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(child: _buildAvatarImage()),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 2,
            child: Container(
              height: 20,
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8BD0),
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33FF80C8),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 8,
                    backgroundColor: Color(0xFFFFD23C),
                    child: Icon(
                      Icons.star_rounded,
                      color: Color(0xFFB12C29),
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    text.badgeTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarImage() {
    final rawUrl = avatarUrl?.trim();
    if (rawUrl == null || rawUrl.isEmpty) {
      return Image.asset(
        ProfilePage._avatarAsset,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      );
    }
    return SiponNetworkImage(
      url: rawUrl,
      fallbackAsset: ProfilePage._avatarAsset,
      alignment: Alignment.topCenter,
      auth: true,
      onError: (error) =>
          debugPrint('Profile avatar image failed: $rawUrl ($error)'),
    );
  }
}

class _QuickEntryCard extends StatefulWidget {
  const _QuickEntryCard({super.key});

  @override
  State<_QuickEntryCard> createState() => _QuickEntryCardState();
}

class _QuickEntryCardState extends State<_QuickEntryCard> {
  final SiponApiService _api = SiponApiService();

  /// 三个入口的计数；为 null 表示尚未加载或加载失败，展示不带数字的文案。
  int? _drankCount;
  int? _wishCount;
  int? _routeCount;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// 分别拉取三类列表的首页来估计计数；任一失败只影响对应入口，互不阻塞。
  Future<void> _loadCounts() async {
    Future<int?> safeCount(Future<List<dynamic>> Function() call) async {
      try {
        return (await call()).length;
      } on Exception {
        return null;
      }
    }

    // 计数时用较大分页，避免条目超过默认 20 条导致数字不准确。
    const countPage = SiponPage(limit: 100);
    final results = await Future.wait([
      safeCount(() => _api.getMyCheckIns(page: countPage)),
      safeCount(() => _api.getWishlistBars(page: countPage)),
      safeCount(() => _api.getMyDrinkingRoutes(page: countPage)),
    ]);
    if (!mounted) return;
    setState(() {
      _drankCount = results[0];
      _wishCount = results[1];
      _routeCount = results[2];
    });
  }

  /// 打开列表弹窗，关闭后重新拉取计数，保证入口数字与弹窗内容一致。
  Future<void> _openList(BuildContext context, ProfileListType type) async {
    await showProfileList(context, type);
    if (mounted) {
      _loadCounts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F9A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: _QuickEntryItem(
                assetPath: ProfilePage._drunkAsset,
                label: _drankCount == null ? '喝过' : '喝过$_drankCount家',
                onTap: () => _openList(context, ProfileListType.drank),
              ),
            ),
            const _VerticalDivider(),
            Expanded(
              child: _QuickEntryItem(
                assetPath: ProfilePage._wishAsset,
                label: _wishCount == null ? '想喝' : '$_wishCount家想喝',
                onTap: () => _openList(context, ProfileListType.wish),
              ),
            ),
            const _VerticalDivider(),
            Expanded(
              child: _QuickEntryItem(
                assetPath: ProfilePage._routeAsset,
                label: _routeCount == null ? '路线' : '$_routeCount条路线',
                onTap: () => _openList(context, ProfileListType.route),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickEntryItem extends StatelessWidget {
  const _QuickEntryItem({
    required this.assetPath,
    required this.label,
    required this.onTap,
  });

  final String assetPath;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(assetPath, width: 32, height: 32),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: ProfilePage._ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum ProfileListType { drank, wish, route }

/// 我的页列表条目：名称、描述、meta 与可选网络封面图。
class _ProfileListEntry {
  const _ProfileListEntry({
    required this.name,
    required this.description,
    required this.meta,
    this.id,
    this.imageUrl,
    this.venue,
    this.isCheckIn = false,
    this.city,
    this.visitedDate,
    this.isPrivate = false,
    this.viewCount,
    this.stops = const [],
    this.routeThumbnails = const [],
  });

  final String name;
  final String description;
  final String meta;

  /// 后端资源 id：打卡 ID、想喝酒吧 ID 或路线 ID。
  final int? id;

  /// 后端返回的封面图（相对或绝对地址）；为空或加载失败时用 [fallbackImagePath]。
  final String? imageUrl;

  /// 解析出的地点信息；喝过/想喝条目用于跳转半屏地图，礼券等无地点列表为 null。
  final MapVenue? venue;

  /// 打卡卡会使用评论标题与地点、时间两行信息布局。
  final bool isCheckIn;
  final String? city;
  final String? visitedDate;

  /// 封面加载失败时的本地兜底素材。
  String get fallbackImagePath => 'assest/首页/图片素材/酒吧1.png';

  /// 路线可见性：仅路线卡片使用。
  final bool isPrivate;
  final int? viewCount;

  /// 路线站点简况（按顺序）；仅路线卡片使用。
  final List<RouteStop> stops;
  final List<String> routeThumbnails;
}

/// 打开喝过/想喝/酒鬼路线列表弹窗，数据源为真实后端接口，列表按页加载。
/// 返回的 Future 在弹窗关闭后完成，便于调用方刷新计数。
Future<void> showProfileList(
  BuildContext context,
  ProfileListType type, {
  SiponApiService? apiService,
}) {
  final api = apiService ?? SiponApiService();
  final (title, loader, emptyText) = switch (type) {
    ProfileListType.drank => (
      '喝过的酒吧',
      (int offset, int limit) =>
          _loadCheckInEntries(api, offset: offset, limit: limit),
      '还没有喝过记录，去打卡第一家酒吧吧',
    ),
    ProfileListType.wish => (
      '想喝的酒吧',
      (int offset, int limit) =>
          _loadWishlistEntries(api, offset: offset, limit: limit),
      '还没有想喝的酒吧，去地图上收藏一家吧',
    ),
    ProfileListType.route => (
      '我的酒鬼路线',
      (int offset, int limit) =>
          _loadRouteEntries(api, offset: offset, limit: limit),
      '还没有酒鬼路线，去规划一条吧',
    ),
  };

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      title: title,
      loader: loader,
      emptyText: emptyText,
      routeStyle: type == ProfileListType.route,
      deleteEntry: switch (type) {
        ProfileListType.drank => api.deleteCheckIn,
        ProfileListType.wish => api.removeWishlistBar,
        ProfileListType.route => api.deleteDrinkingRoute,
      },
    ),
  );
}

/// 从 map 里按候选键读取非空字符串。
String? _pickString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// 从 map 里按候选键读取数字。
num? _pickNum(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value;
    if (value is String) {
      final parsed = num.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// 从 map 里按候选键读取列表。
List<dynamic>? _pickList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) return value;
  }
  return null;
}

/// 从 map 里按候选键读取第一个嵌套 Map（站点里常见 bar/barInfo 等对象）。
Map<String, dynamic>? _pickMapOf(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map) return value.cast<String, dynamic>();
  }
  return null;
}

/// 读取坐标数值：longitude/lng/lon 或 latitude/lat。
double? _pickCoordinate(Map<String, dynamic>? map, {required bool longitude}) {
  if (map == null) return null;
  final keys = longitude
      ? const ['longitude', 'lng', 'lon']
      : const ['latitude', 'lat'];
  return _pickNum(map, keys)?.toDouble();
}

/// 从图集/媒体列表里提取第一个 URL：元素可能是字符串或带 url 字段的对象。
String? _pickFirstUrl(Map<String, dynamic> map, List<String> keys) {
  final list = _pickList(map, keys);
  if (list == null) return null;
  for (final item in list) {
    if (item is String && item.trim().isNotEmpty) return item.trim();
    if (item is Map) {
      final url = _pickString(item.cast<String, dynamic>(), [
        'url',
        'imageUrl',
        'path',
        'src',
        'contentUrl',
      ]);
      if (url != null) return url;
    }
  }
  return null;
}

/// 打卡配图：`mediaIds` 存的是上传 ID，要换成上传内容相对路径才能展示；
/// 没有 `mediaIds` 时回退旧的 `mediaUrls` / `media` / `gallery` 字段。
String? _pickCheckInImageUrl(Map<String, dynamic> map) {
  final mediaId = _pickFirstUrl(map, ['mediaIds']);
  if (mediaId != null) return '/api/uploads/$mediaId/content';
  return _pickFirstUrl(map, ['mediaUrls', 'media', 'gallery']);
}

/// 从喝过/想喝条目的原始 JSON 里解析跳转半屏地图所需的 [MapVenue]。
/// 喝过条目（CheckIn）的酒吧字段可能平铺在顶层，也可能嵌在 bar/barInfo 等对象里；
/// 坐标缺失时以 0 占位，跳转前由 [_openVenueHalfMap] 统一校验。
MapVenue _venueFromEntryMap(Map<String, dynamic> map, {required String name}) {
  final nested = _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']);
  const empty = <String, dynamic>{};
  // 嵌套对象可能不存在，统一用空 map 兜底，便于直接复用宽松取值函数。
  final bar = nested ?? empty;
  final rawTags = _pickList(map, ['tags']) ?? _pickList(bar, ['tags']);
  return MapVenue(
    id:
        (_pickNum(map, ['barId', 'id']) ?? _pickNum(bar, ['barId', 'id']))
            ?.toString() ??
        name,
    name: name,
    longitude:
        _pickCoordinate(map, longitude: true) ??
        _pickCoordinate(nested, longitude: true) ??
        0,
    latitude:
        _pickCoordinate(map, longitude: false) ??
        _pickCoordinate(nested, longitude: false) ??
        0,
    kind: MapVenueKind.fromRaw(
      _pickString(map, ['barSubtype', 'subtype', 'kind', 'type']) ??
          _pickString(bar, ['barSubtype', 'subtype', 'kind', 'type']),
    ),
    rating:
        (_pickNum(map, ['averageRating', 'rating', 'score']) ??
                _pickNum(bar, ['averageRating', 'rating', 'score']))
            ?.toDouble() ??
        0,
    address:
        _pickString(map, ['address']) ?? _pickString(bar, ['address']) ?? '',
    distance: '',
    tags: [
      if (rawTags != null)
        for (final tag in rawTags)
          if (tag != null) tag.toString(),
    ],
    imageAsset: 'assest/首页/图片素材/酒吧1.png',
    imageUrl:
        (map['profileThumbnailUrl'] as String?) ??
        _pickString(map, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
        _pickString(bar, ['imageUrl', 'image', 'cover', 'coverUrl']),
  );
}

/// 点击喝过/想喝条目：坐标有效时打开锁定的半屏地图（[VenueMapHalfPage]），
/// 否则提示暂无位置，与独立详情页点地址的行为一致。
Future<void> _openVenueHalfMap(BuildContext context, MapVenue venue) async {
  final longitude = venue.longitude;
  final latitude = venue.latitude;
  if (!longitude.isFinite ||
      !latitude.isFinite ||
      longitude.abs() > 180 ||
      latitude.abs() > 90 ||
      (longitude == 0 && latitude == 0)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('该地点暂无可用位置'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    return;
  }
  await openVenueMapHalfPage<void>(context, venue);
}

/// ISO 时间截断为 `yyyy-MM-dd` 日期文案。
String _shortDate(String? iso) {
  if (iso == null || iso.length < 10) return '';
  return iso.substring(0, 10);
}

/// 喝过的酒吧：GET /api/users/me/check-ins，元素为 CheckIn 结构，按页拉取。
Future<_ProfileListPage> _loadCheckInEntries(
  SiponApiService api, {
  required int offset,
  required int limit,
}) async {
  final list = await loadProfileBarImages(
    api,
    await api.getMyCheckIns(
      page: SiponPage(limit: limit, offset: offset),
    ),
    checkIns: true,
  );
  final entries = [
    for (final item in list.whereType<Map>())
      () {
        final map = item.cast<String, dynamic>();
        final name = _pickString(map, ['barName', 'name', 'barTitle']);
        if (name == null) return null;
        final city =
            _pickString(map, ['city']) ??
            _pickString(
              _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']) ?? const {},
              ['city'],
            ) ??
            '';
        final date = _shortDate(_pickString(map, ['visitedAt', 'createdAt']));
        final meta = [
          if (city.isNotEmpty) city,
          if (date.isNotEmpty) date,
        ].join(' · ');
        return _ProfileListEntry(
          id: _pickNum(map, ['id'])?.toInt(),
          name: name,
          description: _pickString(map, ['content']) ?? '',
          meta: meta,
          isCheckIn: true,
          city: city.isEmpty ? null : city,
          visitedDate: date.isEmpty ? null : date,
          imageUrl:
              map['profileThumbnailUrl'] as String? ??
              _pickCheckInImageUrl(map),
          venue: _venueFromEntryMap(map, name: name),
        );
      }(),
  ].whereType<_ProfileListEntry>().toList(growable: false);
  // 拉满一页视为还有更多，由弹窗滚动触底继续翻页。
  return _ProfileListPage(items: entries, hasMore: list.length >= limit);
}

/// 想喝的酒吧：GET /api/users/me/wishlist/bars，元素为 Bar 结构，按页拉取。
Future<_ProfileListPage> _loadWishlistEntries(
  SiponApiService api, {
  required int offset,
  required int limit,
}) async {
  final list = await loadProfileBarImages(
    api,
    await api.getWishlistBars(
      page: SiponPage(limit: limit, offset: offset),
    ),
    checkIns: false,
  );
  final entries = [
    for (final item in list.whereType<Map>())
      () {
        final map = item.cast<String, dynamic>();
        final name = _pickString(map, ['name', 'barName', 'title']);
        if (name == null) return null;
        final rating = _pickNum(map, ['averageRating', 'rating', 'score']);
        final meta = [
          ?_pickString(map, ['city']),
          if (rating != null) '${rating.toStringAsFixed(1)} 分',
        ].join(' · ');
        return _ProfileListEntry(
          id:
              (_pickNum(map, ['barId']) ??
                      _pickNum(
                        _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']) ??
                            const {},
                        ['id', 'barId'],
                      ) ??
                      _pickNum(map, ['id']))
                  ?.toInt(),
          name: name,
          description: _pickString(map, ['address', 'description']) ?? '',
          meta: meta,
          imageUrl:
              (map['profileThumbnailUrl'] as String?) ??
              _pickString(map, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
              _pickFirstUrl(map, ['gallery']),
          venue: _venueFromEntryMap(map, name: name),
        );
      }(),
  ].whereType<_ProfileListEntry>().toList(growable: false);
  return _ProfileListPage(items: entries, hasMore: list.length >= limit);
}

/// 我的酒鬼路线：GET /api/users/me/routes，元素为 DrinkingRoute 结构，按页拉取。
/// 站点数取自接口契约的 stops 数组（兜底 barIds/bars）。
Future<_ProfileListPage> _loadRouteEntries(
  SiponApiService api, {
  required int offset,
  required int limit,
}) async {
  final list = await api.getMyDrinkingRoutes(
    page: SiponPage(limit: limit, offset: offset),
  );
  final routes = await Future.wait(
    list.whereType<Map>().map((item) async {
      final map = item.cast<String, dynamic>();
      if (parseRouteStops(map).isNotEmpty) return map;
      final id = _pickNum(map, ['id'])?.toInt();
      if (id == null) return map;
      try {
        final detail = await api.getDrinkingRoute(id);
        if (detail is Map) return {...map, ...detail.cast<String, dynamic>()};
      } on Exception {
        // A missing preview must not hide the route or prevent deletion.
      }
      return map;
    }),
  );
  final barIds = routes
      .expand((map) => parseRouteStops(map).take(3))
      .map((stop) => stop.id)
      .whereType<int>()
      .where((id) => id > 0)
      .toSet();
  final images = await loadProfileBarImages(api, [
    for (final id in barIds) {'id': id},
  ], checkIns: false);
  final thumbnails = <int, String>{
    for (final image in images.whereType<Map>())
      if (image['profileThumbnailUrl'] is String)
        image['id'] as int: image['profileThumbnailUrl'] as String,
  };
  final entries = [
    for (final item in routes)
      () {
        final map = item.cast<String, dynamic>();
        final title = _pickString(map, ['title', 'name']);
        if (title == null) return null;
        final stops = parseRouteStops(map);
        return _ProfileListEntry(
          id: _pickNum(map, ['id'])?.toInt(),
          name: title,
          // 日期仍由服务端保存，但酒鬼路线只表达路线本身，不展示起止日期。
          description: '',
          meta: '${stops.length} 个地点',
          isPrivate:
              _pickString(map, ['visibility'])?.toLowerCase() != 'public',
          viewCount: _pickNum(map, ['viewCount', 'views'])?.toInt(),
          stops: stops,
          routeThumbnails: [
            for (final stop in stops.take(3))
              if (thumbnails[stop.id] != null) thumbnails[stop.id]!,
          ],
        );
      }(),
  ].whereType<_ProfileListEntry>().toList(growable: false);
  return _ProfileListPage(items: entries, hasMore: list.length >= limit);
}

/// 打开「我的礼券」列表弹窗：GET /api/users/me/coupons。
Future<void> _showCouponList(BuildContext context) {
  final api = SiponApiService();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      title: '我的礼券',
      emptyText: '暂无可用礼券',
      // 礼券接口暂不分页，一次性拉取并标记无更多。
      loader: (int _, int _) async {
        final list = await api.getCoupons();
        return _ProfileListPage(
          hasMore: false,
          items: [
            for (final item in list.whereType<Map>())
              () {
                final map = item.cast<String, dynamic>();
                final name = _pickString(map, ['title', 'name', 'couponName']);
                if (name == null) return null;
                final amount = _pickNum(map, ['amount', 'discount', 'value']);
                final validTo = _shortDate(
                  _pickString(map, ['validTo', 'expireAt', 'expiredAt']),
                );
                return _ProfileListEntry(
                  name: name,
                  description:
                      _pickString(map, ['description', 'rule', 'condition']) ??
                      '',
                  meta: [
                    if (amount != null) '¥${amount.toStringAsFixed(0)}',
                    if (validTo.isNotEmpty) '有效期至 $validTo',
                  ].join(' · '),
                );
              }(),
          ].whereType<_ProfileListEntry>().toList(growable: false),
        );
      },
    ),
  );
}

/* 成就勋章暂时隐藏，保留逻辑待后续启用。
/// 打开「成就勋章」列表弹窗：GET /api/users/me/achievements。
Future<void> _showAchievementList(BuildContext context) {
  final api = SiponApiService();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProfileListSheet(
      title: '成就勋章',
      emptyText: '还没有解锁任何成就',
      // 成就接口暂不分页，一次性拉取并标记无更多。
      loader: (int _, int _) async {
        final list = await api.getAchievements();
        return _ProfileListPage(
          hasMore: false,
          items: [
            for (final item in list.whereType<Map>())
              () {
                final map = item.cast<String, dynamic>();
                final name = _pickString(map, ['name', 'title', 'badgeName']);
                if (name == null) return null;
                final unlocked =
                    map['unlocked'] == true ||
                    map['achieved'] == true ||
                    map['isUnlocked'] == true;
                return _ProfileListEntry(
                  name: name,
                  description: _pickString(map, ['description', 'desc']) ?? '',
                  meta: unlocked ? '已解锁' : '未解锁',
                );
              }(),
          ].whereType<_ProfileListEntry>().toList(growable: false),
        );
      },
    ),
  );
}
*/

/// 打开「Sipon 会员」摘要弹窗：GET /api/users/me/membership。
void _showMembershipSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _MembershipSheet(),
  );
}

/// 会员卡摘要：后端字段以真实响应为准，这里把所有基础类型字段逐行展示，
/// 常见键给出中文标签。
class _MembershipSheet extends StatefulWidget {
  const _MembershipSheet();

  @override
  State<_MembershipSheet> createState() => _MembershipSheetState();
}

class _MembershipSheetState extends State<_MembershipSheet> {
  static const _keyLabels = {
    'level': '会员等级',
    'levelName': '会员等级',
    'status': '状态',
    'balance': '余额',
    'points': '积分',
    'integral': '积分',
    'growthValue': '成长值',
    'expireAt': '有效期至',
    'expiredAt': '有效期至',
    'validTo': '有效期至',
    'cardNo': '卡号',
  };

  final SiponApiService _api = SiponApiService();
  Map<String, dynamic>? _membership;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 拉取会员信息；错误统一展示异常文案。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getMembership();
      if (!mounted) return;
      setState(() {
        _membership = data is Map ? data.cast<String, dynamic>() : const {};
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 固定弹窗高度：让加载/空态/数据态高度一致，避免接口返回时 bottom sheet
    // 因内容高度变化重新调整尺寸，弹出时出现“闪一下”。
    final sheetHeight = math.min(
      480.0,
      MediaQuery.of(context).size.height * 0.7,
    );
    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F6F8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D3D8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sipon 会员',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF292B32),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ProfilePage._brand,
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF858991), fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ProfilePage._brand,
                side: const BorderSide(color: ProfilePage._brand),
              ),
            ),
          ],
        ),
      );
    }

    // 只展示基础类型字段，嵌套对象/数组暂不展开。
    final entries = [
      for (final entry in (_membership ?? const {}).entries)
        if (entry.value is! Map && entry.value is! List) entry,
    ];
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text('暂未开通会员', style: TextStyle(color: Color(0xFF858991))),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Color(0xFFE8E4E9)),
      itemBuilder: (_, index) {
        final entry = entries[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _keyLabels[entry.key] ?? entry.key,
                  style: const TextStyle(
                    color: Color(0xFF858991),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${entry.value}',
                style: const TextStyle(
                  color: Color(0xFF292B32),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 个人中心列表的单页数据：条目 + 是否还有下一页。
class _ProfileListPage {
  const _ProfileListPage({required this.items, required this.hasMore});

  final List<_ProfileListEntry> items;
  final bool hasMore;
}

/// 我的页通用列表弹窗：loading / empty / error（带重试）三态齐全，
/// 数据由 [loader] 按页提供，列表触底自动翻页；路线列表用 [routeStyle] 切换卡片样式。
class _ProfileListSheet extends StatefulWidget {
  const _ProfileListSheet({
    required this.title,
    required this.loader,
    required this.emptyText,
    this.routeStyle = false,
    this.deleteEntry,
  });

  final String title;
  final Future<_ProfileListPage> Function(int offset, int limit) loader;
  final String emptyText;
  final bool routeStyle;
  final Future<void> Function(int id)? deleteEntry;

  @override
  State<_ProfileListSheet> createState() => _ProfileListSheetState();
}

class _ProfileListSheetState extends State<_ProfileListSheet> {
  /// 每页条数。
  static const int _pageSize = 20;

  /// 已加载的条目（首屏 + 触底翻页追加）。
  List<_ProfileListEntry> _items = const [];

  bool _loading = true;
  bool _selecting = false;
  bool _deleting = false;
  final Set<int> _selected = {};

  void _toggleSelection(_ProfileListEntry item) {
    final id = item.id;
    if (_deleting || _loadingMore || id == null || id <= 0) return;
    setState(() {
      _selecting = true;
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _deleteSelected() async {
    final deleteEntry = widget.deleteEntry;
    if (_deleting || _selected.isEmpty || deleteEntry == null) return;
    final ids = Set<int>.of(_selected);
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '取消删除',
      barrierColor: const Color(0x660F0910),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curve),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) =>
          _DeleteRecordsDialog(
            count: ids.length,
            name: ids.length == 1
                ? _items.firstWhere((item) => item.id == ids.first).name
                : null,
          ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final deleted = <int>{};
    for (final id in ids) {
      try {
        await deleteEntry(id);
        deleted.add(id);
      } on Exception {
        // Keep failed entries selected so they can be retried.
      }
    }
    if (!mounted) return;
    setState(() {
      _items = _items.where((item) => !deleted.contains(item.id)).toList();
      _selected.removeAll(deleted);
      _deleting = false;
      _selecting = _selected.isNotEmpty;
    });
    final failed = ids.length - deleted.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '已删除 ${deleted.length} 条记录'
              : '已删除 ${deleted.length} 条，$failed 条删除失败，请重试',
        ),
      ),
    );
    if (_items.isEmpty && _hasMore) await _load();
  }

  Widget _selectionActions() {
    final selectable = _items
        .map((item) => item.id)
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    final allSelected =
        selectable.isNotEmpty && _selected.containsAll(selectable);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ProfilePage._brand),
            onPressed: _deleting
                ? null
                : () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(selectable);
                    }
                  }),
            child: Text(allSelected ? '取消全选' : '全选已加载'),
          ),
          const Spacer(),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF85818B),
            ),
            onPressed: _deleting
                ? null
                : () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ProfilePage._brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _deleting || _selected.isEmpty ? null : _deleteSelected,
            child: Text(_deleting ? '删除中…' : '删除 (${_selected.length})'),
          ),
        ],
      ),
    );
  }

  /// 正在翻页加载下一批。
  bool _loadingMore = false;

  /// 是否还有下一页可加载。
  bool _hasMore = true;

  String? _error;

  /// 列表滚动控制器，用于触底自动翻页。
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// 滚动接近底部时自动加载下一页。
  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 200) {
      _loadMore();
    }
  }

  /// 拉取列表第一页；错误统一展示 SiponApiException 文案。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.loader(0, _pageSize);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _hasMore = page.items.isNotEmpty && page.hasMore;
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  /// 触底翻页，追加下一页条目。
  Future<void> _loadMore() async {
    if (_loading || _loadingMore || _selecting || _deleting || !_hasMore) {
      return;
    }

    setState(() => _loadingMore = true);
    try {
      final page = await widget.loader(_items.length, _pageSize);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.items.isNotEmpty && page.hasMore;
        _loadingMore = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        // 翻页失败停止继续尝试，避免触底无限重试。
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 固定弹窗高度：让加载/空态/列表态高度一致，避免数据返回时 bottom sheet
    // 因内容高度变化而重新调整自身尺寸，出现“抖动/跳动”。
    final sheetHeight = math.min(
      620.0,
      MediaQuery.of(context).size.height * 0.8,
    );
    return PopScope(
      canPop: !_deleting,
      child: Container(
        height: sheetHeight,
        decoration: const BoxDecoration(
          color: Color(0xFFF5F6F8),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D3D8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF292B32),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _deleting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (_selecting) _selectionActions(),
                if (!_selecting &&
                    widget.deleteEntry != null &&
                    _items.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '长按记录可多选删除',
                      style: TextStyle(color: Color(0xFF858991), fontSize: 12),
                    ),
                  ),
                Flexible(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ProfilePage._brand,
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF858991), fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ProfilePage._brand,
                side: const BorderSide(color: ProfilePage._brand),
              ),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text(
            widget.emptyText,
            style: const TextStyle(color: Color(0xFF858991), fontSize: 13),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      shrinkWrap: true,
      itemCount:
          _items.length + (!_selecting && (_hasMore || _loadingMore) ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return _ProfileListFooter(
            loading: _loadingMore,
            onLoadMore: _loadMore,
          );
        }
        final item = _items[index];
        return widget.routeStyle
            ? _MockRouteCard(
                item: item,
                index: index,
                selecting: _selecting,
                selected: _selected.contains(item.id),
                onLongPress: _loadingMore || _deleting
                    ? null
                    : () => _toggleSelection(item),
                onTap: _deleting
                    ? null
                    : _selecting
                    ? () => _toggleSelection(item)
                    : () => _showRouteDetail(context, item),
              )
            : _MockListCard(
                item: item,
                selecting: _selecting,
                selected: _selected.contains(item.id),
                onLongPress:
                    widget.deleteEntry == null || _loadingMore || _deleting
                    ? null
                    : () => _toggleSelection(item),
                onOpenMap: _deleting
                    ? null
                    : _selecting
                    ? () => _toggleSelection(item)
                    : item.venue == null
                    ? null
                    : () => _openVenueHalfMap(context, item.venue!),
              );
      },
    );
  }
}

/// 个人中心列表弹窗的尾部：加载中显示转圈，空闲时可点击手动翻页。
class _ProfileListFooter extends StatelessWidget {
  const _ProfileListFooter({required this.loading, required this.onLoadMore});

  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: onLoadMore,
                style: TextButton.styleFrom(
                  foregroundColor: ProfilePage._brand,
                ),
                child: const Text(
                  '加载更多',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
      ),
    );
  }
}

/// 条目封面图：有网络图先用网络图，失败或没有就退回本地资产。
Widget _entryImage(
  _ProfileListEntry item, {
  required double width,
  required double height,
}) {
  final url = item.imageUrl;
  if (url != null && url.isNotEmpty) {
    return SiponNetworkImage(
      url: url,
      fallbackAsset: item.fallbackImagePath,
      width: width,
      height: height,
    );
  }
  return Image.asset(
    item.fallbackImagePath,
    width: width,
    height: height,
    fit: BoxFit.cover,
  );
}

class _DeleteRecordsDialog extends StatelessWidget {
  const _DeleteRecordsDialog({required this.count, this.name});
  final int count;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFF9EDF4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: ProfilePage._brand,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '删除 $count 条记录？',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF29232D),
                ),
              ),
              const SizedBox(height: 10),
              if (name != null) ...[
                Text(
                  name!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF625668),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              const Text(
                '删除后无法恢复，请确认后再操作。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xFF938995),
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: const Color(0xFFF4F2F5),
                        foregroundColor: const Color(0xFF625668),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: ProfilePage._brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MockListCard extends StatefulWidget {
  const _MockListCard({
    required this.item,
    this.onOpenMap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;
  final _ProfileListEntry item;

  /// 点击条目打开半屏地图；无地点的列表（如礼券）为 null，整卡不响应。
  final VoidCallback? onOpenMap;

  @override
  State<_MockListCard> createState() => _MockListCardState();
}

class _MockListCardState extends State<_MockListCard> {
  bool _pressed = false;
  _ProfileListEntry get item => widget.item;
  bool get selecting => widget.selecting;
  bool get selected => widget.selected;
  VoidCallback? get onOpenMap => widget.onOpenMap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = Duration(milliseconds: reduceMotion ? 0 : 180);
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: onOpenMap,
        onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                setState(() => _pressed = false);
                widget.onLongPress!();
              },
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF5FB) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? ProfilePage._brand.withValues(alpha: 0.55)
                  : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              if (selected || _pressed)
                BoxShadow(
                  color: ProfilePage._brand.withValues(alpha: 0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _entryImage(item, width: 88, height: 88),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: item.isCheckIn
                    ? _CheckInListDetails(item: item)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF858991),
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.meta,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9A3D78),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
              if (selecting)
                Semantics(
                  checked: selected,
                  label: '选择 ${item.name}',
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: duration,
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? ProfilePage._brand : Colors.white,
                          border: Border.all(
                            color: selected
                                ? ProfilePage._brand
                                : const Color(0xFFD9D1DC),
                            width: 1.5,
                          ),
                        ),
                        child: AnimatedSwitcher(
                          duration: duration,
                          child: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  key: ValueKey(true),
                                  size: 17,
                                  color: Colors.white,
                                )
                              : const SizedBox.shrink(key: ValueKey(false)),
                        ),
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  // 箭头与整卡同行为；无地点列表保持原先"可点无操作"，避免变灰。
                  onPressed: onOpenMap ?? () {},
                  icon: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Color(0xFF9A3D78),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckInListDetails extends StatelessWidget {
  const _CheckInListDetails({required this.item});

  final _ProfileListEntry item;

  @override
  Widget build(BuildContext context) {
    final review = item.description.trim();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          review.isEmpty ? item.name : review,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w800,
            color: ProfilePage._ink,
          ),
        ),
        const SizedBox(height: 8),
        _CheckInMetaLine(
          icon: Icons.location_on_outlined,
          text: [
            if (item.city?.isNotEmpty == true) item.city!,
            item.name,
          ].join(' · '),
        ),
        const SizedBox(height: 4),
        _CheckInMetaLine(
          icon: Icons.access_time_rounded,
          text: item.visitedDate ?? '日期待补充',
        ),
      ],
    );
  }
}

class _CheckInMetaLine extends StatelessWidget {
  const _CheckInMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF9A3D78)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF79747C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MockRouteCard extends StatefulWidget {
  const _MockRouteCard({
    required this.item,
    required this.index,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  final _ProfileListEntry item;
  final int index;

  @override
  State<_MockRouteCard> createState() => _MockRouteCardState();
}

class _MockRouteCardState extends State<_MockRouteCard> {
  bool _pressed = false;
  _ProfileListEntry get item => widget.item;
  int get index => widget.index;

  @override
  Widget build(BuildContext context) {
    final isPrivate = item.isPrivate;
    const routeColors = [
      Color(0xFFFFE6B8), // 杏桃
      Color(0xFFDDE5FF), // 雾蓝
      Color(0xFFE3F2E4), // 鼠尾草绿
      Color(0xFFF8DFE8), // 玫瑰粉
      Color(0xFFE9E0F7), // 薰衣草紫
      Color(0xFFFFE7D6), // 蜜桃橘
      Color(0xFFDDF0F0), // 薄荷青
    ];
    final backgroundColor = routeColors[index % routeColors.length];
    final routeImages = item.routeThumbnails;
    final duration = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
    );
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                setState(() => _pressed = false);
                widget.onLongPress!();
              },
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 144,
          child: Material(
            color: widget.selected ? const Color(0xFFF9E8F4) : backgroundColor,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 112, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          item.description,
                          style: const TextStyle(
                            color: Color(0xFF79747C),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        item.meta,
                        style: const TextStyle(
                          color: Color(0xFF79747C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 13,
                  right: 14,
                  child: widget.selecting
                      ? AnimatedContainer(
                          duration: duration,
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.selected
                                ? ProfilePage._brand
                                : Colors.white,
                            border: Border.all(
                              color: widget.selected
                                  ? ProfilePage._brand
                                  : const Color(0xFFD9D1DC),
                            ),
                          ),
                          child: widget.selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPrivate
                                  ? Icons.lock_outline_rounded
                                  : Icons.public_rounded,
                              size: 15,
                              color: const Color(0xFF7B7580),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.visibility_outlined,
                              size: 16,
                              color: Color(0xFF7B7580),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${item.viewCount ?? 0}',
                              style: const TextStyle(
                                color: Color(0xFF7B7580),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                ),
                Positioned(
                  right: 12,
                  bottom: 6,
                  child: SizedBox(
                    width: 112,
                    height: 76,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (routeImages.isEmpty)
                          const Center(
                            child: Icon(
                              Icons.route_rounded,
                              size: 44,
                              color: Color(0xFFAC9EAD),
                            ),
                          ),
                        for (
                          var imageIndex = 0;
                          imageIndex < routeImages.length;
                          imageIndex++
                        )
                          Positioned(
                            right: imageIndex * 16.0,
                            bottom: imageIndex * 5.0,
                            child: Transform.rotate(
                              angle: (imageIndex - 1) * 0.10,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 76,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      width: 2,
                                    ),
                                  ),
                                  child: SiponNetworkImage(
                                    url: routeImages[imageIndex],
                                    fit: BoxFit.cover,
                                    fallbackWidget: const ColoredBox(
                                      color: Color(0xFFF1ECF1),
                                      child: Icon(
                                        Icons.local_bar_outlined,
                                        color: Color(0xFFAC9EAD),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
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

/// 点击路线卡片进入路线详情地图页：先展示列表接口已带的数据，
/// 地图页内再拉取 GET /api/routes/{id} 渲染各站点并补齐缺失坐标。
void _showRouteDetail(BuildContext context, _ProfileListEntry item) {
  final routeId = item.id;
  if (routeId == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RouteDetailMapPage(
        routeId: routeId,
        title: item.name,
        subtitle: item.description,
        previewStops: item.stops,
      ),
    ),
  );
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: const Color(0xFFF6F1F4));
  }
}

class _BudgetCard extends StatefulWidget {
  const _BudgetCard({required this.onRecordPressed});

  final VoidCallback? onRecordPressed;

  @override
  State<_BudgetCard> createState() => _BudgetCardState();
}

class _BudgetCardState extends State<_BudgetCard> {
  final DrinkBudgetStore _store = DrinkBudgetStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStoreChanged);
    // 账本卡片进入时先读本地缓存，再后台与后端做一次全量合并。
    _store.ensureLoaded().then((_) => _store.ensureSynced());
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _openStickerCalendar(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DrinkStickerCalendarPage(onRecordPressed: widget.onRecordPressed),
      ),
    );
  }

  void _showRecords(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BudgetBillPage(onDeleted: _onStoreChanged),
      ),
    );
  }

  Future<void> _editBudget(BuildContext context) async {
    final text = SiponLanguageScope.textOf(context);
    final controller = TextEditingController(
      text: _store.monthlyBudget.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            text.editBudget,
            style: const TextStyle(
              color: ProfilePage._ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: text.enterBudget,
              hintStyle: const TextStyle(
                color: ProfilePage._muted,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: const Color(0xFFFBF8FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(foregroundColor: ProfilePage._muted),
              child: Text(text.cancel),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(controller.text.trim());
                if (value == null || value < 0) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              style: FilledButton.styleFrom(
                backgroundColor: ProfilePage._brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(text.confirm),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await _store.setMonthlyBudget(result);
      if (context.mounted) {
        _showProfileMessage(context, text.budgetUpdated);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final monthExpense = _store.currentMonthExpense;
    final remaining = _store.remaining;
    final delta = _store.monthDeltaRatio;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x149A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: ProfilePage._brand,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(
                    Icons.currency_yen_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    text.drinkBudget,
                    style: const TextStyle(
                      color: ProfilePage._ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: widget.onRecordPressed,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(76, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color(0xFFFFEDF7),
                    foregroundColor: ProfilePage._brand,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: Text(
                    text.addRecord,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 5,
                  child: _MonthlyExpense(
                    expense: monthExpense,
                    delta: delta,
                    onTap: () => _showRecords(context),
                  ),
                ),
                Container(
                  width: 1,
                  height: 74,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: ProfilePage._line,
                ),
                Expanded(
                  flex: 4,
                  child: _BudgetStats(
                    budget: _store.monthlyBudget,
                    remaining: remaining,
                    onEditBudget: () => _editBudget(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: ProfilePage._line),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _BudgetShortcut(
                    icon: Icons.calendar_month_outlined,
                    label: text.t('月历'),
                    onTap: () => _openStickerCalendar(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BudgetShortcut(
                    icon: Icons.bar_chart_rounded,
                    label: text.t('统计'),
                    onTap: () => _showRecords(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetShortcut extends StatelessWidget {
  const _BudgetShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFF7FB),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: ProfilePage._brand),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: ProfilePage._ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyExpense extends StatelessWidget {
  const _MonthlyExpense({
    required this.expense,
    required this.delta,
    this.onTap,
  });

  final double expense;
  final double delta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    final deltaText = delta == 0
        ? text.noComparison
        : '${delta > 0 ? '↗' : '↘'} ${(delta * 100).abs().toStringAsFixed(0)}%';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  text.monthlySpend,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ProfilePage._ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.visibility_outlined,
                size: 13,
                color: ProfilePage._muted,
              ),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              _formatCurrency(expense),
              style: const TextStyle(
                color: ProfilePage._brand,
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text.monthlyDeltaPrefix),
                TextSpan(
                  text: deltaText,
                  style: TextStyle(
                    color: delta >= 0
                        ? ProfilePage._brand
                        : const Color(0xFF3FA66A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              color: ProfilePage._muted,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetStats extends StatelessWidget {
  const _BudgetStats({
    required this.budget,
    required this.remaining,
    required this.onEditBudget,
  });

  final double budget;
  final double remaining;
  final VoidCallback onEditBudget;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onEditBudget,
          borderRadius: BorderRadius.circular(10),
          child: _BudgetStat(
            label: text.monthlyBudget,
            value: _formatCurrency(budget),
            trailing: const Icon(
              Icons.edit_outlined,
              size: 13,
              color: ProfilePage._muted,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 9),
          child: Divider(height: 1, color: ProfilePage._line),
        ),
        _BudgetStat(
          label: text.remainingBudget,
          value: _formatCurrency(remaining),
        ),
      ],
    );
  }
}

class _BudgetStat extends StatelessWidget {
  const _BudgetStat({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFC4BBC2),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    color: ProfilePage._brand,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing ?? const SizedBox.shrink(),
      ],
    );
  }
}

class BudgetBillPage extends StatelessWidget {
  const BudgetBillPage({super.key, this.onDeleted});

  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // 底部不进安全区：内容与背景延伸到屏幕底部，小白条区域由
        // 列表自身的 padding 预留，避免底部留出一段不参与滚动的白边。
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _BudgetBillBody(onDeleted: onDeleted),
          ),
        ),
      ),
    );
  }
}

class _BudgetBillBody extends StatefulWidget {
  const _BudgetBillBody({this.onDeleted});

  final VoidCallback? onDeleted;

  @override
  State<_BudgetBillBody> createState() => _BudgetBillBodyState();
}

class _BudgetBillBodyState extends State<_BudgetBillBody> {
  static const _chartColors = [
    Color(0xFF9A3D78),
    Color(0xFFEE8E51),
    Color(0xFF477BC8),
    Color(0xFF3FA66A),
    Color(0xFFC2A43A),
  ];

  final DrinkBudgetStore _store = DrinkBudgetStore.instance;
  late DateTime _selectedDate;
  _BillPeriod _period = _BillPeriod.month;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _store.addListener(_onStoreChanged);
    // 进入账单页时与后端对齐一次，保证跨设备数据一致。
    _store.ensureLoaded().then((_) => _store.ensureSynced());
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (_) => _BillDatePickerDialog(
        initialDate: _selectedDate,
        records: _store.records,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  String _formatSelectedDate(SiponAppText text) {
    final date = _selectedDate;
    if (_period == _BillPeriod.month) {
      return text.isZh
          ? '${date.year}年${date.month}月'
          : '${date.month}/${date.year}';
    }

    if (_period == _BillPeriod.week) {
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      if (text.isZh) {
        if (weekStart.month == weekEnd.month) {
          return '${weekStart.year}年${weekStart.month}月${weekStart.day}日至${weekEnd.day}日';
        }
        return '${weekStart.year}年${weekStart.month}月${weekStart.day}日至${weekEnd.month}月${weekEnd.day}日';
      }
      return '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
    }

    if (text.isZh) {
      return '${date.year}年${date.month}月${date.day}日';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatDate(DateTime date, SiponAppText text) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      return text.t('今天');
    }

    if (text.isZh) {
      return '${date.month}月${date.day}日';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  List<DrinkBudgetRecord> _recordsForPeriod() {
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final month = DrinkBudgetMonth(_selectedDate.year, _selectedDate.month);
    final records = _store.records.where((record) {
      switch (_period) {
        case _BillPeriod.day:
          return record.date.year == dayStart.year &&
              record.date.month == dayStart.month &&
              record.date.day == dayStart.day;
        case _BillPeriod.week:
          return !record.date.isBefore(weekStart) &&
              record.date.isBefore(weekEnd);
        case _BillPeriod.month:
          return month.contains(record.date);
      }
    }).toList();
    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  Map<String, double> _categoryExpenses(List<DrinkBudgetRecord> records) {
    final expenses = <String, double>{};
    for (final record in records) {
      expenses.update(
        record.drinkType,
        (value) => value + record.amount,
        ifAbsent: () => record.amount,
      );
    }
    final sorted = expenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  List<_DayExpense> _dailyExpenses(List<DrinkBudgetRecord> records) {
    final expenses = <DateTime, double>{};
    for (final record in records) {
      final day = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      expenses.update(
        day,
        (value) => value + record.amount,
        ifAbsent: () => record.amount,
      );
    }
    final days = expenses.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return days
        .skip(math.max(0, days.length - 7))
        .map((entry) => _DayExpense(entry.key, entry.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final records = _recordsForPeriod();
    final total = records.fold<double>(0, (sum, record) => sum + record.amount);
    final categoryExpenses = _categoryExpenses(records);
    final dailyExpenses = _dailyExpenses(records);
    final budgetProgress = _store.monthlyBudget <= 0
        ? 0.0
        : (total / _store.monthlyBudget).clamp(0.0, 1.0);

    final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      // 底部留白放在滚动内容内部（见最后一个 sliver），而不是包住
      // CustomScrollView：视口延伸到屏幕底部，滚动时内容能自然滑入
      // 小白条区域，不再留出一条不参与滚动的白边。
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: text.back,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      Text(
                        text.t('统计'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: text.t('更多'),
                          onPressed: () {},
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 0),
                Center(
                  child: Transform.translate(
                    offset: const Offset(8, 0),
                    child: TextButton(
                      onPressed: _pickDate,
                      style: TextButton.styleFrom(
                        foregroundColor: ProfilePage._ink,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatSelectedDate(text),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(width: 1),
                          const Icon(Icons.arrow_drop_down_rounded, size: 23),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _BillPeriodSelector(
                  period: _period,
                  text: text,
                  onChanged: (period) => setState(() => _period = period),
                ),
                const SizedBox(height: 16),
                DrinkStickerGravityPool(
                  records: records,
                  height: 220,
                  onStickerTap: (record) => showModalBottomSheet<void>(
                    context: context,
                    useSafeArea: true,
                    showDragHandle: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                    ),
                    builder: (_) => _BudgetRecordDetailSheet(
                      record: record,
                      dateText: _formatDate(record.date, text),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _BillSummary(
                  headline: '${_period.label(text)}${text.t('支出')}',
                  total: total,
                  budget: _store.monthlyBudget,
                  progress: budgetProgress,
                  recordCount: records.length,
                  activeDays: _dailyExpenses(records).length,
                ),
                const SizedBox(height: 24),
                Text(
                  text.t('消费趋势'),
                  style: const TextStyle(
                    color: ProfilePage._ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text.t('最近 7 个有消费记录的日期'),
                  style: const TextStyle(
                    color: ProfilePage._muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                _BillBarChart(data: dailyExpenses),
                const SizedBox(height: 26),
                Text(
                  text.t('消费构成'),
                  style: const TextStyle(
                    color: ProfilePage._ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                _BillCategoryChart(
                  expenses: categoryExpenses,
                  colors: _chartColors,
                  text: text,
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_period.label(text)}${text.t('明细')}',
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      '${records.length}${text.t('笔')}',
                      style: const TextStyle(
                        color: ProfilePage._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          if (records.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 42),
                child: Center(
                  child: Text(
                    _period == _BillPeriod.day
                        ? text.t('当天还没有记账记录')
                        : text.noRecords,
                    style: const TextStyle(
                      color: ProfilePage._muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: records.length,
              itemBuilder: (_, index) {
                final record = records[index];
                return _BudgetRecordTile(
                  record: record,
                  dateText: _formatDate(record.date, text),
                  onDeleted: () async {
                    await _store.removeRecord(record.id);
                    widget.onDeleted?.call();
                  },
                );
              },
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: ProfilePage._line),
            ),
          // 尾部留白 = 原有间距 32 + 底部安全区，保证静止时明细不被
          // 小白条遮挡；滚动中该区域随内容一起滑入滑出。
          SliverToBoxAdapter(child: SizedBox(height: 32 + bottomSafeInset)),
        ],
      ),
    );
  }
}

class _BillDatePickerDialog extends StatefulWidget {
  const _BillDatePickerDialog({
    required this.initialDate,
    required this.records,
  });

  final DateTime initialDate;
  final List<DrinkBudgetRecord> records;

  @override
  State<_BillDatePickerDialog> createState() => _BillDatePickerDialogState();
}

class _BillDatePickerDialogState extends State<_BillDatePickerDialog> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _month = DateTime(_selected.year, _selected.month);
  }

  bool _hasRecord(int day) {
    return widget.records.any(
      (record) =>
          record.date.year == _month.year &&
          record.date.month == _month.month &&
          record.date.day == day,
    );
  }

  void _changeMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    if (next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) {
      return;
    }
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_month.year}年${_month.month}月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ProfilePage._ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: ProfilePage._muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: firstWeekday - 1 + days,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 42,
              ),
              itemBuilder: (_, index) {
                if (index < firstWeekday - 1) {
                  return const SizedBox.shrink();
                }
                final day = index - firstWeekday + 2;
                final date = DateTime(_month.year, _month.month, day);
                final selected =
                    date.year == _selected.year &&
                    date.month == _selected.month &&
                    date.day == _selected.day;
                final hasRecord = _hasRecord(day);
                return InkWell(
                  onTap: () => Navigator.of(context).pop(date),
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? ProfilePage._brand : null,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: selected ? Colors.white : ProfilePage._ink,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: hasRecord
                              ? ProfilePage._brand
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BillPeriod { day, week, month }

extension on _BillPeriod {
  String label(SiponAppText text) {
    switch (this) {
      case _BillPeriod.day:
        return text.t('当日');
      case _BillPeriod.week:
        return text.t('本周');
      case _BillPeriod.month:
        return text.t('本月');
    }
  }
}

class _BillPeriodSelector extends StatelessWidget {
  const _BillPeriodSelector({
    required this.period,
    required this.text,
    required this.onChanged,
  });

  final _BillPeriod period;
  final SiponAppText text;
  final ValueChanged<_BillPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          for (final option in _BillPeriod.values)
            Expanded(
              child: _BillPeriodOption(
                label: switch (option) {
                  _BillPeriod.day => text.t('日'),
                  _BillPeriod.week => text.t('周'),
                  _BillPeriod.month => text.t('月'),
                },
                selected: period == option,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _BillPeriodOption extends StatelessWidget {
  const _BillPeriodOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: ProfilePage._ink,
                fontSize: 17,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BillSummary extends StatelessWidget {
  const _BillSummary({
    required this.headline,
    required this.total,
    required this.budget,
    required this.progress,
    required this.recordCount,
    required this.activeDays,
  });

  final String headline;
  final double total;
  final double budget;
  final double progress;
  final int recordCount;
  final int activeDays;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final average = activeDays == 0 ? 0.0 : total / activeDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF2DFEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              color: ProfilePage._muted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCurrency(total),
            style: const TextStyle(
              color: ProfilePage._brand,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFF2E6ED),
              valueColor: const AlwaysStoppedAnimation(ProfilePage._brand),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${text.t('预算')} ${_formatCurrency(budget)}  ·  ${text.t('剩余')} ${_formatCurrency(budget - total)}',
            style: const TextStyle(
              color: ProfilePage._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF0E3EB)),
          ),
          Row(
            children: [
              Expanded(
                child: _BillMetric(
                  label: text.t('记账笔数'),
                  value: '$recordCount',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: const Color(0xFFF0E3EB),
              ),
              Expanded(
                child: _BillMetric(label: text.t('消费天数'), value: '$activeDays'),
              ),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: const Color(0xFFF0E3EB),
              ),
              Expanded(
                child: _BillMetric(
                  label: text.t('日均消费'),
                  value: _formatCurrency(average),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillMetric extends StatelessWidget {
  const _BillMetric({required this.label, required this.value});

  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ProfilePage._muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: ProfilePage._ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _DayExpense {
  const _DayExpense(this.date, this.amount);

  final DateTime date;
  final double amount;
}

class _BillBarChart extends StatelessWidget {
  const _BillBarChart({required this.data});

  final List<_DayExpense> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _BillChartEmpty();
    }
    final highest = data.fold<double>(
      0,
      (value, item) => math.max(value, item.amount),
    );
    return SizedBox(
      height: 156,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final item in data)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Tooltip(
                          message: _formatCurrency(item.amount),
                          child: Container(
                            width: 18,
                            height: math.max(8, 100 * item.amount / highest),
                            decoration: BoxDecoration(
                              color: ProfilePage._brand,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item.date.day}',
                      style: const TextStyle(
                        color: ProfilePage._muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BillCategoryChart extends StatelessWidget {
  const _BillCategoryChart({
    required this.expenses,
    required this.colors,
    required this.text,
  });

  final Map<String, double> expenses;
  final List<Color> colors;
  final SiponAppText text;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return const _BillChartEmpty();
    }
    final total = expenses.values.fold<double>(0, (sum, value) => sum + value);
    final entries = expenses.entries.toList();
    if (entries.length > colors.length) {
      final otherTotal = entries
          .skip(colors.length - 1)
          .fold<double>(0, (sum, entry) => sum + entry.value);
      entries
        ..removeRange(colors.length - 1, entries.length)
        ..add(MapEntry('其他', otherTotal));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          size: const Size(116, 116),
          painter: _CategoryPiePainter(
            values: entries.map((entry) => entry.value).toList(),
            colors: colors,
          ),
          child: SizedBox(
            width: 116,
            height: 116,
            child: Center(
              child: Text(
                _formatCurrency(total),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ProfilePage._ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (var index = 0; index < entries.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors[index % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          text.t(entries[index].key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ProfilePage._ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Text(
                        '${(entries[index].value / total * 100).round()}%',
                        style: const TextStyle(
                          color: ProfilePage._muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BillChartEmpty extends StatelessWidget {
  const _BillChartEmpty();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Container(
      height: 116,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.t('暂无统计数据'),
        style: const TextStyle(
          color: ProfilePage._muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CategoryPiePainter extends CustomPainter {
  const _CategoryPiePainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) {
      return;
    }
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      paint.color = colors[index % colors.length];
      canvas.drawArc(rect.deflate(9), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

class _BudgetRecordTile extends StatelessWidget {
  const _BudgetRecordTile({
    required this.record,
    required this.dateText,
    required this.onDeleted,
  });

  final DrinkBudgetRecord record;
  final String dateText;
  final VoidCallback onDeleted;

  String _formatFullDate(DateTime date, SiponAppText text) {
    if (text.isZh) {
      return '${date.year}年${date.month}月${date.day}日';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showDetail(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _BudgetRecordDetailSheet(
        record: record,
        dateText: _formatFullDate(record.date, text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              DrinkSticker(record: record, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.t(record.drinkType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfilePage._ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${text.t(record.place)} · $dateText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfilePage._muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatCurrency(record.amount),
                style: const TextStyle(
                  color: ProfilePage._brand,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onDeleted,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFC7C1C6),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 28),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetRecordDetailSheet extends StatelessWidget {
  const _BudgetRecordDetailSheet({
    required this.record,
    required this.dateText,
  });

  final DrinkBudgetRecord record;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final note = record.note.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DrinkSticker(record: record, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.t('记录详情'),
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text.t('本笔记账'),
                        style: const TextStyle(
                          color: ProfilePage._muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatCurrency(record.amount),
                  style: const TextStyle(
                    color: ProfilePage._brand,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _RecordDetailRow(
              label: text.t('酒款'),
              value: text.t(record.drinkType),
            ),
            _RecordDetailRow(label: text.t('地点'), value: text.t(record.place)),
            _RecordDetailRow(label: text.t('日期'), value: dateText),
            _RecordDetailRow(
              label: text.t('花费'),
              value: _formatCurrency(record.amount),
            ),
            _RecordDetailRow(
              label: text.t('杯数'),
              value: '${record.cups} ${text.t('杯')}',
            ),
            _RecordDetailRow(
              label: text.t('评分'),
              value: record.rating > 0 ? '${record.rating}/5' : '-',
            ),
            _RecordDetailRow(
              label: text.t('备注'),
              value: note.isEmpty ? '-' : note,
              alignTop: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordDetailRow extends StatelessWidget {
  const _RecordDetailRow({
    required this.label,
    required this.value,
    this.alignTop = false,
  });

  final String label;
  final String value;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: alignTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                color: ProfilePage._muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: ProfilePage._ink,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF5D565C),
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}

class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index != rows.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 42),
                child: Divider(height: 1, color: ProfilePage._line),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileListRow extends StatelessWidget {
  const _ProfileListRow({
    required this.assetPath,
    required this.title,
    this.badge,
    // 成就勋章暂时隐藏，trailingText 保留待后续启用。
    // this.trailingText,
    this.onTap,
  });

  final String assetPath;
  final String title;
  final String? badge;
  // final String? trailingText;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Image.asset(assetPath, width: 26, height: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: ProfilePage._ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: ProfilePage._brand,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            // 成就勋章暂时隐藏，trailingText 渲染保留待后续启用。
            // if (trailingText != null)
            //   Text(
            //     trailingText!,
            //     style: const TextStyle(
            //       color: ProfilePage._brand,
            //       fontSize: 10,
            //       fontWeight: FontWeight.w700,
            //       letterSpacing: 0,
            //     ),
            //   ),
            const SizedBox(width: 7),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFC7C1C6),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
