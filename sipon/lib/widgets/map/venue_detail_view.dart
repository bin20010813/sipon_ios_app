import 'package:flutter/material.dart' hide Visibility;

import '../../pages/language_transform.dart';
import '../../services/map/map_models.dart';
import '../../services/map/mock_venue_detail_repository.dart';
import '../../services/map/venue_detail_models.dart';
import 'map_theme.dart';
import 'venue_common.dart';

/// 展开态的详情内容。
///
/// 由 [VenueSheetSurface] 里唯一的滚动视图承载，方便整体做透明度动画。
/// 目前后端详情接口尚未接入，内部通过 [MockVenueDetailRepository] 获取 Mock 数据。
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

  @override
  State<VenueDetailContent> createState() => _VenueDetailContentState();
}

class _VenueDetailContentState extends State<VenueDetailContent> {
  static const double _pagePadding = 20;
  static const double _tabsHeight = 56;

  /// Mock 详情数据源。
  final MockVenueDetailRepository _repository =
      const MockVenueDetailRepository();

  /// 当前加载到的详情数据。
  VenueDetail? _detail;

  bool _favorite = false;
  int _galleryPage = 0;
  int _detailTabIndex = 0;
  int _visibleReviewCount = 5;
  _ReviewFilter _reviewFilter = _ReviewFilter.standard;
  bool _scrollingToTab = false;
  bool _tabsPinned = false;
  final GlobalKey _scrollViewKey = GlobalKey();
  final GlobalKey _tabsKey = GlobalKey();
  final List<GlobalKey> _sectionKeys = List.generate(3, (_) => GlobalKey());
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
      _favorite = false;
      _galleryPage = 0;
      _detailTabIndex = 0;
      _visibleReviewCount = 5;
      _tabsPinned = false;
      _loadDetail();
    }
  }

  /// 异步加载当前酒吧的详情数据。
  Future<void> _loadDetail() async {
    final detail = await _repository.fetchDetail(widget.venue);
    if (mounted) {
      setState(() {
        _detail = detail;
      });
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
      1 => _measureHeading(_drinksHeadingKey),
      2 => _measureHeading(_reviewsHeadingKey),
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

  void _showMoreReviews() {
    final reviewCount = _detail?.reviews.length ?? 0;
    if (_visibleReviewCount >= reviewCount) {
      return;
    }

    final previousOffset = widget.scrollController.offset;
    _scrollingToTab = true;
    setState(() {
      _detailTabIndex = 2;
      final nextCount = _visibleReviewCount + 3;
      _visibleReviewCount = nextCount < reviewCount ? nextCount : reviewCount;
    });
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
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomScrollView(
          key: _scrollViewKey,
          controller: widget.scrollController,
          physics: const BouncingScrollPhysics(
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

  /// 沉浸式封面轮播：关闭按钮与页码悬浮在图上，不再单独占一行。
  Widget _buildHero(BuildContext context) {
    final images = _detail?.gallery ?? [widget.venue.imageAsset];
    final showPageBadge = images.length > 1;

    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: PageView.builder(
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _galleryPage = index),
            itemBuilder: (context, index) {
              return VenueImage(
                imageUrl: null,
                assetPath: images[index],
                width: double.infinity,
                height: double.infinity,
              );
            },
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
            onToggleFavorite: () => setState(() => _favorite = !_favorite),
            onNavigate: () => _showMockToast(text.t('已唤起地图导航（演示）')),
            onShare: () => _showMockToast(text.t('已分享地点（演示）')),
          ),
          const SizedBox(height: 18),
          _VenueInfoCard(
            detail: detail,
            onOpenMap: () => _showMockToast(text.t('已唤起地图导航（演示）')),
            onCall: () =>
                _showMockToast(text.t('正在拨打 ${detail?.phone ?? ''}（演示）')),
          ),
        ],
      ),
    );
  }

  /// 三个板块连续排列，滚动位置与吸顶标签双向联动。
  Widget _buildSections(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final detail = _detail;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _pagePadding,
        18,
        _pagePadding,
        widget.bottomOverlayInset + MediaQuery.paddingOf(context).bottom + 24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: _sectionKeys[0],
            child: _VenueAbout(detail: detail),
          ),
          const SizedBox(height: 35),
          KeyedSubtree(
            key: _sectionKeys[1],
            child: _VenueDrinks(
              drinks: detail?.signatureDrinks ?? const [],
              headingKey: _drinksHeadingKey,
            ),
          ),
          const SizedBox(height: 35),
          KeyedSubtree(
            key: _sectionKeys[2],
            child: _VenueReviewsSection(
              reviews: detail?.reviews ?? const [],
              visibleCount: _visibleReviewCount,
              totalCount: detail?.reviewCount ?? 0,
              sort: _reviewFilter,
              onSortChanged: (filter) => setState(() => _reviewFilter = filter),
              onAddReview: () => _showMockToast(text.t('评论发布功能开发中（演示）')),
              onViewMore: _showMoreReviews,
              headingKey: _reviewsHeadingKey,
            ),
          ),
        ],
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
    final labels = [text.t('关于'), text.t('招牌酒款'), text.t('评价')];

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          labels[index],
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
            ),
        ],
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
    required this.onShare,
  });

  final MapVenue venue;
  final VenueDetail? detail;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onNavigate;
  final VoidCallback onShare;

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
              onShare: onShare,
            ),
          ],
        ),
      ],
    );
  }
}

/// 标签行末尾的收藏、导航与分享快捷操作。
class _VenueActionBar extends StatelessWidget {
  /// 创建快捷操作区。
  const _VenueActionBar({
    required this.favorite,
    required this.onToggleFavorite,
    required this.onNavigate,
    required this.onShare,
  });

  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onNavigate;
  final VoidCallback onShare;

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
        const SizedBox(width: 8),
        _ActionCircleButton(
          icon: Icons.ios_share_rounded,
          tooltip: text.t('分享'),
          onTap: onShare,
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
    required this.onOpenMap,
    required this.onCall,
  });

  final VenueDetail? detail;
  final VoidCallback onOpenMap;
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
          _OpenStatusRow(detail: data),
          const Divider(
            height: 1,
            thickness: 1,
            indent: 62,
            color: MapDesign.hairline,
          ),
          _InfoTile(
            icon: Icons.location_on_outlined,
            title: text.t(data.venue.address),
            subtitle: '${text.t(data.venue.distance)} · ${text.t('点击导航')}',
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
  const _OpenStatusRow({required this.detail});

  final VenueDetail detail;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    final statusColor = detail.openNow ? MapDesign.success : MapDesign.alert;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
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
        ],
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
            const Icon(
              Icons.chevron_right_rounded,
              color: MapDesign.muted,
              size: 20,
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
  const _VenueAbout({this.detail});

  final VenueDetail? detail;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final paragraphs = detail?.description;
    final features = detail?.features ?? const <String>[];

    if (paragraphs == null || paragraphs.isEmpty) {
      return const _PlaceholderBlock(width: double.infinity, height: 66);
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

/// 招牌酒款横向滚动列表，单卡保持 3:4 纵向比例。
class _VenueDrinks extends StatelessWidget {
  /// 创建酒款列表。
  const _VenueDrinks({required this.drinks, this.headingKey});

  final List<VenueDrink> drinks;

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
          text.t('招牌酒款'),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        if (drinks.isEmpty)
          const _PlaceholderBlock(width: double.infinity, height: 132)
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
                      VenueImage(
                        imageUrl: null,
                        assetPath:
                            drink.imageAsset ?? MapAssets.coverForIndex(index),
                        width: double.infinity,
                        height: 132,
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

/// 评价列表的筛选方式。
enum _ReviewFilter { standard, withImages, newest, good, bad }

/// 用户评价区：顶部显示总分统计，条目之间用细分隔线。
class _VenueReviewsSection extends StatelessWidget {
  /// 创建用户评价区。
  const _VenueReviewsSection({
    required this.reviews,
    required this.visibleCount,
    required this.totalCount,
    required this.sort,
    required this.onSortChanged,
    required this.onAddReview,
    required this.onViewMore,
    this.headingKey,
  });

  final List<VenueReview> reviews;
  final int visibleCount;
  final int totalCount;
  final _ReviewFilter sort;
  final ValueChanged<_ReviewFilter> onSortChanged;
  final VoidCallback onAddReview;
  final VoidCallback onViewMore;

  /// 板块小标题的 key，供 tab 跳转时测量标题高度。
  final Key? headingKey;

  /// 解析 `YYYY-M-DD` 形式的评价日期，解析失败时回退到最早时间。
  static DateTime _parseDate(String date) {
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
      case _ReviewFilter.standard:
        break;
      case _ReviewFilter.withImages:
        filteredReviews = filteredReviews
            .where((review) => review.imageAssets.isNotEmpty)
            .toList();
      case _ReviewFilter.newest:
        filteredReviews.sort(
          (a, b) => _parseDate(b.date).compareTo(_parseDate(a.date)),
        );
      case _ReviewFilter.good:
        filteredReviews = filteredReviews
            .where((review) => review.rating >= 4)
            .toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));
      case _ReviewFilter.bad:
        filteredReviews = filteredReviews
            .where((review) => review.rating < 3)
            .toList()
          ..sort((a, b) => a.rating.compareTo(b.rating));
    }
    final visibleReviews = filteredReviews.take(visibleCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: headingKey,
          text.t('评价'),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
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
                  child: Text(
                    text.t('综合评分'),
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                Text(
                  '$totalCount ${text.t('条评价')}',
                  style: const TextStyle(
                    color: MapDesign.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _ReviewFilterChip(
                  label: text.t('默认'),
                  selected: sort == _ReviewFilter.standard,
                  onTap: () => onSortChanged(_ReviewFilter.standard),
                ),
                const SizedBox(width: 8),
                _ReviewFilterChip(
                  label: text.t('带图'),
                  icon: Icons.image_outlined,
                  selected: sort == _ReviewFilter.withImages,
                  onTap: () => onSortChanged(_ReviewFilter.withImages),
                ),
                const SizedBox(width: 8),
                _ReviewFilterChip(
                  label: text.t('最新'),
                  icon: Icons.schedule_rounded,
                  selected: sort == _ReviewFilter.newest,
                  onTap: () => onSortChanged(_ReviewFilter.newest),
                ),
                const SizedBox(width: 8),
                _ReviewFilterChip(
                  label: text.t('好评'),
                  selected: sort == _ReviewFilter.good,
                  onTap: () => onSortChanged(_ReviewFilter.good),
                ),
                const SizedBox(width: 8),
                _ReviewFilterChip(
                  label: text.t('差评'),
                  selected: sort == _ReviewFilter.bad,
                  onTap: () => onSortChanged(_ReviewFilter.bad),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
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
        if (reviews.isEmpty)
          const _PlaceholderBlock(width: double.infinity, height: 72)
        else ...[
          for (var i = 0; i < visibleReviews.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 12),
                color: MapDesign.hairline,
              ),
            _ReviewItem(review: visibleReviews[i]),
          ],
          if (visibleCount < reviews.length) ...[
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: onViewMore,
                style: TextButton.styleFrom(
                  foregroundColor: MapDesign.brand,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                label: Text(text.t('更多评论')),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// 评价筛选的选项胶囊。
class _ReviewFilterChip extends StatelessWidget {
  /// 创建筛选胶囊。
  const _ReviewFilterChip({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: selected ? MapDesign.brandSurface : const Color(0xFFF7F3F6),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? MapDesign.brand : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? MapDesign.brand : MapDesign.muted,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? MapDesign.brand : MapDesign.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
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

/// 单条用户评价。
class _ReviewItem extends StatelessWidget {
  /// 创建单条评价。
  const _ReviewItem({required this.review});

  final VenueReview review;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ClipOval(
              child: review.avatarAsset != null
                  ? Image.asset(
                      review.avatarAsset!,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _defaultAvatar(),
                    )
                  : _defaultAvatar(),
            ),
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
                    review.date,
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
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: VenueImage(
                    imageUrl: null,
                    assetPath: review.imageAssets[index],
                    width: 112,
                    height: 92,
                  ),
                );
              },
            ),
          ),
        ],
      ],
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
