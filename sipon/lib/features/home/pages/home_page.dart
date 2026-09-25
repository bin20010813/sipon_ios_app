import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';

import 'package:sipon/features/drinks/cocktails/data/cocktail_recommendation_store.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/shared/services/sipon_api_models.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/services/sipon_data_repository.dart';
import 'package:sipon/shared/widgets/bottom_clamping_bouncing_scroll_physics.dart';
import 'package:sipon/features/map/pages/venue_detail_page.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';
import 'package:sipon/shared/widgets/sipon_network_image.dart';
import 'package:sipon/features/drinks/cocktails/pages/cocktail_detail_page.dart';
import 'package:sipon/features/drinks/cocktails/pages/cocktail_list_page.dart';
import 'package:sipon/features/drinks/cocktails/pages/ingredient_list_page.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/drinks/virtual_drinking/pages/virtual_drinking_page.dart';

part '../widgets/home_top_and_prompts.dart';
part '../widgets/home_data_widgets.dart';
part '../widgets/home_venue_widgets.dart';
part '../widgets/home_cocktail_widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.bottomOverlayInset = 0,
    this.onRecordPressed,
    this.onVenueMapRequested,
    this.searchExpanded,
  });

  final double bottomOverlayInset;
  final VoidCallback? onRecordPressed;
  final ValueChanged<MapVenue>? onVenueMapRequested;

  /// 外部共享的搜索展开状态（壳层用它在遮罩出现时同步隐藏底栏）；
  /// 为空时由页面内部自建，页面可独立使用。
  final ValueNotifier<bool>? searchExpanded;

  static const Color brand = Color(0xFF9A3D78);
  static Color inkOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color mutedOf(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
  static Color chipBgOf(BuildContext context) =>
      context.siponColors.brandSurface;
  static Color lineOf(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  static const String logoAsset = 'assest/首页/logo@3x.png';
  static const String nameAsset = 'assest/首页/sipon_logo.svg';
  static const String nameLegacyAsset = 'assest/首页/NAME@3x.png';
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
  late Future<_HomeBarsData> _homeBarsFuture;
  SiponCityController? _cityController;
  String? _loadedCity;
  SiponLocationPoint? _loadedAnchor;
  // 搜索展开状态用 ValueNotifier 局部刷新顶栏/遮罩，避免 setState 重建整个
  // 首页列表；实例可能由壳层注入（用于联动底栏），见 initState。
  late final ValueNotifier<bool> _searchExpanded;
  final GlobalKey<_HomeTopBarState> _homeTopBarKey =
      GlobalKey<_HomeTopBarState>();
  // ignore: unused_field, prefer_final_fields -- DrinkProduct 功能待定，暂时隐藏，恢复 _DrinkCarousel 时启用
  int _currentDrink = 1;

  @override
  void initState() {
    super.initState();
    _searchExpanded = widget.searchExpanded ?? ValueNotifier<bool>(false);
    _drinkController = PageController(initialPage: 1, viewportFraction: 0.52);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cityController = SiponCityScope.controllerOf(context);
    if (_cityController != cityController) {
      _cityController?.removeListener(_refreshHomeBarsForCity);
      _cityController = cityController..addListener(_refreshHomeBarsForCity);
    }
    _refreshHomeBarsForCity();
  }

  @override
  void dispose() {
    _cityController?.removeListener(_refreshHomeBarsForCity);
    // 注入的 notifier 由壳层管理生命周期，仅自建时释放。
    if (widget.searchExpanded == null) {
      _searchExpanded.dispose();
    }
    _drinkController.dispose();
    super.dispose();
  }

  void _refreshHomeBarsForCity() {
    final city = _cityController?.city;
    final anchor = _cityController?.queryAnchor;
    if (!mounted ||
        city == null ||
        (city == _loadedCity && anchor == _loadedAnchor)) {
      return;
    }
    _loadedCity = city;
    _loadedAnchor = anchor;
    _homeBarsFuture = _loadHomeBars(city);
    setState(() {});
  }

  void _setSearchExpanded(bool expanded) {
    if (!mounted || _searchExpanded.value == expanded) {
      return;
    }
    _searchExpanded.value = expanded;
  }

  Future<_HomeBarsData> _loadHomeBars(String city) async {
    // 首页按所选城市加载完整酒吧列表。
    try {
      // 首页按城市加载，避免 nearby 接口将结果限制在定位点周围的半径内。
      // fetchHomeBars 会请求 hasImage=true，并再次校验响应的 hasImage 字段。
      final bars = await SiponDataRepository.instance.fetchHomeBars(city: city);
      if (bars.isEmpty) {
        return _HomeBarsData(
          bars: city == SiponCityController.defaultCity
              ? _fallbackHomeBars
              : const [],
          statusMessage: city == SiponCityController.defaultCity
              ? '使用本地示例数据: 接口未返回可展示酒吧'
              : '当前城市暂无可展示酒吧',
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
        bars: city == SiponCityController.defaultCity
            ? _fallbackHomeBars
            : const [],
        statusMessage: city == SiponCityController.defaultCity
            ? '使用本地示例数据: $error'
            : '当前城市酒吧加载失败: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        // 底部不进安全区：页面背景（白色）自然延伸到底，避免安全区露出
        // 与内容脱节的 Scaffold 底色条带；底部空间由 bottomOverlayInset 预留。
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Stack(
              children: [
                CustomScrollView(
                  physics: const BottomClampingBouncingScrollPhysics(),
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
                          Padding(
                            padding: const EdgeInsets.only(right: 22),
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _searchExpanded,
                              builder: (context, searchExpanded, _) =>
                                  searchExpanded
                                  ? const SizedBox(height: 52)
                                  : _HomeTopBar(
                                      key: _homeTopBarKey,
                                      expanded: false,
                                      onExpandedChanged: _setSearchExpanded,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // TODO: 首页 _DrinkProduct / _DrinkCarousel 功能待定，暂时注释隐藏。
                          // 恢复时取消下面注释即可。
                          // _DrinkCarousel(
                          //   controller: _drinkController,
                          //   currentIndex: _currentDrink,
                          //   onPageChanged: (index) {
                          //     setState(() => _currentDrink = index);
                          //   },
                          // ),
                          // const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.only(right: 23),
                            child: _SectionHeader(
                              title: text.t('鸡尾酒推荐'),
                              onMorePressed: () => _pushCocktailList(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const _CocktailScroller(),
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.only(right: 23),
                            child: _VirtualDrinkingPrompt(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const VirtualDrinkingPage(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.only(right: 23),
                            child: _HomeRecordPrompt(
                              onPressed: widget.onRecordPressed,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FutureBuilder<_HomeBarsData>(
                            future: _homeBarsFuture,
                            builder: (context, snapshot) {
                              final data =
                                  snapshot.data ??
                                  const _HomeBarsData(
                                    bars: [],
                                    statusMessage: '正在加载接口数据...',
                                  );

                              return _HomeDataSections(
                                data: data,
                                onVenueMapRequested: widget.onVenueMapRequested,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _searchExpanded,
                  builder: (context, searchExpanded, _) => Positioned.fill(
                    top: 52,
                    child: IgnorePointer(
                      ignoring: !searchExpanded,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          _setSearchExpanded(false);
                        },
                        // 模糊强度随遮罩透明度同步渐变，避免整段动画每帧全速
                        // 全屏高斯模糊；进度归零后彻底移除 BackdropFilter，
                        // 收起状态下滚动首页不再有任何模糊开销。
                        child: TweenAnimationBuilder<double>(
                          duration: _HomeTopBarState._searchAnimationDuration,
                          curve: Curves.easeOutCubic,
                          tween: Tween<double>(end: searchExpanded ? 1 : 0),
                          builder: (context, progress, _) {
                            if (progress <= 0) {
                              return const SizedBox.shrink();
                            }
                            return ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 8 * progress,
                                  sigmaY: 8 * progress,
                                ),
                                child: ColoredBox(
                                  color: Theme.of(context).colorScheme.surface
                                      .withValues(alpha: 0.38 * progress),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: _searchExpanded,
                  builder: (context, searchExpanded, _) => searchExpanded
                      ? Positioned(
                          top: 16,
                          left: 23,
                          right: 22,
                          child: _HomeTopBar(
                            key: _homeTopBarKey,
                            expanded: true,
                            onExpandedChanged: _setSearchExpanded,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
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
    this.id = '',
    this.kind = '',
    this.longitude,
    this.latitude,
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

  /// 接口返回的地点 id；本地演示数据为空，详情数据源会回退 Mock。
  final String id;

  /// 接口返回的地点类型串（craft/bistro/party/...），可能与展示标签不一致。
  final String kind;

  /// 接口返回的坐标；演示数据无坐标时为 null。
  final double? longitude;
  final double? latitude;

  factory _HomeBar.fromApi(SiponBarMapItem item, int index) {
    final tags = item.tags.isEmpty ? [_displayKind(item.kind)] : item.tags;

    return _HomeBar(
      id: item.id,
      kind: item.kind,
      longitude: item.longitude,
      latitude: item.latitude,
      name: item.name,
      imageAsset: _homeImageAssetForIndex(index),
      // 首页列表和小卡使用 320px 缩略图，避免为列表一次下载 640px 中图。
      // 此 URL 会随 MapVenue 传到详情页，确保点击后能复用同一图片缓存。
      imageUrl: item.resolvedThumbnailUrl,
      rating: item.rating,
      address: item.address,
      distance: item.distance,
      tags: tags,
      description: tags.take(2).join(' · '),
    );
  }

  /// 转成地图地点模型，供详情页使用；无 id/坐标时用名称兜底并走 Mock 详情。
  MapVenue toVenue() {
    return MapVenue(
      id: id.isEmpty ? name : id,
      name: name,
      longitude: longitude ?? 0,
      latitude: latitude ?? 0,
      kind: MapVenueKind.fromRaw(kind),
      rating: rating,
      address: address,
      distance: distance,
      tags: tags,
      imageAsset: imageAsset,
      imageUrl: imageUrl,
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

enum _DrinkVisualKind { rum, vodka, gin, ice }

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
