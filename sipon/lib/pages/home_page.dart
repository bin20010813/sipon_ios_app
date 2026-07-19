import 'package:flutter/material.dart';

import '../services/sipon_api_models.dart';
import '../services/sipon_data_repository.dart';
import 'language_transform.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.bottomOverlayInset = 0});

  final double bottomOverlayInset;

  static const Color brand = Color(0xFF9A3D78);
  static const Color ink = Color(0xFF252229);
  static const Color muted = Color(0xFF9B939B);
  static const Color chipBg = Color(0xFFF8E7F7);
  static const Color line = Color(0xFFF2EDF1);

  static const String logoAsset = 'assest/首页/logo@3x.png';
  static const String nameAsset = 'assest/首页/NAME@3x.png';
  static const String searchAsset = 'assest/首页/搜索@3x.png';
  static const String barMainAsset = 'assest/首页/图片素材/庙前冰室.png';
  static const String bharatAsset = 'assest/首页/图片素材/Bharat Balami.png';
  static const String mattAsset = 'assest/首页/图片素材/Matt Hasting.png';
  static const String akiAsset = 'assest/首页/图片素材/Aki Wang.png';
  static const String speakLowAsset = 'assest/首页/图片素材/Speak Low（彼楼）.png';
  static const String janesAsset = 'assest/首页/图片素材/酒吧 Janes and Hooch.png';
  static const String playHouseAsset = 'assest/首页/图片素材/Play House 电音夜店.png';
  static const String barOneAsset = 'assest/首页/图片素材/酒吧1.png';
  static const String barTwoAsset = 'assest/首页/图片素材/酒吧2.png';
  static const String barThreeAsset = 'assest/首页/图片素材/酒吧3.png';
  static const String cocktailOneAsset = 'assest/首页/图片素材/鸡尾酒系列1.png';
  static const String cocktailTwoAsset = 'assest/首页/图片素材/鸡尾酒系列2.png';
  static const String cocktailThreeAsset = 'assest/首页/图片素材/鸡尾酒系列3.png';
  static const String pubAsset = 'assest/首页/清吧@3x.png';
  static const String craftAsset = 'assest/首页/精酿@3x.png';
  static const String bistroAsset = 'assest/首页/Bistro@3x.png';
  static const String partyAsset = 'assest/首页/派对@3x.png';
  static const String livehouseAsset = 'assest/首页/Livehouse@3x.png';

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final PageController _drinkController;
  late final Future<_HomeBarsData> _homeBarsFuture;
  int _currentDrink = 1;

  @override
  void initState() {
    super.initState();
    _drinkController = PageController(initialPage: 1, viewportFraction: 0.52);
    _homeBarsFuture = _loadHomeBars();
  }

  @override
  void dispose() {
    _drinkController.dispose();
    super.dispose();
  }

  Future<_HomeBarsData> _loadHomeBars() async {
    try {
      final bars = await SiponDataRepository.instance.fetchHomeBars();
      if (bars.isEmpty) {
        return const _HomeBarsData(
          bars: _fallbackHomeBars,
          statusMessage: '使用本地示例数据: 接口未返回可展示酒吧',
        );
      }

      return _HomeBarsData(
        bars: [
          for (var index = 0; index < bars.length; index++)
            _HomeBar.fromApi(bars[index], index),
        ],
      );
    } catch (error) {
      return _HomeBarsData(
        bars: _fallbackHomeBars,
        statusMessage: '使用本地示例数据: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    23,
                    16,
                    0,
                    24 + widget.bottomOverlayInset,
                  ),
                  sliver: SliverList.list(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 18),
                        child: _HomeTopBar(),
                      ),
                      const SizedBox(height: 28),
                      _DrinkCarousel(
                        controller: _drinkController,
                        currentIndex: _currentDrink,
                        onPageChanged: (index) {
                          setState(() => _currentDrink = index);
                        },
                      ),
                      const SizedBox(height: 24),
                      FutureBuilder<_HomeBarsData>(
                        future: _homeBarsFuture,
                        builder: (context, snapshot) {
                          final data =
                              snapshot.data ??
                              const _HomeBarsData(
                                bars: _fallbackHomeBars,
                                statusMessage: '正在加载接口数据...',
                              );

                          return _HomeDataSections(data: data);
                        },
                      ),
                    ],
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

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Image.asset(HomePage.logoAsset, width: 42, height: 42),
          Expanded(
            child: Center(
              child: Image.asset(HomePage.nameAsset, width: 88, height: 32),
            ),
          ),
          Tooltip(
            message: text.t('搜索'),
            child: IconButton(
              onPressed: () {},
              style: IconButton.styleFrom(
                fixedSize: const Size(44, 44),
                backgroundColor: const Color(0xFFF6F5F6),
                foregroundColor: const Color(0xFF6B666B),
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: Image.asset(
                HomePage.searchAsset,
                width: 22,
                height: 22,
                color: const Color(0xFF6B666B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeDataSections extends StatelessWidget {
  const _HomeDataSections({required this.data});

  final _HomeBarsData data;

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
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(right: 23),
          child: _FeaturedBarCard(bar: data.featuredBar),
        ),
        const SizedBox(height: 14),
        const _CategoryScroller(),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(right: 23),
          child: _SectionHeader(title: text.t('调酒师故事')),
        ),
        const SizedBox(height: 14),
        const Padding(
          padding: EdgeInsets.only(right: 23),
          child: _BartenderStories(),
        ),
        const SizedBox(height: 26),
        _TopBarsSection(bars: data.bars),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(right: 23),
          child: _SectionHeader(title: text.t('鸡尾酒推荐')),
        ),
        const SizedBox(height: 14),
        const _CocktailScroller(),
      ],
    );
  }
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
      style: const TextStyle(
        color: HomePage.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

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
      kind: _DrinkVisualKind.vodka,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 248,
          child: PageView.builder(
            controller: controller,
            padEnds: false,
            itemCount: _products.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final selected = index == currentIndex;
              return AnimatedScale(
                scale: selected ? 1 : 0.9,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _DrinkProductCard(
                    product: _products[index],
                    selected: selected,
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
  const _DrinkProductCard({required this.product, required this.selected});

  final _DrinkProduct product;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F3),
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
      child: Padding(
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
                        style: const TextStyle(
                          color: HomePage.ink,
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
            Expanded(
              child: Center(child: _DrinkVisual(product: product)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrinkVisual extends StatelessWidget {
  const _DrinkVisual({required this.product});

  final _DrinkProduct product;

  @override
  Widget build(BuildContext context) {
    return switch (product.kind) {
      _DrinkVisualKind.rum => _RumBottle(product: product),
      _DrinkVisualKind.vodka => _VodkaBottle(product: product),
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
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: HomePage.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            foregroundColor: HomePage.muted,
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
  const _FeaturedBarCard({required this.bar});

  final _HomeBar bar;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 8),
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
                          style: const TextStyle(
                            color: HomePage.ink,
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
                      const Icon(
                        Icons.location_on_outlined,
                        color: HomePage.muted,
                        size: 16,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          text.t(bar.address),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HomePage.muted,
                            fontSize: 12,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Text(
                        text.t(bar.distance),
                        style: const TextStyle(
                          color: HomePage.muted,
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
        color: const Color(0xFFFFE8F6),
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
      return Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _assetImage(),
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

class _CategoryScroller extends StatelessWidget {
  const _CategoryScroller();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: const [
          _CategoryChip(
            label: '清吧',
            assetPath: HomePage.pubAsset,
            selected: true,
          ),
          _CategoryChip(label: '精酿', assetPath: HomePage.craftAsset),
          _CategoryChip(label: 'Bistro', assetPath: HomePage.bistroAsset),
          _CategoryChip(label: '派对', assetPath: HomePage.partyAsset),
          _CategoryChip(label: 'Livehouse', assetPath: HomePage.livehouseAsset),
          SizedBox(width: 23),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.assetPath,
    this.selected = false,
  });

  final String label;
  final String assetPath;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: Material(
        color: selected ? HomePage.brand : HomePage.chipBg,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  assetPath,
                  width: 22,
                  height: 22,
                  color: selected ? Colors.white : HomePage.brand,
                ),
                const SizedBox(width: 6),
                Text(
                  text.t(label),
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF443B43),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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
  const _TopBarsSection({required this.bars});

  final List<_HomeBar> bars;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final primaryBars = _ensureBarCount(bars.take(3).toList(), 3);
    final secondaryBars = _ensureBarCount(bars.skip(3).take(3).toList(), 3);

    return SizedBox(
      height: 306,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _RankingCard(
            title: text.t('全国TOP10酒吧'),
            items: primaryBars.map((bar) => bar.toRankingItem(text)).toList(),
          ),
          const SizedBox(width: 16),
          _RankingCard(
            title: text.t('广州Top10'),
            compact: true,
            items: secondaryBars.map((bar) => bar.toRankingItem(text)).toList(),
          ),
          const SizedBox(width: 23),
        ],
      ),
    );
  }
}

class _RankingCard extends StatelessWidget {
  const _RankingCard({
    required this.title,
    required this.items,
    this.compact = false,
  });

  final String title;
  final List<_RankingItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 184 : 302,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomePage.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 16,
              offset: Offset(0, 8),
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
                style: const TextStyle(
                  color: HomePage.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: HomePage.line),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final item in items)
                      _RankingTile(item: item, compact: compact),
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

class _RankingTile extends StatelessWidget {
  const _RankingTile({required this.item, required this.compact});

  final _RankingItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                  style: const TextStyle(
                    color: HomePage.ink,
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
                  style: const TextStyle(
                    color: HomePage.muted,
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
    );
  }
}

class _CocktailScroller extends StatelessWidget {
  const _CocktailScroller();

  static const List<_CocktailItem> _items = [
    _CocktailItem(
      imagePath: HomePage.cocktailOneAsset,
      title: '白俄罗斯',
      subtitle: '冷战的硬核浪漫',
    ),
    _CocktailItem(
      imagePath: HomePage.cocktailTwoAsset,
      title: '黑俄罗斯',
      subtitle: '流动的咖啡冰淇淋',
    ),
    _CocktailItem(
      imagePath: HomePage.cocktailThreeAsset,
      title: '黑俄罗斯',
      subtitle: '流动的咖啡烈酒',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SizedBox(
      height: 262,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const SizedBox(width: 23);
          }
          return _CocktailCard(item: _items[index].translated(text));
        },
      ),
    );
  }
}

class _CocktailCard extends StatelessWidget {
  const _CocktailCard({required this.item});

  final _CocktailItem item;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 142,
      child: Material(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.82,
                child: Image.asset(item.imagePath, fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomePage.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                child: Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomePage.muted,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeBarsData {
  const _HomeBarsData({required this.bars, this.statusMessage});

  final List<_HomeBar> bars;
  final String? statusMessage;

  _HomeBar get featuredBar => bars.first;
}

class _HomeBar {
  const _HomeBar({
    required this.name,
    required this.imageAsset,
    required this.rating,
    required this.address,
    required this.distance,
    required this.tags,
    required this.description,
    this.imageUrl,
  });

  final String name;
  final String imageAsset;
  final String? imageUrl;
  final double rating;
  final String address;
  final String distance;
  final List<String> tags;
  final String description;

  factory _HomeBar.fromApi(SiponBarMapItem item, int index) {
    final tags = item.tags.isEmpty ? [_displayKind(item.kind)] : item.tags;

    return _HomeBar(
      name: item.name,
      imageAsset: _homeImageAssetForIndex(index),
      imageUrl: item.imageUrl,
      rating: item.rating,
      address: item.address,
      distance: item.distance,
      tags: tags,
      description: tags.take(2).join(' · '),
    );
  }

  _RankingItem toRankingItem(SiponAppText text) {
    return _RankingItem(
      imagePath: imageAsset,
      imageUrl: imageUrl,
      title: text.t(name),
      description: text.t(description.isEmpty ? address : description),
    );
  }
}

List<_HomeBar> _ensureBarCount(List<_HomeBar> bars, int count) {
  if (bars.length >= count) {
    return bars;
  }

  return [
    ...bars,
    ..._fallbackHomeBars.skip(bars.length).take(count - bars.length),
  ];
}

String _homeImageAssetForIndex(int index) {
  const images = [
    HomePage.barMainAsset,
    HomePage.speakLowAsset,
    HomePage.janesAsset,
    HomePage.playHouseAsset,
    HomePage.barOneAsset,
    HomePage.barTwoAsset,
    HomePage.barThreeAsset,
  ];

  return images[index % images.length];
}

String _displayKind(String kind) {
  return switch (kind) {
    'craft' => '精酿',
    'bistro' => 'Bistro',
    'party' => '派对',
    'livehouse' => 'Livehouse',
    _ => '清吧',
  };
}

const List<_HomeBar> _fallbackHomeBars = [
  _HomeBar(
    name: '庙前冰室（Hope & Sesame）',
    imageAsset: HomePage.barMainAsset,
    rating: 4.9,
    address: '越秀区庙前西街 48 号',
    distance: '约2460公里',
    tags: ['经典复古', '地下酒吧', '鸡尾酒吧', '中式复古风'],
    description: '岭南灵感和复古调酒。',
  ),
  _HomeBar(
    name: 'Speak Low（彼楼）',
    imageAsset: HomePage.speakLowAsset,
    rating: 4.9,
    address: '上海市黄浦区复兴中路 579',
    distance: '约1.7km',
    tags: ['经典吧台', 'Speakeasy'],
    description: '隐藏式 speakeasy，调酒专业，复古氛围浓。',
  ),
  _HomeBar(
    name: 'Janes and Hooch',
    imageAsset: HomePage.janesAsset,
    rating: 4.8,
    address: '北京市朝阳区工体北路',
    distance: '约2.4km',
    tags: ['清吧', '经典调酒'],
    description: '北京顶级鸡尾酒清吧，经典调酒极强。',
  ),
  _HomeBar(
    name: 'Play House 电音夜店',
    imageAsset: HomePage.playHouseAsset,
    rating: 4.7,
    address: '上海市黄浦区淮海中路 333',
    distance: '约2.8km',
    tags: ['派对', '现场音乐'],
    description: '百大夜店，超大舞池，顶级电音和舞美。',
  ),
  _HomeBar(
    name: '庙前酒馆',
    imageAsset: HomePage.barOneAsset,
    rating: 4.6,
    address: '广州市越秀区庙前西街',
    distance: '约2.2km',
    tags: ['清吧', '威士忌'],
    description: '烛光、木质吧台和威士忌。',
  ),
  _HomeBar(
    name: '天台酒廊',
    imageAsset: HomePage.barTwoAsset,
    rating: 4.5,
    address: '广州市天河区珠江新城',
    distance: '约3.1km',
    tags: ['Bistro', '露台'],
    description: '城市夜景与招牌特调。',
  ),
];

class _DrinkProduct {
  const _DrinkProduct({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.tint,
    required this.kind,
  });

  final String title;
  final String subtitle;
  final String label;
  final Color tint;
  final _DrinkVisualKind kind;
}

enum _DrinkVisualKind { rum, vodka, ice }

class _RankingItem {
  const _RankingItem({
    required this.imagePath,
    required this.title,
    required this.description,
    this.imageUrl,
  });

  final String imagePath;
  final String title;
  final String description;
  final String? imageUrl;
}

class _CocktailItem {
  const _CocktailItem({
    required this.imagePath,
    required this.title,
    required this.subtitle,
  });

  final String imagePath;
  final String title;
  final String subtitle;

  _CocktailItem translated(SiponAppText text) {
    return _CocktailItem(
      imagePath: imagePath,
      title: text.t(title),
      subtitle: text.t(subtitle),
    );
  }
}
