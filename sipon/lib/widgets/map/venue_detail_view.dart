import 'package:flutter/material.dart' hide Visibility;

import '../../pages/language_transform.dart';
import '../../pages/venue_contribution_page.dart';
import '../../services/external_map_launcher.dart';
import '../../services/map/api_venue_detail_repository.dart';
import '../../services/map/map_models.dart';
import '../../services/map/mock_venue_detail_repository.dart';
import '../../services/map/venue_detail_models.dart';
import '../../services/sipon_api_service.dart';
import '../bottom_clamping_bouncing_scroll_physics.dart';
import '../sipon_network_image.dart';
import 'map_theme.dart';
import '../review_composer.dart';
import 'venue_common.dart';

/// 判断详情数据里的图片路径是否是网络地址（相对路径也算，交给 VenueImage 拼接）。
bool _isRemoteImage(String path) =>
    path.startsWith('http') || path.startsWith('/');

/// 展开态的详情内容。
///
/// 由 [VenueSheetSurface] 里唯一的滚动视图承载，方便整体做透明度动画。
/// 数据源通过 [repository] 注入：默认 [MockVenueDetailRepository] 保持现状，
/// 后端联调时传入 [SiponApiVenueDetailRepository]，页面代码零改动。
class VenueDetailContent extends StatefulWidget {
  /// 创建地点详情内容。
  const VenueDetailContent({
    super.key,
    required this.venue,
    required this.scrollController,
    required this.opacity,
    required this.topInset,
    required this.bottomOverlayInset,
    required this.onClose,
    this.onAddressTap,
    this.onMapClose,
    this.repository,
  });

  /// 当前选中的酒吧基础信息。
  final MapVenue venue;

  /// 与 DraggableScrollableSheet 共用的滚动控制器。
  final ScrollController scrollController;

  /// 展开态内容随面板形变渐显的透明度。
  final double opacity;

  /// 全屏过程中逐渐让出的状态栏高度。
  final double topInset;

  /// 底部悬浮元素（如导航栏）需要避开的额外高度。
  final double bottomOverlayInset;

  /// 点击关闭按钮的回调。
  final VoidCallback onClose;

  /// 独立详情页可接管地址点击；地图面板未传时仍打开外部导航。
  final ValueChanged<MapVenue>? onAddressTap;

  /// 半屏地图关闭回调；传入时在封面左上角显示独立的地图关闭按钮。
  final VoidCallback? onMapClose;

  /// 详情数据源；为 null 时使用 Mock，保持既有演示行为。
  final VenueDetailRepository? repository;

  @override
  State<VenueDetailContent> createState() => _VenueDetailContentState();
}

class _VenueDetailContentState extends State<VenueDetailContent> {
  static const double _pagePadding = 20;
  static const double _tabsHeight = 56;

  /// 评价每页条数：详情首屏与「更多评论」翻页共用。
  static const int _reviewPageSize = 10;

  /// 详情数据源，默认 Mock；调用方注入 API 实现后即可联调真实接口。
  late final VenueDetailRepository _repository =
      widget.repository ?? const MockVenueDetailRepository();
  final SiponApiService _api = SiponApiService();

  /// 当前加载到的详情数据。
  VenueDetail? _detail;

  /// 已加载的评价列表（详情首屏 + 分页追加）。
  List<VenueReview> _reviews = const [];

  /// 评价总数（来自详情/分页响应的汇总字段）。
  int _reviewTotal = 0;

  /// 是否还有下一页评价可加载。
  bool _reviewsHasMore = false;

  /// 正在翻页加载评价。
  bool _reviewsLoading = false;

  /// 加载失败时的错误文案；为 null 表示没有错误。
  String? _loadError;

  bool _favorite = false;
  int _galleryPage = 0;
  int _detailTabIndex = 0;
  _ReviewFilter _reviewFilter = _ReviewFilter.relevant;
  bool _scrollingToTab = false;
  bool _tabsPinned = false;
  final GlobalKey _scrollViewKey = GlobalKey();
  final GlobalKey _tabsKey = GlobalKey();
  final List<GlobalKey> _sectionKeys = List.generate(4, (_) => GlobalKey());
  final GlobalKey _updatesHeadingKey = GlobalKey();
  final GlobalKey _drinksHeadingKey = GlobalKey();
  final GlobalKey _reviewsHeadingKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_syncTabWithScroll);
    _loadDetail();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_syncTabWithScroll);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VenueDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_syncTabWithScroll);
      widget.scrollController.addListener(_syncTabWithScroll);
    }
    if (oldWidget.venue.id != widget.venue.id) {
      _detail = null;
      _loadError = null;
      _favorite = false;
      _galleryPage = 0;
      _detailTabIndex = 0;
      _reviews = const [];
      _reviewTotal = 0;
      _reviewsHasMore = false;
      _reviewsLoading = false;
      _tabsPinned = false;
      _loadDetail();
    }
  }

  /// 异步加载当前酒吧的详情数据；失败时展示错误态而不是卡在占位上。
  Future<void> _loadDetail() async {
    try {
      final detail = await _repository.fetchDetail(widget.venue);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loadError = null;
          _reviews = detail.reviews;
          _reviewTotal = detail.reviewCount;
          _reviewsHasMore = _reviews.length < detail.reviewCount;
          _reviewsLoading = false;
        });
      }
      await _loadFavorite();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error.toString();
        });
      }
    }
  }

  Future<void> _loadFavorite() async {
    final barId = int.tryParse(widget.venue.id);
    if (barId == null) return;
    try {
      final wishlist = await _api.getWishlistBars(
        page: const SiponPage(limit: 100),
      );
      final favorite = wishlist.whereType<Map>().any((item) {
        final map = item.cast<String, dynamic>();
        final id =
            (map['id'] as num?)?.toInt() ?? (map['barId'] as num?)?.toInt();
        return id == barId;
      });
      if (mounted) setState(() => _favorite = favorite);
    } on Exception {
      // 详情仍可用，收藏状态保持默认值。
    }
  }

  Future<void> _toggleFavorite() async {
    final barId = int.tryParse(widget.venue.id);
    if (barId == null) {
      _showMockToast(SiponLanguageScope.textOf(context).t('暂不支持收藏'));
      return;
    }
    final nextFavorite = !_favorite;
    setState(() => _favorite = nextFavorite);
    try {
      if (nextFavorite) {
        await _api.addWishlistBar(barId);
      } else {
        await _api.removeWishlistBar(barId);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _favorite = !nextFavorite);
      _showMockToast(
        '${SiponLanguageScope.textOf(context).t('收藏操作失败')}：$error',
      );
    }
  }

  /// 点赞/点踩评价：先按结果更新本地列表，请求失败再回滚。
  ///
  /// [reaction] 取 `like` / `dislike`，null 表示取消表态；`review.id` 为空
  /// 说明是本地示例数据，没有可写入的签到。
  Future<void> _setReviewReaction(VenueReview review, String? reaction) async {
    final text = SiponLanguageScope.textOf(context);
    final checkInId = review.id;
    if (checkInId == null) {
      _showMockToast(text.t('暂不支持该评价互动'));
      return;
    }
    final previousReviews = _reviews;
    final likeDelta =
        (reaction == 'like' ? 1 : 0) - (review.myReaction == 'like' ? 1 : 0);
    final likeCount = review.likeCount + likeDelta;
    setState(() {
      _reviews = [
        for (final item in _reviews)
          if (item.id == checkInId)
            review.copyWithReaction(
              myReaction: reaction,
              likeCount: likeCount < 0 ? 0 : likeCount,
            )
          else
            item,
      ];
    });
    try {
      await _api.setCheckInReaction(checkInId, reaction);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _reviews = previousReviews);
      _showMockToast('${text.t('互动失败')}：$error');
      return;
    }
    if (!mounted) return;
    final isDislike = (reaction ?? review.myReaction) == 'dislike';
    _showMockToast(
      text.t(
        reaction == null
            ? (isDislike ? '已取消点踩' : '已取消点赞')
            : (isDislike ? '点踩成功' : '点赞成功'),
      ),
    );
  }

  /// 举报评价：选完原因后 POST /api/reports，`reason` 上报稳定码、`details` 带上文案。
  Future<void> _reportReview(VenueReview review) async {
    final text = SiponLanguageScope.textOf(context);
    final checkInId = review.id;
    if (checkInId == null) {
      _showMockToast(text.t('暂不支持该评价互动'));
      return;
    }
    final reason = await showModalBottomSheet<_ReportReason>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const _ReportReasonSheet(),
    );
    if (reason == null) return;
    try {
      await _api.createReport({
        'contentType': 'check_in',
        'contentId': checkInId,
        'reason': reason.code,
        'details': reason.label,
      });
      if (!mounted) return;
      _showMockToast(text.t('举报已提交，感谢反馈'));
    } on Exception catch (error) {
      if (!mounted) return;
      _showMockToast('${text.t('举报提交失败')}：$error');
    }
  }

  void _showMockToast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 220,
          duration: const Duration(milliseconds: 1200),
        ),
      );
  }

  Future<void> _openNavigation() async {
    final text = SiponLanguageScope.textOf(context);
    final apps = await ExternalMapLauncher.availableNavigationApps();
    if (!mounted) {
      return;
    }
    if (apps.isEmpty) {
      _showMockToast(text.t(ExternalMapLaunchResult.unavailable().message));
      return;
    }

    final selected = await showModalBottomSheet<ExternalMapApp>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                text.t('选择地图软件'),
                style: const TextStyle(
                  color: MapDesign.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            for (final app in apps)
              ListTile(
                leading: Icon(_mapAppIcon(app), color: MapDesign.brand),
                title: Text(
                  app.label,
                  style: const TextStyle(
                    color: MapDesign.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                subtitle: Text(
                  text.t('以当前位置规划路线，可选择交通方式'),
                  style: const TextStyle(
                    color: MapDesign.muted,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(app),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null) {
      return;
    }

    final result = await ExternalMapLauncher.openNavigation(
      app: selected,
      name: widget.venue.name,
      longitude: widget.venue.longitude,
      latitude: widget.venue.latitude,
    );
    if (!mounted) {
      return;
    }
    _showMockToast(text.t(result.message));
  }

  IconData _mapAppIcon(ExternalMapApp app) {
    return switch (app) {
      ExternalMapApp.apple => Icons.map_rounded,
      ExternalMapApp.amap => Icons.navigation_rounded,
      ExternalMapApp.baidu => Icons.explore_rounded,
      ExternalMapApp.tencent => Icons.near_me_rounded,
    };
  }

  void _syncTabWithScroll() {
    if (_scrollingToTab) {
      return;
    }
    final scrollBox = _scrollViewKey.currentContext?.findRenderObject();
    if (scrollBox is! RenderBox) {
      return;
    }

    final threshold = widget.topInset + _tabsHeight + 12;
    final tabsBox = _tabsKey.currentContext?.findRenderObject();
    final tabsPinned =
        tabsBox is RenderBox &&
        tabsBox.localToGlobal(Offset.zero, ancestor: scrollBox).dy <=
            widget.topInset;
    var nextIndex = 0;
    for (var index = 0; index < _sectionKeys.length; index++) {
      final sectionBox = _sectionKeys[index].currentContext?.findRenderObject();
      if (sectionBox is RenderBox &&
          sectionBox.localToGlobal(Offset.zero, ancestor: scrollBox).dy <=
              threshold) {
        nextIndex = index;
      }
    }
    if (mounted &&
        (nextIndex != _detailTabIndex || tabsPinned != _tabsPinned)) {
      setState(() {
        _detailTabIndex = nextIndex;
        _tabsPinned = tabsPinned;
      });
    }
  }

  Future<void> _scrollToSection(int index) async {
    final sectionContext = _sectionKeys[index].currentContext;
    final scrollBox = _scrollViewKey.currentContext?.findRenderObject();
    if (sectionContext == null || scrollBox is! RenderBox) {
      return;
    }
    final sectionBox = sectionContext.findRenderObject();
    if (sectionBox is! RenderBox) {
      return;
    }

    _scrollingToTab = true;
    setState(() => _detailTabIndex = index);
    // 板块内的小标题由吸顶标签栏代为展示：跳转时让标题一并藏进吸顶栏，
    // 定位点落在标题下方的功能内容顶部。
    final headingHeight = switch (index) {
      1 => _measureHeading(_updatesHeadingKey),
      2 => _measureHeading(_drinksHeadingKey),
      3 => _measureHeading(_reviewsHeadingKey),
      _ => 0.0,
    };
    final threshold = widget.topInset + _tabsHeight + 12;
    final position = widget.scrollController.position;
    final target =
        (sectionBox.localToGlobal(Offset.zero, ancestor: scrollBox).dy +
                position.pixels -
                threshold +
                headingHeight)
            .clamp(0.0, position.maxScrollExtent);
    try {
      await widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _scrollingToTab = false;
      _syncTabWithScroll();
    }
  }

  /// 小标题高度 + 与内容的间距。
  double _measureHeading(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return 0;
    }

    return box.size.height + 12;
  }

  /// 翻页加载下一批评价；成功后把新内容带进视野。
  Future<void> _loadMoreReviews() async {
    if (_reviewsLoading || !_reviewsHasMore) {
      return;
    }

    setState(() => _reviewsLoading = true);
    try {
      final page = await _repository.fetchReviews(
        widget.venue,
        offset: _reviews.length,
        limit: _reviewPageSize,
      );
      if (!mounted) {
        return;
      }
      final previousOffset = widget.scrollController.offset;
      setState(() {
        _reviews = [..._reviews, ...page.reviews];
        _reviewTotal = page.totalCount;
        _reviewsHasMore = page.hasMore && page.reviews.isNotEmpty;
        _reviewsLoading = false;
      });
      _scrollingToTab = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          return;
        }
        final target = (previousOffset + 220).clamp(
          0.0,
          widget.scrollController.position.maxScrollExtent,
        );
        try {
          await widget.scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        } finally {
          _scrollingToTab = false;
          _syncTabWithScroll();
        }
      });
    } on Exception {
      if (!mounted) {
        return;
      }
      setState(() => _reviewsLoading = false);
      _showMockToast(SiponLanguageScope.textOf(context).t('加载更多评价失败，请重试'));
    }
  }

  /// 打开补充信息共建页；提交成功后向用户致谢。
  Future<void> _openContribution() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VenueContributionPage(venue: widget.venue),
      ),
    );
    if (!mounted || submitted != true) {
      return;
    }
    _showMockToast(SiponLanguageScope.textOf(context).t('感谢共建！信息已提交审核'));
  }

  void _openReviewComposer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFFBF8F9),
          appBar: AppBar(
            title: const Text(
              '写评论',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
          ),
          body: ReviewComposer(
            venueName: widget.venue.name,
            venueAddress: widget.venue.address,
            onSubmit: (draft) async {
              if (!mounted) return;
              _showMockToast(
                SiponLanguageScope.textOf(context).t('评论发布功能开发中（演示）'),
              );
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomScrollView(
          key: _scrollViewKey,
          controller: widget.scrollController,
          physics: const BottomClampingBouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverIgnorePointer(
              ignoring: widget.opacity < 0.5,
              sliver: SliverOpacity(
                opacity: widget.opacity,
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHero(context)),
                    if (_loadError != null && _detail == null)
                      SliverToBoxAdapter(child: _buildLoadError(context))
                    else ...[
                      SliverToBoxAdapter(child: _buildOverview(context)),
                      SliverToBoxAdapter(
                        child: Padding(
                          key: _tabsKey,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          child: _VenueDetailTabs(
                            selectedIndex: _detailTabIndex,
                            onSelected: _scrollToSection,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _buildSections(context)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_tabsPinned)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: widget.opacity < 0.5,
              child: Opacity(
                opacity: widget.opacity,
                child: Material(
                  color: Colors.white,
                  elevation: 1,
                  shadowColor: const Color(0x1F000000),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      widget.topInset + 18,
                      20,
                      4,
                    ),
                    child: _VenueDetailTabs(
                      selectedIndex: _detailTabIndex,
                      onSelected: _scrollToSection,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 详情加载失败的错误态：给出错误文案与重试入口，断网时不至于白屏。
  Widget _buildLoadError(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pagePadding, 32, _pagePadding, 32),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: MapDesign.muted, size: 32),
          const SizedBox(height: 12),
          Text(
            text.t('详情加载失败'),
            style: const TextStyle(
              color: MapDesign.ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _loadError ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MapDesign.muted,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _loadError = null);
              _loadDetail();
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(text.t('重试')),
            style: OutlinedButton.styleFrom(
              foregroundColor: MapDesign.brand,
              side: const BorderSide(color: MapDesign.brand),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 沉浸式封面轮播：关闭按钮与页码悬浮在图上，不再单独占一行。
  Widget _buildHero(BuildContext context) {
    // 详情数据尚未返回时先展示首页传入的封面；它与首页使用相同 URL，
    // Flutter 可直接复用正在进行或已经完成的图片缓存请求。
    final images =
        _detail?.gallery ??
        [
          VenueGalleryImage(
            mediumImageUrl: widget.venue.imageUrl ?? widget.venue.imageAsset,
            imageUrl: widget.venue.imageUrl ?? widget.venue.imageAsset,
          ),
        ];
    final showPageBadge = images.length > 1;
    Widget buildImage(int index) {
      final path = images[index].mediumImageUrl;
      final remote = _isRemoteImage(path);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openGalleryPreview(context, images, index),
        child: VenueImage(
          imageUrl: remote ? path : null,
          assetPath: remote ? widget.venue.imageAsset : path,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          // 详情尚在加载时只有一张列表封面。即使禁用滚动，单页 PageView
          // 仍会创建横向手势识别器并抢走垂直拖动，所以单图直接渲染图片。
          child: images.length == 1
              ? buildImage(0)
              : PageView.builder(
                  itemCount: images.length,
                  onPageChanged: (index) =>
                      setState(() => _galleryPage = index),
                  itemBuilder: (context, index) => buildImage(index),
                ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.42),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.38),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: widget.topInset + 6,
          right: 12,
          child: _CircleIconButton(
            icon: Icons.close_rounded,
            tooltip: SiponLanguageScope.textOf(context).t('收起地点详情'),
            onTap: widget.onClose,
          ),
        ),
        if (widget.onMapClose != null)
          Positioned(
            top: widget.topInset + 6,
            left: 12,
            child: _CircleIconButton(
              icon: Icons.keyboard_arrow_down_rounded,
              tooltip: SiponLanguageScope.textOf(context).t('收起地图'),
              onTap: widget.onMapClose!,
            ),
          ),
        if (showPageBadge)
          Positioned(
            right: 14,
            bottom: 12,
            child: _GalleryPageBadge(
              current: _galleryPage + 1,
              total: images.length,
            ),
          ),
      ],
    );
  }

  /// 标签栏之前的标题、快捷操作和地点信息。
  Widget _buildOverview(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final detail = _detail;

    return Padding(
      padding: EdgeInsets.fromLTRB(_pagePadding, 18, _pagePadding, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _VenueTitleBlock(
            venue: widget.venue,
            detail: detail,
            favorite: _favorite,
            onToggleFavorite: _toggleFavorite,
            onNavigate: _openNavigation,
          ),
          const SizedBox(height: 18),
          _VenueInfoCard(
            detail: detail,
            onContribute: _openContribution,
            onOpenMap: widget.onAddressTap == null
                ? _openNavigation
                : () => widget.onAddressTap!(detail?.venue ?? widget.venue),
            addressActionLabel: widget.onAddressTap == null ? '点击导航' : '查看地图',
            onCall: () =>
                _showMockToast(text.t('正在拨打 ${detail?.phone ?? ''}（演示）')),
          ),
        ],
      ),
    );
  }

  /// 三个板块连续排列，滚动位置与吸顶标签双向联动。
  Widget _buildSections(BuildContext context) {
    final detail = _detail;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _pagePadding,
        18,
        _pagePadding,
        // bottomOverlayInset 已经包含全局底栏高度和系统底部安全区，不能
        // 再叠加一次 MediaQuery bottom inset。
        widget.bottomOverlayInset + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _sectionKeys[0],
            child: _VenueAbout(detail: detail, onContribute: _openContribution),
          ),
          const SizedBox(height: 35),
          KeyedSubtree(
            key: _sectionKeys[1],
            child: _VenueLatestUpdates(
              updates: detail?.latestUpdates ?? const [],
              loaded: detail != null,
              onContribute: _openContribution,
              headingKey: _updatesHeadingKey,
            ),
          ),
          const SizedBox(height: 35),
          KeyedSubtree(
            key: _sectionKeys[2],
            child: _VenueDrinks(
              drinks: detail?.signatureDrinks ?? const [],
              loaded: detail != null,
              onContribute: _openContribution,
              headingKey: _drinksHeadingKey,
            ),
          ),
          const SizedBox(height: 35),
          KeyedSubtree(
            key: _sectionKeys[3],
            child: _VenueReviewsSection(
              reviews: _reviews,
              totalCount: _reviewTotal,
              hasMoreReviews: _reviewsHasMore,
              reviewsLoading: _reviewsLoading,
              loaded: detail != null,
              onContribute: _openContribution,
              sort: _reviewFilter,
              onSortChanged: (filter) => setState(() => _reviewFilter = filter),
              onAddReview: _openReviewComposer,
              onViewMore: _loadMoreReviews,
              onReviewReaction: _setReviewReaction,
              onReviewReport: _reportReview,
              headingKey: _reviewsHeadingKey,
            ),
          ),
        ],
      ),
    );
  }

  void _openGalleryPreview(
    BuildContext context,
    List<VenueGalleryImage> images,
    int index,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _VenueGalleryPreview(
          images: images,
          initialIndex: index,
          fallbackAssetPath: widget.venue.imageAsset,
        ),
      ),
    );
  }
}

/// 地点图集的全屏预览：单击封面进入，支持横向切图与双指缩放。
class _VenueGalleryPreview extends StatefulWidget {
  const _VenueGalleryPreview({
    required this.images,
    required this.initialIndex,
    required this.fallbackAssetPath,
  });

  final List<VenueGalleryImage> images;
  final int initialIndex;
  final String fallbackAssetPath;

  @override
  State<_VenueGalleryPreview> createState() => _VenueGalleryPreviewState();
}

class _VenueGalleryPreviewState extends State<_VenueGalleryPreview> {
  late final PageController _controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) {
                final path = images[index].imageUrl;
                final remote = _isRemoteImage(path);
                final image = remote
                    ? SiponNetworkImage(
                        url: path,
                        fallbackAsset: widget.fallbackAssetPath,
                        fit: BoxFit.contain,
                      )
                    : Image.asset(path, fit: BoxFit.contain);
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: image),
                );
              },
            ),
            Positioned(
              top: 10,
              right: 12,
              child: IconButton.filled(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 18,
                left: 0,
                right: 0,
                child: Center(
                  child: _GalleryPageBadge(
                    current: _index + 1,
                    total: images.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 悬浮在封面上的圆形毛玻璃感按钮。
class _CircleIconButton extends StatelessWidget {
  /// 创建圆形按钮。
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

/// 封面右下角的页码胶囊，替代一串圆点指示器。
class _GalleryPageBadge extends StatelessWidget {
  /// 创建页码胶囊。
  const _GalleryPageBadge({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$current / $total',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// 关于、招牌酒款与评价共用的单行标签栏。
class _VenueDetailTabs extends StatelessWidget {
  const _VenueDetailTabs({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final labels = [text.t('关于'), text.t('最新动态'), text.t('菜单'), text.t('评价')];

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            _buildTab(labels[index], index),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(index),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selectedIndex == index
                        ? MapDesign.brand
                        : MapDesign.muted,
                    fontSize: 14,
                    fontWeight: selectedIndex == index
                        ? FontWeight.w900
                        : FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 2,
                  color: selectedIndex == index
                      ? MapDesign.brand
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 详情页标题区：类型徽章、人均、名称、评分与距离合并成一行 meta。
class _VenueTitleBlock extends StatelessWidget {
  /// 创建标题区。
  const _VenueTitleBlock({
    required this.venue,
    this.detail,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onNavigate,
  });

  final MapVenue venue;
  final VenueDetail? detail;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final reviewCount = detail?.reviewCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.t(venue.name),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _RatingStars(rating: venue.rating, starSize: 15),
            const SizedBox(width: 3),
            Text(
              venue.rating.toStringAsFixed(1),
              style: const TextStyle(
                color: MapDesign.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            if (reviewCount != null && reviewCount > 0) ...[
              const SizedBox(width: 3),
              Text(
                '($reviewCount)',
                style: const TextStyle(
                  color: MapDesign.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Text(
              '·',
              style: const TextStyle(
                color: MapDesign.muted,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.location_on_outlined, color: MapDesign.muted, size: 15),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                text.t(venue.distance),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MapDesign.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (detail != null) ...[
              const SizedBox(width: 8),
              Text(
                '·',
                style: const TextStyle(
                  color: MapDesign.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${text.t('人均')} ${detail!.priceLevel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MapDesign.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                runAlignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MapDesign.brandSurface,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      text.t(venue.kind.label),
                      style: const TextStyle(
                        color: MapDesign.brand,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  for (final tag in venue.tags.take(4))
                    VenueTag(label: text.t(tag)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _VenueActionBar(
              favorite: favorite,
              onToggleFavorite: onToggleFavorite,
              onNavigate: onNavigate,
            ),
          ],
        ),
      ],
    );
  }
}

/// 标签行末尾的收藏与导航快捷操作。
class _VenueActionBar extends StatelessWidget {
  /// 创建快捷操作区。
  const _VenueActionBar({
    required this.favorite,
    required this.onToggleFavorite,
    required this.onNavigate,
  });

  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionCircleButton(
          icon: favorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          tooltip: text.t(favorite ? '已收藏' : '收藏'),
          selected: favorite,
          onTap: onToggleFavorite,
        ),
        const SizedBox(width: 8),
        _ActionCircleButton(
          icon: Icons.near_me_rounded,
          tooltip: text.t('导航'),
          onTap: onNavigate,
        ),
      ],
    );
  }
}

/// 单个圆形快捷操作按钮。
class _ActionCircleButton extends StatelessWidget {
  /// 创建操作按钮。
  const _ActionCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? MapDesign.brandSurface : const Color(0xFFF7F3F6),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              icon,
              color: selected ? MapDesign.brand : MapDesign.ink,
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

/// 信息卡：营业状态、地址、电话合并到同一块浅色卡片里，
/// 替代原先各自独立的「营业时间」「地点位置」两个 section。
class _VenueInfoCard extends StatelessWidget {
  /// 创建信息卡。
  const _VenueInfoCard({
    required this.detail,
    required this.onContribute,
    required this.onOpenMap,
    required this.addressActionLabel,
    required this.onCall,
  });

  final VenueDetail? detail;
  final VoidCallback onContribute;
  final VoidCallback onOpenMap;
  final String addressActionLabel;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final data = detail;
    final text = SiponLanguageScope.textOf(context);

    if (data == null) {
      return const _PlaceholderBlock(width: double.infinity, height: 148);
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5F8),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OpenStatusRow(detail: data, onContribute: onContribute),
          const Divider(
            height: 1,
            thickness: 1,
            indent: 62,
            color: MapDesign.hairline,
          ),
          _InfoTile(
            icon: Icons.location_on_outlined,
            title: text.t(data.venue.address),
            subtitle: text.t(data.venue.distance),
            trailingLabel: text.t(addressActionLabel),
            titleMaxLines: null,
            onTap: onOpenMap,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            indent: 62,
            color: MapDesign.hairline,
          ),
          _InfoTile(
            icon: Icons.phone_outlined,
            title: data.phone,
            subtitle: text.t('点击拨打'),
            onTap: onCall,
          ),
        ],
      ),
    );
  }
}

/// 信息卡顶部的营业状态行。
class _OpenStatusRow extends StatelessWidget {
  /// 创建营业状态行。
  const _OpenStatusRow({required this.detail, required this.onContribute});

  final VenueDetail detail;

  /// 点击行尾「补充信息」按钮的回调。
  final VoidCallback onContribute;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    final statusColor = detail.openNow ? MapDesign.success : MapDesign.alert;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 15, 10, 15),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            detail.openNow ? text.t('营业中') : text.t('已打烊'),
            style: TextStyle(
              color: statusColor,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '·',
            style: TextStyle(
              color: MapDesign.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${text.t(detail.todayKey)} ${detail.todayHoursLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MapDesign.muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ContributePillButton(label: text.t('补充信息'), onTap: onContribute),
        ],
      ),
    );
  }
}

/// 「补充信息」胶囊按钮：营业时间行尾与共建引导插画共用。
class _ContributePillButton extends StatelessWidget {
  /// 创建补充信息按钮。
  const _ContributePillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // edit_note 传达「帮忙修订/补全信息」，比加号更贴共建语义。
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: Color(0x2E9A3D78))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.edit_note_rounded,
                color: MapDesign.brand,
                size: 17,
              ),
              const SizedBox(width: 2),
              Text(
                label,
                style: const TextStyle(
                  color: MapDesign.brand,
                  fontSize: 11,
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

/// 信息卡里的一行（地址 / 电话）。
class _InfoTile extends StatelessWidget {
  /// 创建信息行。
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingLabel,
    this.titleMaxLines = 2,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? trailingLabel;
  final int? titleMaxLines;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: MapDesign.brand, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: titleMaxLines,
                    overflow: titleMaxLines == null
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 13.5,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: MapDesign.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailingLabel case final label?) ...[
                  Text(
                    label,
                    style: const TextStyle(
                      color: MapDesign.brand,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
                const Icon(
                  Icons.chevron_right_rounded,
                  color: MapDesign.muted,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 酒吧简介 + 特色标签。未加载完成时显示占位行。
class _VenueAbout extends StatelessWidget {
  /// 创建简介区。
  const _VenueAbout({this.detail, this.onContribute});

  final VenueDetail? detail;

  /// 空信息时引导用户共建补充的入口。
  final VoidCallback? onContribute;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final paragraphs = detail?.description;
    final features = detail?.features ?? const <String>[];

    if (paragraphs == null) {
      return const _PlaceholderBlock(width: double.infinity, height: 66);
    }
    if (paragraphs.isEmpty) {
      return _ContributionHint(
        icon: Icons.local_bar_rounded,
        title: text.t('还没有介绍'),
        subtitle: text.t('写下这里的氛围与特色，帮大家种草'),
        onTap: onContribute,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              text.t(paragraph),
              style: const TextStyle(
                color: MapDesign.ink,
                fontSize: 13.5,
                height: 1.65,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ),
        if (features.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final feature in features)
                _FeatureChip(label: text.t(feature)),
            ],
          ),
        ],
      ],
    );
  }
}

/// 特色标签小胶囊。
class _FeatureChip extends StatelessWidget {
  /// 创建特色标签。
  const _FeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: MapDesign.hairline),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, color: MapDesign.brand, size: 15),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              color: MapDesign.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// 地点最新动态列表。
class _VenueLatestUpdates extends StatelessWidget {
  const _VenueLatestUpdates({
    required this.updates,
    this.loaded = true,
    this.onContribute,
    this.headingKey,
  });

  final List<String> updates;

  /// 详情是否已加载完成；未完成时保持占位块，加载后仍为空才展示引导。
  final bool loaded;

  /// 空信息时引导用户共建补充的入口。
  final VoidCallback? onContribute;

  final Key? headingKey;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: headingKey,
          text.t('最新动态'),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (updates.isEmpty && !loaded)
          const _PlaceholderBlock(width: double.infinity, height: 56)
        else if (updates.isEmpty)
          _ContributionHint(
            icon: Icons.campaign_rounded,
            title: text.t('还没有动态'),
            subtitle: text.t('分享这里的最新活动与消息'),
            onTap: onContribute,
          )
        else
          for (final update in updates)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, color: MapDesign.brand, size: 7),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      text.t(update),
                      style: const TextStyle(
                        color: MapDesign.ink,
                        fontSize: 13.5,
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// 招牌酒款横向滚动列表，单卡保持 3:4 纵向比例。
class _VenueDrinks extends StatelessWidget {
  /// 创建酒款列表。
  const _VenueDrinks({
    required this.drinks,
    this.loaded = true,
    this.onContribute,
    this.headingKey,
  });

  final List<VenueDrink> drinks;

  /// 详情是否已加载完成；未完成时保持占位块，加载后仍为空才展示引导。
  final bool loaded;

  /// 空信息时引导用户共建补充的入口。
  final VoidCallback? onContribute;

  /// 板块小标题的 key，供 tab 跳转时测量标题高度。
  final Key? headingKey;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key: headingKey,
          text.t('菜单'),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (drinks.isEmpty && !loaded)
          const _PlaceholderBlock(width: double.infinity, height: 132)
        else if (drinks.isEmpty)
          _ContributionHint(
            icon: Icons.wine_bar_rounded,
            title: text.t('还没有菜单'),
            subtitle: text.t('拍张菜单或补充招牌酒款'),
            onTap: onContribute,
          )
        else
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: drinks.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final drink = drinks[index];

                return Container(
                  width: 186,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: MapDesign.hairline),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(
                        builder: (_) {
                          final path =
                              drink.imageAsset ??
                              MapAssets.coverForIndex(index);
                          final remote = _isRemoteImage(path);
                          return VenueImage(
                            imageUrl: remote ? path : null,
                            assetPath: remote
                                ? MapAssets.coverForIndex(index)
                                : path,
                            width: double.infinity,
                            height: 132,
                          );
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      text.t(drink.name),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: MapDesign.ink,
                                        fontSize: 14,
                                        height: 1.25,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    drink.price,
                                    style: const TextStyle(
                                      color: MapDesign.brand,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                text.t(drink.description),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: MapDesign.muted,
                                  fontSize: 11.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
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
              },
            ),
          ),
      ],
    );
  }
}

String _relativeReviewDate(VenueReview review, SiponAppText text) {
  final createdAt = review.createdAt;
  if (createdAt == null) {
    return text.t('时间未知');
  }

  final days = DateTime.now().difference(createdAt).inDays.clamp(0, 36500);
  if (days < 30) {
    return '$days${text.t('天前')}';
  }
  if (days < 365) {
    return '${days ~/ 30}${text.t('月前')}';
  }
  return '${days ~/ 365}${text.t('年前')}';
}

/// 评价列表的筛选方式。
enum _ReviewFilter { relevant, highest, newest, oldest }

/// 用户评价区：顶部显示总分统计，条目之间用细分隔线。
class _VenueReviewsSection extends StatelessWidget {
  /// 创建用户评价区。
  const _VenueReviewsSection({
    required this.reviews,
    required this.totalCount,
    required this.hasMoreReviews,
    required this.reviewsLoading,
    this.loaded = true,
    this.onContribute,
    required this.sort,
    required this.onSortChanged,
    required this.onAddReview,
    required this.onViewMore,
    required this.onReviewReaction,
    required this.onReviewReport,
    this.headingKey,
  });

  /// 已加载的评价列表。
  final List<VenueReview> reviews;

  /// 评价总数（用于顶部统计展示）。
  final int totalCount;

  /// 是否还有下一页可加载。
  final bool hasMoreReviews;

  /// 正在翻页加载评价。
  final bool reviewsLoading;

  /// 详情是否已加载完成；未完成时保持占位块，加载后仍无评价才展示引导。
  final bool loaded;

  /// 无评价时引导用户共建补充的入口。
  final VoidCallback? onContribute;

  final _ReviewFilter sort;
  final ValueChanged<_ReviewFilter> onSortChanged;
  final VoidCallback onAddReview;
  final VoidCallback onViewMore;

  /// 评价点赞/点踩，[reaction] 为 null 表示取消表态。
  final Future<void> Function(VenueReview review, String? reaction)
  onReviewReaction;

  /// 评价举报。
  final Future<void> Function(VenueReview review) onReviewReport;

  /// 板块小标题的 key，供 tab 跳转时测量标题高度。
  final Key? headingKey;

  /// 优先使用服务端时间，兼容旧数据里的 `YYYY-M-DD` 文案。
  static DateTime _parseDate(VenueReview review) {
    if (review.createdAt != null) return review.createdAt!;
    final date = review.date;
    final parts = date.split('-');
    if (parts.length != 3) return DateTime(1970);
    return DateTime.tryParse(
          '${parts[0].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-'
          '${parts[2].padLeft(2, '0')}',
        ) ??
        DateTime(1970);
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final averageRating = reviews.isEmpty
        ? null
        : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
    var filteredReviews = [...reviews];
    switch (sort) {
      case _ReviewFilter.relevant:
        filteredReviews.sort((a, b) => b.likeCount.compareTo(a.likeCount));
      case _ReviewFilter.highest:
        filteredReviews.sort((a, b) => b.rating.compareTo(a.rating));
      case _ReviewFilter.newest:
        filteredReviews.sort((a, b) => _parseDate(b).compareTo(_parseDate(a)));
      case _ReviewFilter.oldest:
        filteredReviews.sort((a, b) => _parseDate(a).compareTo(_parseDate(b)));
    }
    // 已加载即全量展示，翻页加载的新评价直接追加到列表尾部。
    final visibleReviews = filteredReviews;
    final filterButton = PopupMenuButton<_ReviewFilter>(
      initialValue: sort,
      position: PopupMenuPosition.under,
      onSelected: onSortChanged,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ReviewFilter.relevant,
          child: Text(text.t('最相关')),
        ),
        PopupMenuItem(
          value: _ReviewFilter.highest,
          child: Text(text.t('评分从高到低')),
        ),
        PopupMenuItem(
          value: _ReviewFilter.newest,
          child: Text(text.t('最新到最旧')),
        ),
        PopupMenuItem(
          value: _ReviewFilter.oldest,
          child: Text(text.t('最旧到最新')),
        ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F3F6),
          border: Border.all(color: MapDesign.hairline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.filter_list_rounded,
              color: MapDesign.brand,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              text.t('筛选'),
              style: const TextStyle(
                color: MapDesign.ink,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: MapDesign.muted,
              size: 17,
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                key: headingKey,
                text.t('评价'),
                style: const TextStyle(
                  color: MapDesign.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (averageRating != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F5F8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Text(
                  averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                    color: MapDesign.brand,
                    fontSize: 32,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 8),
                _RatingStars(rating: averageRating, starSize: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$totalCount ${text.t('条评价')}',
                              style: const TextStyle(
                                color: MapDesign.muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          filterButton,
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: onAddReview,
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: Text(text.t('添加评论')),
              style: OutlinedButton.styleFrom(
                foregroundColor: MapDesign.brand,
                side: const BorderSide(color: MapDesign.brand),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (reviews.isEmpty && loaded && totalCount == 0)
          _ContributionHint(
            icon: Icons.rate_review_rounded,
            title: text.t('还没有评价'),
            subtitle: text.t('说说你的微醺体验，给后来人参考'),
            onTap: onContribute,
          )
        else if (reviews.isEmpty)
          const _PlaceholderBlock(width: double.infinity, height: 72)
        else ...[
          for (var i = 0; i < visibleReviews.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 12),
                color: MapDesign.hairline,
              ),
            _ReviewItem(
              review: visibleReviews[i],
              onReaction: onReviewReaction,
              onReport: onReviewReport,
            ),
          ],
          if (hasMoreReviews) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: reviewsLoading ? null : onViewMore,
                style: TextButton.styleFrom(
                  foregroundColor: MapDesign.brand,
                  disabledForegroundColor: MapDesign.brand,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                icon: reviewsLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MapDesign.brand,
                        ),
                      )
                    : const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                label: Text(text.t('更多评论')),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// 单条用户评价。
class _ReviewItem extends StatefulWidget {
  /// 创建单条评价。
  const _ReviewItem({
    required this.review,
    required this.onReaction,
    required this.onReport,
  });

  final VenueReview review;

  /// 点赞/点踩回调；[reaction] 为 `like`/`dislike`，null 表示取消表态。
  final Future<void> Function(VenueReview review, String? reaction) onReaction;

  /// 举报回调。
  final Future<void> Function(VenueReview review) onReport;

  @override
  State<_ReviewItem> createState() => _ReviewItemState();
}

enum _ReviewReaction { none, like, dislike }

class _ReviewItemState extends State<_ReviewItem> {
  /// 互动请求进行中时屏蔽重复点击。
  bool _submitting = false;

  /// 反应状态由数据驱动，[myReaction] 为 null 表示未表态。
  _ReviewReaction get _reaction => switch (widget.review.myReaction) {
    'like' => _ReviewReaction.like,
    'dislike' => _ReviewReaction.dislike,
    _ => _ReviewReaction.none,
  };

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final review = widget.review;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipOval(child: _buildAvatar(review)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    review.nickname,
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _relativeReviewDate(review, text),
                    style: const TextStyle(
                      color: MapDesign.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              review.rating.toStringAsFixed(1),
              style: const TextStyle(
                color: MapDesign.ink,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 2),
            _RatingStars(rating: review.rating, starSize: 13),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text.t(review.content),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 13,
            height: 1.55,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        if (review.imageAssets.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: review.imageAssets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final path = review.imageAssets[index];
                final remote = _isRemoteImage(path);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: VenueImage(
                    imageUrl: remote ? path : null,
                    assetPath: remote ? MapAssets.coverForIndex(index) : path,
                    width: 112,
                    height: 92,
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReviewActionButton(
                icon: _reaction == _ReviewReaction.like
                    ? Icons.thumb_up_rounded
                    : Icons.thumb_up_outlined,
                label: text.t('点赞'),
                count: review.likeCount,
                selected: _reaction == _ReviewReaction.like,
                onTap: () => _toggleReaction(_ReviewReaction.like),
              ),
              const SizedBox(width: 12),
              _ReviewActionButton(
                icon: _reaction == _ReviewReaction.dislike
                    ? Icons.thumb_down_rounded
                    : Icons.thumb_down_outlined,
                label: text.t('点踩'),
                selected: _reaction == _ReviewReaction.dislike,
                onTap: () => _toggleReaction(_ReviewReaction.dislike),
              ),
              const SizedBox(width: 12),
              _ReviewActionButton(
                icon: Icons.flag_outlined,
                label: text.t('举报'),
                onTap: () => widget.onReport(review),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 同一反应再次点击表示取消，交由父级落库后回传数据。
  Future<void> _toggleReaction(_ReviewReaction reaction) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onReaction(
        widget.review,
        _reaction == reaction ? null : reaction.name,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 头像：网络图优先，加载失败或缺失时用默认占位。
  Widget _buildAvatar(VenueReview review) {
    final avatar = review.avatarAsset;
    if (avatar == null || avatar.isEmpty) {
      return _defaultAvatar();
    }
    if (_isRemoteImage(avatar)) {
      return SiponNetworkImage(
        url: avatar,
        width: 36,
        height: 36,
        fallbackWidget: _defaultAvatar(),
      );
    }
    return Image.asset(
      avatar,
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _defaultAvatar(),
    );
  }

  /// 默认头像占位。
  Widget _defaultAvatar() {
    return Container(
      width: 36,
      height: 36,
      color: MapDesign.brandSurface,
      child: const Icon(Icons.person_outline, color: MapDesign.brand, size: 20),
    );
  }
}

class _ReviewActionButton extends StatelessWidget {
  const _ReviewActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.count,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? MapDesign.brand : MapDesign.muted,
              ),
              if (count != null) ...[
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: TextStyle(
                    color: selected ? MapDesign.brand : MapDesign.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 数据加载中的占位块。
class _PlaceholderBlock extends StatelessWidget {
  /// 创建占位块。
  const _PlaceholderBlock({required this.width, this.height = 16});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MapDesign.hairline,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

/// 空信息时的共建引导：纯 Flutter 绘制的轻量插画 + 文案 + 补充入口。
///
/// 项目内没有插画图片资源，这里用图标组合出「卡片 + 闪光」的画面，
/// 各板块通过 [icon] 区分主题（介绍/动态/菜单/评价）。
class _ContributionHint extends StatelessWidget {
  /// 创建共建引导插画。
  const _ContributionHint({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  /// 插画主图标，表达当前缺失内容的主题。
  final IconData icon;
  final String title;
  final String subtitle;

  /// 点击「补充信息」的回调。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildIllustration(),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: MapDesign.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MapDesign.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          _ContributePillButton(label: text.t('补充信息'), onTap: onTap ?? () {}),
        ],
      ),
    );
  }

  /// 中央插画：渐变圆底 + 主题图标，四周用小圆点与星光点缀。
  Widget _buildIllustration() {
    return SizedBox(
      width: 96,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 2,
            child: Container(
              width: 52,
              height: 8,
              decoration: BoxDecoration(
                color: MapDesign.hairline,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFEDF7), Color(0xFFFFF8FB)],
              ),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x149A3D78)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x149A3D78),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: MapDesign.brand, size: 26),
          ),
          const Positioned(
            top: 0,
            right: 20,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFD9A8C7),
              size: 15,
            ),
          ),
          const Positioned(
            bottom: 10,
            left: 20,
            child: Icon(
              Icons.auto_awesome_rounded,
              color: Color(0x669A3D78),
              size: 11,
            ),
          ),
          Positioned(
            top: 12,
            left: 14,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0x409A3D78),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: 14,
            right: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0x269A3D78),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 五颗星评分展示，始终渲染 5 颗星并按评分填充实星、半星与空星。
class _RatingStars extends StatelessWidget {
  /// 创建评分星星组。
  const _RatingStars({required this.rating, this.starSize = 14});

  /// 评分（0-5，支持小数）。
  final double rating;

  /// 单颗星星的尺寸。
  final double starSize;

  IconData _starIcon(int index) {
    final filled = rating.clamp(0.0, 5.0) - index;
    if (filled >= 0.75) return Icons.star_rounded;
    if (filled >= 0.25) return Icons.star_half_rounded;
    return Icons.star_border_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(_starIcon(i), color: MapDesign.brand, size: starSize),
      ],
    );
  }
}

/// 举报原因：`code` 作为接口 `reason` 上报，`label` 用于展示与 `details`。
class _ReportReason {
  const _ReportReason(this.code, this.label);

  final String code;
  final String label;
}

const List<_ReportReason> _reportReasons = [
  _ReportReason('spam', '垃圾广告'),
  _ReportReason('abuse', '辱骂攻击'),
  _ReportReason('false_info', '虚假信息'),
  _ReportReason('porn', '色情低俗'),
  _ReportReason('other', '其他'),
];

/// 举报原因选择面板：点选后把原因回传给调用方提交。
class _ReportReasonSheet extends StatelessWidget {
  const _ReportReasonSheet();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              text.t('举报该评价'),
              style: const TextStyle(
                color: MapDesign.ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          for (final reason in _reportReasons)
            ListTile(
              onTap: () => Navigator.of(context).pop(reason),
              title: Center(
                child: Text(
                  text.t(reason.label),
                  style: const TextStyle(
                    color: MapDesign.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
