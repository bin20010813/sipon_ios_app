import 'dart:math' as math;

import 'package:flutter/material.dart' hide Visibility;

import '../../pages/language_transform.dart';
import '../../services/map/map_models.dart';
import 'map_theme.dart';
import 'venue_common.dart';
import 'venue_detail_view.dart';

/// 收起态卡片与展开态详情共用的同一块面板。
///
/// 尺寸、位置、圆角、阴影全部由 [progress] / [fullscreenProgress] 连续插值，
/// 两套内容错开淡化（互不重叠），因此看到的是"卡片长成面板"而不是"两个控件互换"。
class VenueSheetSurface extends StatelessWidget {
  const VenueSheetSurface({
    super.key,
    required this.venue,
    required this.scrollController,
    required this.progress,
    required this.fullscreenProgress,
    required this.collapsedBottomGap,
    required this.bottomOverlayInset,
    required this.onExpand,
    required this.onCollapse,
  });

  /// 收起态卡片的最大宽度，与顶部搜索栏保持一致。
  static const double _collapsedMaxWidth = 430;
  static const double _collapsedSideInset = 14;
  static const double _cornerRadius = 18;

  /// 收起态内容淡出的区间上限；展开态内容从这里才开始淡入，两者不同时可见。
  static const double _contentSwapPoint = 0.28;

  /// 展开态内容淡入所占的区间长度（从 [_contentSwapPoint] 起算）。
  static const double _contentFadeInSpan = 0.5;

  /// 当前视野一家酒吧都没有时为 null，此时面板只显示一句提示、也不能展开。
  final MapVenue? venue;
  final ScrollController scrollController;
  final double progress;
  final double fullscreenProgress;
  final double collapsedBottomGap;
  final double bottomOverlayInset;
  final VoidCallback onExpand;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final selected = venue;
    final collapsed = progress < 0.02;
    final collapsedOpacity = 1 - mapClamp01(progress / _contentSwapPoint);
    final expandedOpacity = mapClamp01(
      (progress - _contentSwapPoint) / _contentFadeInSpan,
    );
    final collapsedSideInset = math.max(
      _collapsedSideInset,
      (MediaQuery.sizeOf(context).width - _collapsedMaxWidth) / 2,
    );
    final sideInset = mapLerp(collapsedSideInset, 0, progress);
    final topInset = MediaQuery.paddingOf(context).top * fullscreenProgress;

    return Padding(
      padding: EdgeInsets.only(
        left: sideInset,
        right: sideInset,
        bottom: mapLerp(collapsedBottomGap, 0, progress),
      ),
      child: Material(
        color: Colors.white,
        elevation: mapLerp(10, 12, progress),
        shadowColor: Color.lerp(
          const Color(0x52000000),
          const Color(0x29000000),
          progress,
        ),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(mapLerp(_cornerRadius, 0, fullscreenProgress)),
          bottom: Radius.circular(mapLerp(_cornerRadius, 0, progress)),
        ),
        clipBehavior: Clip.antiAlias,
        // Material 内部对 elevation / 圆角 / 阴影带 200ms 隐式动画。这里的值本来
        // 就是逐帧插出来的，再套一层隐式动画只会让阴影和圆角追不上面板，所以关掉。
        animationDuration: Duration.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            selected == null
                ? CustomScrollView(
                    controller: scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: const [SliverFillRemaining()],
                  )
                : VenueDetailContent(
                    venue: selected,
                    scrollController: scrollController,
                    opacity: expandedOpacity,
                    topInset: topInset,
                    bottomOverlayInset: bottomOverlayInset,
                    onClose: onCollapse,
                  ),
            // 收起态内容钉在面板顶部，不随内部滚动移动，因此不受滚动偏移影响。
            if (collapsedOpacity > 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _VenueSheetLayer(
                  opacity: collapsedOpacity,
                  interactive: false,
                  child: selected == null
                      ? const _VenueSheetEmptyContent()
                      : _VenueSummaryContent(venue: selected),
                ),
              ),
            // 唯一的拖拽手柄，两个状态共享，避免交叉淡化时闪一下。
            Positioned(
              top: topInset + 8,
              left: 0,
              right: 0,
              child: const IgnorePointer(
                child: Center(child: _VenueSheetDragHandle()),
              ),
            ),
            // 收起态下整块卡片都能点开。translucent 的意思是"我要参与手势竞技场，
            // 但不吞掉命中结果"：这一层拿到 tap，同时下面的滚动视图照样收到事件，
            // 所以静止点击走 onExpand，手指一移动就由 sheet 的拖拽识别器接管。
            if (collapsed && selected != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: onExpand,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 按透明度淡入淡出的一层内容。淡到看不清时就不再参与命中测试与无障碍朗读，
/// 避免两套内容在交叉区互相抢事件。
class _VenueSheetLayer extends StatelessWidget {
  const _VenueSheetLayer({
    required this.opacity,
    required this.child,
    this.interactive = true,
  });

  final double opacity;
  final Widget child;

  /// 为 false 时这一层永不接收指针事件（收起态内容只负责展示，点击交给下层面板）。
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final visible = opacity >= 0.5;

    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible || !interactive,
        child: Opacity(opacity: opacity, child: child),
      ),
    );
  }
}

class _VenueSheetDragHandle extends StatelessWidget {
  const _VenueSheetDragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 5,
      decoration: BoxDecoration(
        color: const Color(0xFFD2D0D2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// 视野里没有酒吧时的占位内容。原来这条分支根本到不了（永远兜底 4 家精选），
/// 现在平移到郊区就会真的看到它。
class _VenueSheetEmptyContent extends StatelessWidget {
  const _VenueSheetEmptyContent();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 27, 18, 16),
      child: SizedBox(
        height: 102,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.travel_explore_outlined,
              color: MapDesign.muted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              text.t('当前视野暂无可展示酒吧'),
              style: const TextStyle(
                color: MapDesign.ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text.t('试着缩小地图或者换个分类看看'),
              style: const TextStyle(
                color: MapDesign.muted,
                fontSize: 12,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VenueSummaryContent extends StatelessWidget {
  const _VenueSummaryContent({required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Padding(
      // 顶部 27 = 手柄上边距 8 + 手柄高 5 + 手柄与内容间距 14
      padding: const EdgeInsets.fromLTRB(18, 27, 18, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: VenueImage(
              imageUrl: venue.imageUrl,
              assetPath: venue.imageAsset,
              width: 90,
              height: 102,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.t(venue.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MapDesign.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Text(
                      venue.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        color: MapDesign.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.star_rounded,
                      color: MapDesign.brand,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final tag in venue.tags.take(2))
                            VenueTag(label: text.t(tag)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: MapDesign.brand,
                      size: 17,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        text.t(venue.address),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MapDesign.muted,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  text.t(venue.distance),
                  style: const TextStyle(
                    color: MapDesign.muted,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
