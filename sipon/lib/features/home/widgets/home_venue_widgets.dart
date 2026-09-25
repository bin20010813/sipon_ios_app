part of '../pages/home_page.dart';

// Kept for the currently disabled bartender section on the home page.
// ignore: unused_element
class _BartenderStories extends StatelessWidget {
  const _BartenderStories();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      children: [
        Expanded(
          flex: 56,
          child: _StoryCard(
            height: 194,
            imagePath: HomePage.bharatAsset,
            title: 'Bharat Balami',
            subtitle: '从孟买到上海\n用风味连接世界',
            tags: [text.t('风味探索'), text.t('文化融合'), text.t('创意表达')],
            titleSize: 19,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 40,
          child: Column(
            children: [
              _StoryCard(
                height: 92,
                imagePath: HomePage.mattAsset,
                title: 'Matt Hasting',
                tags: [text.t('经典技巧'), text.t('优雅平衡')],
                titleSize: 13,
              ),
              const SizedBox(height: 10),
              _StoryCard(
                height: 92,
                imagePath: HomePage.akiAsset,
                title: 'Aki Wang',
                tags: [text.t('东方灵感'), text.t('女性魅力')],
                titleSize: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element -- 调酒师故事模块暂时隐藏，恢复时取消首页 build 中的注释即可
class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.height,
    required this.imagePath,
    required this.title,
    required this.tags,
    this.subtitle,
    this.titleSize = 16,
  });

  final double height;
  final String imagePath;
  final String title;
  final String? subtitle;
  final List<String> tags;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(imagePath, fit: BoxFit.cover),
              // 内容固有色：照片上的渐变压暗与白色文字，两种外观一致，保证在图片上可读。
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x15000000),
                      Color(0x12000000),
                      Color(0xB8000000),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 10,
                top: 14,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    // 内容固有色：图片上的标题，深浅外观一致。
                    color: Colors.white,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (subtitle != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 38,
                  child: Text(
                    text.t(subtitle!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      // 内容固有色：图片上的副标题，深浅外观一致。
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.35,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              Positioned(
                left: 10,
                right: 8,
                bottom: 10,
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final tag in tags)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          // 内容固有色：图片上的标签底，保证标签文字在图片上可读。
                          color: Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              // 内容固有色：图片标签文字，深浅外观一致。
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBarsSection extends StatelessWidget {
  const _TopBarsSection({required this.bars, this.onVenueMapRequested});

  final List<_HomeBar> bars;
  final ValueChanged<MapVenue>? onVenueMapRequested;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    // 首条已在上方作为精选酒吧展示；更多推荐只展示其余条目，避免重复。
    final recommendationBars = bars.skip(1).take(5).toList();
    if (recommendationBars.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        // 右侧与上方精选卡片对齐，底部留白避免阴影被父滚动容器裁切。
        padding: const EdgeInsets.only(right: 23, bottom: 16),
        child: _RankingCard(
          width: constraints.maxWidth - 23,
          title: text.t('更多酒吧推荐'),
          items: recommendationBars
              .map((bar) => bar.toRankingItem(text))
              .toList(),
          onItemTap: [
            for (final bar in recommendationBars)
              () => _pushVenueDetail(context, bar, onVenueMapRequested),
          ],
        ),
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.items,
    required this.width,
    this.onItemTap,
  });

  final String title;
  final List<_RankingItem> items;
  final double width;

  /// 与 [items] 一一对应的点击回调，用于跳转到对应地点详情页。
  final List<VoidCallback>? onItemTap;

  @override
  Widget build(BuildContext context) {
    final siponColors = context.siponColors;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomePage.lineOf(context)),
          boxShadow: [
            BoxShadow(
              color: siponColors.shadow,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: HomePage.inkOf(context),
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: HomePage.lineOf(context)),
              const SizedBox(height: 12),
              for (var i = 0; i < items.length; i++) ...[
                _RankingTile(item: items[i], onTap: onItemTap?[i]),
                if (i < items.length - 1) const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.item, this.compact = false, this.onTap});

  final _RankingItem item;
  final bool compact;

  /// 点击这一行动项时的回调，用于跳转到对应地点详情页。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _HomeVenueImage(
              imageUrl: item.imageUrl,
              assetPath: item.imagePath,
              width: compact ? 58 : 60,
              height: compact ? 58 : 60,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HomePage.inkOf(context),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: HomePage.mutedOf(context),
                      fontSize: 12,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
