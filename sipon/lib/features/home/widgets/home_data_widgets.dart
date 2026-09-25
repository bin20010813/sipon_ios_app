part of '../pages/home_page.dart';

class _HomeDataSections extends StatelessWidget {
  const _HomeDataSections({required this.data, this.onVenueMapRequested});

  final _HomeBarsData data;
  final ValueChanged<MapVenue>? onVenueMapRequested;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 23),
          child: _SectionHeader(title: text.t('酒吧推荐')),
        ),
        if (data.statusMessage != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 23),
            child: _HomeDataStatus(message: text.t(data.statusMessage!)),
          ),
        ],
        if (data.bars.isNotEmpty) const SizedBox(height: 14),
        if (data.bars.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 23),
            child: _FeaturedBarCard(
              bar: data.featuredBar,
              onTap: () => _pushVenueDetail(
                context,
                data.featuredBar,
                onVenueMapRequested,
              ),
            ),
          ),
        // if (data.bars.isNotEmpty) const SizedBox(height: 14),
        // if (data.bars.isNotEmpty) const _CategoryScroller(),
        // const SizedBox(height: 22),
        // Padding(
        //   padding: const EdgeInsets.only(right: 23),
        //   child: _SectionHeader(title: text.t('调酒师故事')),
        // ),
        // const SizedBox(height: 14),
        // const Padding(
        //   padding: EdgeInsets.only(right: 23),
        //   child: _BartenderStories(),
        // ),
        if (data.bars.length > 1) const SizedBox(height: 26),
        if (data.bars.length > 1)
          _TopBarsSection(
            bars: data.bars,
            onVenueMapRequested: onVenueMapRequested,
          ),
      ],
    );
  }
}

/// 全屏打开鸡尾酒百科列表页。
void _pushCocktailList(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const CocktailListPage()));
}

class _HomeDataStatus extends StatelessWidget {
  const _HomeDataStatus({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: HomePage.mutedOf(context),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

/// 全屏打开某个酒吧/地点的详情页。
void _pushVenueDetail(
  BuildContext context,
  _HomeBar bar,
  ValueChanged<MapVenue>? onVenueMapRequested,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VenueDetailPage(
        venue: bar.toVenue(),
        onMapRequested: onVenueMapRequested == null
            ? null
            : (venue) {
                Navigator.of(context).pop();
                onVenueMapRequested(venue);
              },
      ),
    ),
  );
}

// ignore: unused_element -- DrinkProduct 功能待定，暂时隐藏，恢复时取消首页 build 中的注释即可
class _DrinkCarousel extends StatelessWidget {
  const _DrinkCarousel({
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
  });

  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  static const List<_DrinkProduct> _products = [
    _DrinkProduct(
      title: '朗姆酒',
      subtitle: '热带甜感',
      label: 'Limon',
      tint: Color(0xFFB71E22),
      kind: _DrinkVisualKind.rum,
    ),
    _DrinkProduct(
      title: '伏特加',
      subtitle: '莹质酒',
      label: 'VODKA',
      tint: Color(0xFF89DDF2),
      kind: _DrinkVisualKind.vodka,
    ),
    _DrinkProduct(
      title: '冰块',
      subtitle: '风味辅助',
      label: 'ICE',
      tint: Color(0xFF8DDAF0),
      kind: _DrinkVisualKind.ice,
    ),
    _DrinkProduct(
      title: '金酒',
      subtitle: '草本香气',
      label: 'GIN',
      tint: Color(0xFF7DCBB5),
      kind: _DrinkVisualKind.gin,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: controller,
            padEnds: false,
            itemCount: _products.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final selected = index == currentIndex;
              final product = _products[index];
              return AnimatedScale(
                scale: selected ? 1 : 0.9,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _DrinkProductCard(
                    product: product,
                    selected: selected,
                    onTap: () => _openIngredientList(context, product.kind),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < _products.length; index++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == currentIndex ? 7 : 6,
                height: index == currentIndex ? 7 : 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: index == currentIndex
                      ? HomePage.brand
                      : const Color(0xFFDCD8DC),
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DrinkProductCard extends StatelessWidget {
  const _DrinkProductCard({
    required this.product,
    required this.selected,
    this.onTap,
  });

  final _DrinkProduct product;
  final bool selected;

  /// 点击回调（如跳转配料百科）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(17, 16, 13, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.t(product.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: HomePage.inkOf(context),
                        fontSize: 19,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text.t(product.subtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB7B1B7),
                        fontSize: 11,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'SIPON',
                style: TextStyle(
                  color: Color(0xFFC8C4C8),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Center(
            child: SizedBox(height: 116, child: _DrinkVisual(product: product)),
          ),
        ],
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: content,
            ),
    );
  }
}

/// 从首页酒水卡片进入配料百科：按酒水种类预选分类。
void _openIngredientList(BuildContext context, _DrinkVisualKind kind) {
  final category = switch (kind) {
    _DrinkVisualKind.rum => 'rum',
    _DrinkVisualKind.vodka => 'vodka',
    _DrinkVisualKind.gin => 'gin',
    _DrinkVisualKind.ice => null, // 冰块未归入固定分类，展示全部配料
  };
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => IngredientListPage(initialCategory: category),
    ),
  );
}

class _DrinkVisual extends StatelessWidget {
  const _DrinkVisual({required this.product});

  final _DrinkProduct product;

  @override
  Widget build(BuildContext context) {
    return switch (product.kind) {
      _DrinkVisualKind.rum => _RumBottle(product: product),
      _DrinkVisualKind.vodka => _VodkaBottle(product: product),
      _DrinkVisualKind.gin => _VodkaBottle(product: product),
      _DrinkVisualKind.ice => _IceCubes(color: product.tint),
    };
  }
}

class _VodkaBottle extends StatelessWidget {
  const _VodkaBottle({required this.product});

  final _DrinkProduct product;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 138,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 0,
            child: Container(
              width: 24,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFFD8DDE1),
                border: Border.all(color: const Color(0xFF8A9299)),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            top: 11,
            child: Container(
              width: 18,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE9EFF2), Color(0xFFBFC8CD)],
                ),
                border: Border.all(color: const Color(0xFF89939A)),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Positioned(
            top: 40,
            child: Container(
              width: 55,
              height: 94,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF8FDFF),
                    Color(0xFFD7E0E4),
                    Color(0xFFF5FBFD),
                  ],
                ),
                border: Border.all(color: const Color(0xFF9EA8AE)),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                  bottom: Radius.circular(8),
                ),
              ),
              child: Center(
                child: Text(
                  product.label,
                  style: TextStyle(
                    color: product.tint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 48,
            child: Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                border: Border.all(color: const Color(0xFF9AA4AA)),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.water_drop_outlined,
                color: Color(0xFF94A0A6),
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RumBottle extends StatelessWidget {
  const _RumBottle({required this.product});

  final _DrinkProduct product;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 74,
      height: 138,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 7,
            child: Container(
              width: 26,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF8D1117),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            top: 19,
            child: Container(
              width: 20,
              height: 35,
              color: const Color(0xFFF9C447),
            ),
          ),
          Positioned(
            top: 48,
            child: Container(
              width: 55,
              height: 82,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFAE151D), Color(0xFFEEB220)],
                ),
                border: Border.all(color: const Color(0xFF6E1013), width: 1.5),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                  bottom: Radius.circular(7),
                ),
              ),
              child: Center(
                child: Container(
                  width: 38,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE78A),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    product.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF941214),
                      fontSize: 7,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IceCubes extends StatelessWidget {
  const _IceCubes({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 128,
      child: Stack(
        children: [
          _IceCube(left: 52, top: 0, angle: -0.32, color: color),
          _IceCube(left: 23, top: 36, angle: 0.28, color: color),
          _IceCube(left: 67, top: 47, angle: -0.13, color: color),
          _IceCube(left: 35, top: 84, angle: -0.5, color: color),
        ],
      ),
    );
  }
}

class _IceCube extends StatelessWidget {
  const _IceCube({
    required this.left,
    required this.top,
    required this.angle,
    required this.color,
  });

  final double left;
  final double top;
  final double angle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 33,
          height: 33,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                color.withValues(alpha: 0.5),
                color.withValues(alpha: 0.84),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.24),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onMorePressed});

  final String title;

  /// 右侧"更多"点击回调；为空时保持不可用的空操作。
  final VoidCallback? onMorePressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: HomePage.inkOf(context),
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        TextButton(
          onPressed: onMorePressed ?? () {},
          style: TextButton.styleFrom(
            foregroundColor: HomePage.mutedOf(context),
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text.t('更多'),
                style: const TextStyle(fontSize: 12, letterSpacing: 0),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeaturedBarCard extends StatelessWidget {
  const _FeaturedBarCard({required this.bar, required this.onTap});

  final _HomeBar bar;

  /// 点击卡片后的回调，用于跳转到对应地点详情页。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomePage.lineOf(context)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1.84,
                    child: _HomeVenueImage(
                      imageUrl: bar.imageUrl,
                      assetPath: bar.imageAsset,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 10,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in bar.tags.take(2))
                          _OverlayTag(label: text.t(tag)),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            text.t(bar.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: HomePage.inkOf(context),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              bar.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xFF6F6870),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(width: 3),
                            const Icon(
                              Icons.star_rounded,
                              color: HomePage.brand,
                              size: 16,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in bar.tags.take(3))
                          _LightTag(label: text.t(tag)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: HomePage.mutedOf(context),
                          size: 16,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            text.t(bar.address),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: HomePage.mutedOf(context),
                              fontSize: 12,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        Text(
                          text.t(bar.distance),
                          style: TextStyle(
                            color: HomePage.mutedOf(context),
                            fontSize: 12,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
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

class _OverlayTag extends StatelessWidget {
  const _OverlayTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _LightTag extends StatelessWidget {
  const _LightTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: HomePage.chipBgOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: HomePage.brand,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _HomeVenueImage extends StatelessWidget {
  const _HomeVenueImage({
    required this.imageUrl,
    required this.assetPath,
    this.width,
    this.height,
  });

  final String? imageUrl;
  final String assetPath;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      // 后端图片字段是 `/api/bars/{id}/images/{variant}` 相对路径，
      // SiponNetworkImage 内部会拼上 API base 并走磁盘缓存。
      return SiponNetworkImage(
        url: url,
        fallbackAsset: assetPath,
        width: width,
        height: height,
      );
    }

    return _assetImage();
  }

  Widget _assetImage() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }
}

// class _CategoryScroller extends StatelessWidget {
//   const _CategoryScroller();
//
//   @override
//   Widget build(BuildContext context) {
//     return SizedBox(
//       height: 42,
//       child: ListView(
//         scrollDirection: Axis.horizontal,
//         physics: const BouncingScrollPhysics(),
//         children: const [
//           _CategoryChip(
//             label: '清吧',
//             assetPath: HomePage.pubAsset,
//             selected: true,
//           ),
//           _CategoryChip(label: '精酿', assetPath: HomePage.craftAsset),
//           _CategoryChip(label: 'Bistro', assetPath: HomePage.bistroAsset),
//           _CategoryChip(label: '派对', assetPath: HomePage.partyAsset),
//           _CategoryChip(label: 'Livehouse', assetPath: HomePage.livehouseAsset),
//           SizedBox(width: 23),
//         ],
//       ),
//     );
//   }
// }
//
// class _CategoryChip extends StatelessWidget {
//   const _CategoryChip({
//     required this.label,
//     required this.assetPath,
//     this.selected = false,
//   });
//
//   final String label;
//   final String assetPath;
//   final bool selected;
//
//   @override
//   Widget build(BuildContext context) {
//     final text = SiponLanguageScope.textOf(context);
//
//     return Padding(
//       padding: const EdgeInsets.only(right: 9),
//       child: Material(
//         color: selected ? HomePage.brand : HomePage.chipBg,
//         borderRadius: BorderRadius.circular(22),
//         child: InkWell(
//           onTap: () {},
//           borderRadius: BorderRadius.circular(22),
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Image.asset(
//                   assetPath,
//                   width: 22,
//                   height: 22,
//                   color: selected ? Colors.white : HomePage.brand,
//                 ),
//                 const SizedBox(width: 6),
//                 Text(
//                   text.t(label),
//                   style: TextStyle(
//                     color: selected ? Colors.white : const Color(0xFF443B43),
//                     fontSize: 14,
//                     fontWeight: FontWeight.w700,
//                     letterSpacing: 0,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// ignore: unused_element -- 调酒师故事模块暂时隐藏，恢复时取消首页 build 中的注释即可
