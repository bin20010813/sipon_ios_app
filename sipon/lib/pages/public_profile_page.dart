import 'package:flutter/material.dart';

import '../services/drink_budget_store.dart';
import '../services/map/map_models.dart';
import '../services/sipon_api_config.dart';
import '../services/sipon_api_service.dart';
import '../services/user_profile_data.dart';
import 'drink_sticker_calendar_page.dart';
import 'route_detail_map_page.dart';
import 'venue_map_half_page.dart';

/// 用户公开主页：
/// - 顶部不设「用户主页」标题，头像 + 资料卡即页头；
/// - 编辑资料里的内容（用户名 / 城市 / 简介 / ID）以小标签排在头像下方；
/// - 本人主页下方以两列瀑布流展示动态：喝过打卡、想喝、酒鬼路线、
///   打卡时写的点评、记账喝酒记录（金额私密，只展示喝酒本身）。
class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  final int userId;
  final bool isCurrentUser;

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const String _fallbackCover = 'assest/首页/图片素材/酒吧1.png';

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _api = SiponApiService();
  UserProfileData? _profile;
  Object? _error;
  bool _loading = true;
  bool _updatingFollow = false;

  /// 动态时间线数据；仅本人主页加载（他人动态暂无公开接口）。
  List<_Moment> _moments = const [];
  bool _momentsLoading = false;

  /// 统计计数：overview 未返回时用动态列表长度兜底（与「我的」页口径一致）。
  int? _checkInCount;
  int? _wishCount;
  int? _routeCount;

  /// 记账喝酒次数（本地账本），仅本人主页展示。
  int? _drinkCount;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.isCurrentUser) _loadMoments();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 本人主页直接用 /users/me：与编辑资料（PATCH /users/me）同一数据源，
      // 保证编辑保存后主页立即展示最新值；公开接口 /users/{id}/profile
      // 可能存在缓存或字段同步延迟。他人主页只能走公开接口。
      final response = widget.isCurrentUser
          ? await _api.getMyProfile()
          : await _api.getUserProfile(widget.userId);
      if (mounted) {
        setState(() => _profile = UserProfileData.fromJson(response));
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 拉动态：打卡/想喝/路线各取一页，记账读本地账本（已与后端同步），
  /// 之后按时间倒序合并；单项失败不影响其余动态展示。
  Future<void> _loadMoments() async {
    setState(() => _momentsLoading = true);
    const page = SiponPage(limit: 50);
    final results = await Future.wait([
      _safe(() => _api.getMyCheckIns(page: page)),
      _safe(() => _api.getWishlistBars(page: page)),
      _safe(() => _api.getMyDrinkingRoutes(page: page)),
    ]);

    final store = DrinkBudgetStore.instance;
    List<DrinkBudgetRecord> records = const [];
    try {
      await store.ensureLoaded();
      await store.ensureSynced();
      records = store.records;
    } on Exception {
      // 账本不可用时动态流里少一类卡片即可。
    }

    final checkIns = (results[0] ?? const []).whereType<Map>().toList();
    final wishes = (results[1] ?? const []).whereType<Map>().toList();
    final routes = (results[2] ?? const []).whereType<Map>().toList();

    final moments = <_Moment>[
      for (final item in checkIns)
        ..._momentsFromCheckIn(item.cast<String, dynamic>()),
      for (final item in wishes) ?_momentFromWishlist(item.cast<String, dynamic>()),
      for (final item in routes) ?_momentFromRoute(item.cast<String, dynamic>()),
      for (final record in records) _momentFromDrinkRecord(record),
    ];
    moments.sort((a, b) {
      final aTime = a.time;
      final bTime = b.time;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    if (!mounted) return;
    setState(() {
      _moments = moments;
      _momentsLoading = false;
      _checkInCount = checkIns.length;
      _wishCount = wishes.length;
      _routeCount = routes.length;
      _drinkCount = records.length;
    });
  }

  Future<List<dynamic>?> _safe(Future<List<dynamic>> Function() call) async {
    try {
      return await call();
    } on Exception {
      return null;
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _updatingFollow || widget.isCurrentUser) return;
    setState(() => _updatingFollow = true);
    try {
      if (profile.isFollowing == true) {
        await _api.unfollowUser(widget.userId);
      } else {
        await _api.followUser(widget.userId);
      }
      await _load();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _updatingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // 需求：不展示「用户主页」标题，仅保留返回按钮。
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(''),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PublicProfilePage._brand,
              ),
            )
          : _error != null || _profile == null
          ? _ProfileLoadError(onRetry: _load)
          : RefreshIndicator(
              color: PublicProfilePage._brand,
              onRefresh: () async {
                await _load();
                if (widget.isCurrentUser) await _loadMoments();
              },
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _ProfileHeaderSection(
                      profile: _profile!,
                      isCurrentUser: widget.isCurrentUser,
                      updatingFollow: _updatingFollow,
                      onFollow: _toggleFollow,
                      checkInCount: _checkInCount,
                      wishCount: _wishCount,
                      routeCount: _routeCount,
                      drinkCount: _drinkCount,
                    ),
                  ),
                  if (widget.isCurrentUser)
                    _MomentsSection(
                      moments: _moments,
                      loading: _momentsLoading,
                      onOpenVenue: _openVenueHalfMap,
                      onOpenRoute: _openRouteDetail,
                      onOpenDrinkCalendar: _openDrinkCalendar,
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
    );
  }

  /// 点击打卡/想喝/点评卡：坐标有效时打开锁定的半屏地图。
  void _openVenueHalfMap(MapVenue venue) {
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
    openVenueMapHalfPage<void>(context, venue);
  }

  void _openRouteDetail(_Moment moment) {
    final routeId = moment.routeId;
    if (routeId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RouteDetailMapPage(
          routeId: routeId,
          title: moment.title,
          subtitle: moment.subtitle ?? '',
          previewStops: moment.stops,
        ),
      ),
    );
  }

  void _openDrinkCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DrinkStickerCalendarPage()),
    );
  }
}

// ---------- 页头：头像 + 小标签资料 ----------

class _ProfileHeaderSection extends StatelessWidget {
  const _ProfileHeaderSection({
    required this.profile,
    required this.isCurrentUser,
    required this.updatingFollow,
    required this.onFollow,
    this.checkInCount,
    this.wishCount,
    this.routeCount,
    this.drinkCount,
  });

  final UserProfileData profile;
  final bool isCurrentUser;
  final bool updatingFollow;
  final VoidCallback onFollow;

  /// overview 未返回计数时的列表长度兜底值。
  final int? checkInCount;
  final int? wishCount;
  final int? routeCount;

  /// 记账喝酒次数；仅本人主页展示。
  final int? drinkCount;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final bio = profile.bio?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        children: [
          _UserAvatar(url: profile.avatarUrl, size: 96),
          const SizedBox(height: 14),
          Text(
            profile.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: PublicProfilePage._ink,
            ),
          ),
          // 编辑资料里填写的内容以小标签形式排在头像/昵称下方。
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (profile.username?.isNotEmpty == true)
                _InfoChip(
                  icon: Icons.alternate_email_rounded,
                  label: profile.username!,
                ),
              if (profile.city?.isNotEmpty == true)
                _InfoChip(
                  icon: Icons.location_on_outlined,
                  label: profile.city!,
                ),
              if (profile.id != null)
                _InfoChip(
                  icon: Icons.badge_outlined,
                  label: 'ID ${profile.id}',
                ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              bio,
              textAlign: TextAlign.center,
              style: const TextStyle(
                height: 1.5,
                color: Color(0xFF4B464B),
                fontSize: 13,
              ),
            ),
          ],
          if (!isCurrentUser) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: 152,
              child: FilledButton(
                onPressed: updatingFollow ? null : onFollow,
                style: FilledButton.styleFrom(
                  backgroundColor: profile.isFollowing == true
                      ? const Color(0xFFF0E9ED)
                      : PublicProfilePage._brand,
                  foregroundColor: profile.isFollowing == true
                      ? const Color(0xFF6D5865)
                      : Colors.white,
                ),
                child: Text(
                  updatingFollow
                      ? '处理中…'
                      : (profile.isFollowing == true ? '已关注' : '关注'),
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _StatsRow(
            profile: profile,
            isCurrentUser: isCurrentUser,
            checkInCount: checkInCount,
            wishCount: wishCount,
            routeCount: routeCount,
            drinkCount: drinkCount,
          ),
          const SizedBox(height: 26),
        ],
      ),
    );
  }
}

/// 资料小标签：浅粉底圆角胶囊。
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF1F7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: PublicProfilePage._brand),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PublicProfilePage._brand,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.profile,
    required this.isCurrentUser,
    this.checkInCount,
    this.wishCount,
    this.routeCount,
    this.drinkCount,
  });

  final UserProfileData profile;
  final bool isCurrentUser;

  /// overview 未返回计数时的列表长度兜底值。
  final int? checkInCount;
  final int? wishCount;
  final int? routeCount;

  /// 记账喝酒次数；仅本人主页展示。
  final int? drinkCount;

  @override
  Widget build(BuildContext context) {
    // 粉丝/关注暂不展示；计数优先用 overview 返回值，兜底用动态列表长度。
    final stats = <_ProfileStat>[
      _ProfileStat('喝过', profile.checkInCount ?? checkInCount),
      _ProfileStat('想喝', profile.wishlistCount ?? wishCount),
      _ProfileStat('路线', profile.routeCount ?? routeCount),
      if (isCurrentUser) _ProfileStat('喝酒次数', drinkCount),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final stat in stats) Expanded(child: _StatTile(stat: stat)),
        ],
      ),
    );
  }
}

class _ProfileStat {
  const _ProfileStat(this.label, this.value);
  final String label;
  final int? value;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _ProfileStat stat;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        stat.value?.toString() ?? '—',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: PublicProfilePage._ink,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        stat.label,
        style: const TextStyle(
          color: PublicProfilePage._muted,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.url, required this.size});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final value = url?.trim();
    final imageUrl = value == null || value.isEmpty
        ? null
        : SiponApiConfig.instance.resolveUri(value).toString();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFFFE4F1),
      backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl),
      onBackgroundImageError: imageUrl == null ? null : (_, _) {},
      child: imageUrl == null
          ? Icon(
              Icons.person_rounded,
              size: size * .52,
              color: PublicProfilePage._brand,
            )
          : null,
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('主页加载失败'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

// ---------- 动态瀑布流 ----------

/// 动态区标题 + 两列瀑布流；无动态时给出引导文案。
class _MomentsSection extends StatelessWidget {
  const _MomentsSection({
    required this.moments,
    required this.loading,
    required this.onOpenVenue,
    required this.onOpenRoute,
    required this.onOpenDrinkCalendar,
  });

  final List<_Moment> moments;
  final bool loading;
  final ValueChanged<MapVenue> onOpenVenue;
  final ValueChanged<_Moment> onOpenRoute;
  final VoidCallback onOpenDrinkCalendar;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: PublicProfilePage._brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '我的动态',
                  style: TextStyle(
                    color: PublicProfilePage._ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PublicProfilePage._brand,
                    ),
                  ),
                ),
              )
            else if (moments.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCF8FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.local_bar_rounded,
                      size: 34,
                      color: Color(0xFFD8C9D3),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '还没有动态，去打卡第一家酒吧吧',
                      style: TextStyle(
                        color: PublicProfilePage._muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              _MomentTimeline(
                moments: moments,
                onOpenVenue: onOpenVenue,
                onOpenRoute: onOpenRoute,
                onOpenDrinkCalendar: onOpenDrinkCalendar,
              ),
          ],
        ),
      ),
    );
  }
}

/// 时间线动态流：左侧日期 + 节点圆点/垂线，右侧内容卡；
/// 动态已按时间倒序，同一天的日期只在当天第一条展示。
class _MomentTimeline extends StatelessWidget {
  const _MomentTimeline({
    required this.moments,
    required this.onOpenVenue,
    required this.onOpenRoute,
    required this.onOpenDrinkCalendar,
  });

  final List<_Moment> moments;
  final ValueChanged<MapVenue> onOpenVenue;
  final ValueChanged<_Moment> onOpenRoute;
  final VoidCallback onOpenDrinkCalendar;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? lastDayKey;
    for (var index = 0; index < moments.length; index++) {
      final moment = moments[index];
      final dayKey = _dayKey(moment.time);
      final showDate = dayKey != lastDayKey;
      lastDayKey = dayKey;
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: index == moments.length - 1 ? 0 : 14),
          child: _TimelineRow(
            moment: moment,
            dateText: showDate ? _dayLabel(moment.time) : null,
            isLast: index == moments.length - 1,
            onOpenVenue: onOpenVenue,
            onOpenRoute: onOpenRoute,
            onOpenDrinkCalendar: onOpenDrinkCalendar,
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  static String _dayKey(DateTime? time) {
    final value = time;
    return value == null ? '' : '${value.year}-${value.month}-${value.day}';
  }

  /// 日期文案：今年显示「M月d日」，往年带年份。
  static String _dayLabel(DateTime? time) {
    final value = time;
    if (value == null) return '';
    final now = DateTime.now();
    if (value.year == now.year) return '${value.month}月${value.day}日';
    return '${value.year}/${value.month}/${value.day}';
  }
}

/// 时间线的一行：左列日期、中间节点轴（圆点 + 向下延伸的垂线）、右侧卡片。
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.moment,
    required this.isLast,
    required this.onOpenVenue,
    required this.onOpenRoute,
    required this.onOpenDrinkCalendar,
    this.dateText,
  });

  final _Moment moment;
  final String? dateText;
  final bool isLast;
  final ValueChanged<MapVenue> onOpenVenue;
  final ValueChanged<_Moment> onOpenRoute;
  final VoidCallback onOpenDrinkCalendar;

  static const Color _lineColor = Color(0xFFF0E2EB);

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 日期列：同日只在第一条展示，其余留空对齐。
          SizedBox(
            width: 50,
            child: dateText == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      dateText!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFFB9AEB6),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // 节点轴：圆点固定在顶部，垂线延伸到行底（最后一行不再延伸）。
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: moment.dotColor,
                    border: Border.all(
                      color: moment.dotColor.withValues(alpha: 0.25),
                      width: 3,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: _lineColor),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MomentCard(
              moment: moment,
              onOpenVenue: onOpenVenue,
              onOpenRoute: onOpenRoute,
              onOpenDrinkCalendar: onOpenDrinkCalendar,
            ),
          ),
        ],
      ),
    );
  }
}

/// 动态卡片：点击跳转对应详情。
class _MomentCard extends StatelessWidget {
  const _MomentCard({
    required this.moment,
    required this.onOpenVenue,
    required this.onOpenRoute,
    required this.onOpenDrinkCalendar,
  });

  final _Moment moment;
  final ValueChanged<MapVenue> onOpenVenue;
  final ValueChanged<_Moment> onOpenRoute;
  final VoidCallback onOpenDrinkCalendar;

  @override
  Widget build(BuildContext context) {
    final moment = this.moment;
    // shape 与 borderRadius 不能同时传给 Material（断言约束），
    // 圆角与描边统一放在 shape 里，裁剪也按 shape 生效。
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFF3EAF0)),
      ),
      child: InkWell(
        onTap: switch (moment.kind) {
          _MomentKind.route =>
            moment.routeId == null ? null : () => onOpenRoute(moment),
          _MomentKind.drink => onOpenDrinkCalendar,
          _ => moment.venue == null ? null : () => onOpenVenue(moment.venue!),
        },
        child: switch (moment.kind) {
          _MomentKind.checkIn => _CheckInBody(moment: moment),
          _MomentKind.wish => _WishBody(moment: moment),
          _MomentKind.route => _RouteBody(moment: moment),
          _MomentKind.review => _ReviewBody(moment: moment),
          _MomentKind.drink => _DrinkBody(moment: moment),
        },
      ),
    );
  }
}

/// 打卡卡：封面图（或渐变占位）+ 酒吧名 + 时间。
class _CheckInBody extends StatelessWidget {
  const _CheckInBody({required this.moment});

  final _Moment moment;

  @override
  Widget build(BuildContext context) {
    final imageUrl = moment.imageUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 132,
              child: _MomentImage(url: imageUrl),
            ),
            const Positioned(
              left: 8,
              top: 8,
              child: _MomentBadge(label: '打卡', color: PublicProfilePage._brand),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                moment.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PublicProfilePage._ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (moment.subtitle?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  moment.subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PublicProfilePage._muted,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 5),
              _MomentTime(time: moment.time),
            ],
          ),
        ),
      ],
    );
  }
}

/// 想喝卡：封面图 + 酒吧名 + 评分/城市。
class _WishBody extends StatelessWidget {
  const _WishBody({required this.moment});

  final _Moment moment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: 112,
              child: _MomentImage(url: moment.imageUrl),
            ),
            const Positioned(
              left: 8,
              top: 8,
              child: _MomentBadge(label: '想喝', color: Color(0xFFFF8BD0)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                moment.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PublicProfilePage._ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                moment.subtitle?.isNotEmpty == true
                    ? moment.subtitle!
                    : '想去喝一杯',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PublicProfilePage._muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 路线卡：暖色底 + 站点小标签流。
class _RouteBody extends StatelessWidget {
  const _RouteBody({required this.moment});

  final _Moment moment;

  @override
  Widget build(BuildContext context) {
    final stops = moment.stops;
    return Container(
      color: moment.cardColor,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _MomentBadge(label: '路线', color: Color(0xFFB8860B)),
              const Spacer(),
              Icon(
                moment.isPrivate
                    ? Icons.lock_outline_rounded
                    : Icons.public_rounded,
                size: 14,
                color: const Color(0xFF7B7580),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            moment.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PublicProfilePage._ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            moment.subtitle?.isNotEmpty == true
                ? moment.subtitle!
                : '${stops.length} 个地点',
            style: const TextStyle(
              color: Color(0xFF79747C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (stops.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (index, stop) in stops.take(3).indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1} ${stop.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PublicProfilePage._ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (stops.length > 3)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '+${stops.length - 3}',
                      style: const TextStyle(
                        color: PublicProfilePage._ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 点评卡：引用样式的文字内容 + 底部酒吧名。
class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.moment});

  final _Moment moment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFFBF5),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _MomentBadge(label: '点评', color: Color(0xFFC98A2D)),
              const Spacer(),
              const Icon(
                Icons.format_quote_rounded,
                size: 18,
                color: Color(0xFFE7CFA8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            moment.subtitle ?? '',
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PublicProfilePage._ink,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.local_bar_rounded,
                size: 13,
                color: PublicProfilePage._brand,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  moment.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PublicProfilePage._brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _MomentTime(time: moment.time),
        ],
      ),
    );
  }
}

/// 记账小酌卡：喝酒本身（酒名/杯数/地点/日期），金额私密不展示。
class _DrinkBody extends StatelessWidget {
  const _DrinkBody({required this.moment});

  final _Moment moment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF3FAF5),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _MomentBadge(label: '小酌', color: Color(0xFF3FA66A)),
              const Spacer(),
              const Icon(
                Icons.local_drink_rounded,
                size: 16,
                color: Color(0xFF3FA66A),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            moment.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PublicProfilePage._ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (moment.cups > 0) ...[
                const Icon(
                  Icons.local_bar_rounded,
                  size: 13,
                  color: Color(0xFF3FA66A),
                ),
                const SizedBox(width: 3),
                Text(
                  '×${moment.cups}',
                  style: const TextStyle(
                    color: Color(0xFF3FA66A),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  moment.subtitle ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: PublicProfilePage._muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _MomentTime(time: moment.time),
        ],
      ),
    );
  }
}

/// 卡片左上角的类型小徽标。
class _MomentBadge extends StatelessWidget {
  const _MomentBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MomentTime extends StatelessWidget {
  const _MomentTime({required this.time});

  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final value = time;
    if (value == null) return const SizedBox.shrink();
    return Text(
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
      style: const TextStyle(color: Color(0xFFB9B2BC), fontSize: 11),
    );
  }
}

/// 动态封面图：网络图优先，失败或为空时回退本地资产。
class _MomentImage extends StatelessWidget {
  const _MomentImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final value = url?.trim();
    if (value == null || value.isEmpty) {
      return Image.asset(PublicProfilePage._fallbackCover, fit: BoxFit.cover);
    }
    return Image.network(
      SiponApiConfig.instance.resolveUri(value).toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          Image.asset(PublicProfilePage._fallbackCover, fit: BoxFit.cover),
    );
  }
}

// ---------- 动态数据模型与解析 ----------

enum _MomentKind { checkIn, wish, route, review, drink }

/// 时间线上的一条动态。
class _Moment {
  const _Moment({
    required this.kind,
    required this.title,
    this.time,
    this.subtitle,
    this.imageUrl,
    this.venue,
    this.routeId,
    this.stops = const [],
    this.isPrivate = false,
    this.cups = 0,
    this.cardColor = Colors.white,
  });

  final _MomentKind kind;
  final String title;
  final DateTime? time;
  final String? subtitle;
  final String? imageUrl;
  final MapVenue? venue;
  final int? routeId;
  final List<RouteStop> stops;
  final bool isPrivate;
  final int cups;
  final Color cardColor;

  /// 时间线节点圆点颜色：按动态类型区分。
  Color get dotColor => switch (kind) {
    _MomentKind.checkIn => PublicProfilePage._brand,
    _MomentKind.wish => const Color(0xFFFF8BD0),
    _MomentKind.route => const Color(0xFFB8860B),
    _MomentKind.review => const Color(0xFFC98A2D),
    _MomentKind.drink => const Color(0xFF3FA66A),
  };
}

DateTime? _parseTime(Map<String, dynamic> map, List<String> keys) {
  final raw = _pickString(map, keys);
  if (raw == null) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// 一条打卡可能产出两张卡：打卡卡本身 + 打卡时写的文字点评卡。
List<_Moment> _momentsFromCheckIn(Map<String, dynamic> map) {
  final name = _pickString(map, ['barName', 'name', 'barTitle']);
  if (name == null) return const [];
  final time = _parseTime(map, ['visitedAt', 'createdAt']);
  final city = _pickString(map, ['city']);
  final content = (_pickString(map, ['content']) ?? '').trim();
  final imageUrl = _pickCheckInImageUrl(map);
  final venue = _venueFromEntryMap(map, name: name);

  return [
    // 打卡卡副文只放城市，日期由卡片底部时间展示，避免重复。
    _Moment(
      kind: _MomentKind.checkIn,
      title: name,
      time: time,
      subtitle: city,
      imageUrl: imageUrl,
      venue: venue,
    ),
    if (content.isNotEmpty)
      _Moment(
        kind: _MomentKind.review,
        title: name,
        time: time,
        subtitle: content,
        venue: venue,
      ),
  ];
}

_Moment? _momentFromWishlist(Map<String, dynamic> map) {
  final name = _pickString(map, ['name', 'barName', 'title']);
  if (name == null) return null;
  final rating = _pickNum(map, ['averageRating', 'rating', 'score']);
  final city = _pickString(map, ['city']);
  final meta = [
    ?city,
    if (rating != null) '${rating.toStringAsFixed(1)} 分',
  ].join(' · ');
  return _Moment(
    kind: _MomentKind.wish,
    title: name,
    time: _parseTime(map, ['createdAt', 'addedAt', 'updatedAt']),
    subtitle: meta.isEmpty ? null : meta,
    imageUrl:
        _pickString(map, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
        _pickFirstUrl(map, ['gallery']),
    venue: _venueFromEntryMap(map, name: name),
  );
}

_Moment? _momentFromRoute(Map<String, dynamic> map) {
  final title = _pickString(map, ['title', 'name']);
  if (title == null) return null;
  final start = _shortDate(map, ['localStartDate', 'startDate']);
  final end = _shortDate(map, ['localEndDate', 'endDate']);
  final stops = parseRouteStops(map);
  final rangeText = start.isEmpty ? '' : '$start 至 $end';
  return _Moment(
    kind: _MomentKind.route,
    title: title,
    time: _parseTime(map, ['createdAt', 'updatedAt']),
    subtitle: rangeText.isEmpty ? null : rangeText,
    routeId: _pickNum(map, ['id'])?.toInt(),
    stops: stops,
    isPrivate: _pickString(map, ['visibility'])?.toLowerCase() != 'public',
    cardColor: stops.isEmpty || stops.length.isEven
        ? const Color(0xFFFFE6B8)
        : const Color(0xFFDDE5FF),
  );
}

/// 记账动态：只展示喝的是什么/在哪/什么时候，不展示金额。
_Moment _momentFromDrinkRecord(DrinkBudgetRecord record) {
  final title = record.drinkName.trim().isNotEmpty
      ? record.drinkName.trim()
      : (record.drinkType.trim().isNotEmpty ? record.drinkType : '小酌一杯');
  return _Moment(
    kind: _MomentKind.drink,
    title: title,
    time: record.date,
    subtitle: record.place.trim().isEmpty ? null : record.place.trim(),
    cups: record.cups,
  );
}

/// ISO 时间截断为 `yyyy-MM-dd` 日期文案。
String _shortDate(Map<String, dynamic> map, List<String> keys) {
  final iso = _pickString(map, keys);
  if (iso == null || iso.length < 10) return '';
  return iso.substring(0, 10);
}

// ---------- 宽松取值工具（与「我的」页同一套约定） ----------

String? _pickString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

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

List<dynamic>? _pickList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) return value;
  }
  return null;
}

Map<String, dynamic>? _pickMapOf(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map) return value.cast<String, dynamic>();
  }
  return null;
}

double? _pickCoordinate(Map<String, dynamic>? map, {required bool longitude}) {
  if (map == null) return null;
  final keys = longitude
      ? const ['longitude', 'lng', 'lon']
      : const ['latitude', 'lat'];
  return _pickNum(map, keys)?.toDouble();
}

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

/// 从打卡/想喝条目原始 JSON 解析跳转半屏地图所需的 [MapVenue]。
MapVenue _venueFromEntryMap(Map<String, dynamic> map, {required String name}) {
  final nested = _pickMapOf(map, ['bar', 'barInfo', 'venue', 'place']);
  final bar = nested ?? const <String, dynamic>{};
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
    tags: const [],
    imageAsset: PublicProfilePage._fallbackCover,
    imageUrl:
        _pickString(map, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
        _pickString(bar, ['imageUrl', 'image', 'cover', 'coverUrl']),
  );
}
