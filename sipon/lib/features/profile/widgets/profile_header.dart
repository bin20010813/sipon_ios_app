part of '../pages/profile_page.dart';

class _ProfileTopActions extends StatelessWidget {
  const _ProfileTopActions({
    this.onLogoutSucceeded,
    required this.onNotificationsPressed,
    required this.hasUnreadNotifications,
  });

  final VoidCallback? onLogoutSucceeded;
  final VoidCallback onNotificationsPressed;
  final bool hasUnreadNotifications;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _TopIconButton(
          tooltip: text.messages,
          icon: Icons.notifications_none_rounded,
          showDot: hasUnreadNotifications,
          onPressed: onNotificationsPressed,
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
    final scheme = Theme.of(context).colorScheme;
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
              foregroundColor: scheme.onSurfaceVariant,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(icon, size: 25),
          ),
          if (showDot)
            Positioned(
              right: 7,
              top: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 7, height: 7),
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
    final scheme = Theme.of(context).colorScheme;

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
                    color: scheme.onSurface,
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
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      '查看我的主页',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: loading ? null : onEdit,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;

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
                // 头像描边用 surface：浅色与原白色一致，深色融入背景减少割裂，
                // 分隔作用由下方品牌阴影继续承担。
                border: Border.all(color: scheme.surface, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: context.siponColors.shadow,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
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
                // 内容固有色保留：小酌徽章粉底。
                color: const Color(0xFFFF8BD0),
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    // 内容固有色保留：徽章配套粉色阴影。
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
                    // 内容固有色保留：星标底。
                    backgroundColor: Color(0xFFFFD23C),
                    child: Icon(
                      Icons.star_rounded,
                      // 内容固有色保留：星标红。
                      color: Color(0xFFB12C29),
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    text.badgeTitle,
                    // 内容固有色保留：徽章上的白色文字。
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
        color: context.siponColors.elevatedSurface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.siponColors.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
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
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 内容图保持原图：多彩 PNG 不做主题着色，承载卡片底已随主题适配；
            // 深色变体资源待设计补齐后可再替换 asset。
            Image.asset(assetPath, width: 32, height: 32),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
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
