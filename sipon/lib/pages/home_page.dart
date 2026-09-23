import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/cocktail_recommendation_store.dart';
import '../services/map/map_models.dart';
import '../services/sipon_api_models.dart';
import '../services/sipon_api_service.dart';
import '../services/sipon_city_controller.dart';
import '../services/sipon_data_repository.dart';
import '../widgets/bottom_clamping_bouncing_scroll_physics.dart';
import '../widgets/map/venue_detail_page.dart';
import '../widgets/sipon_city_picker.dart';
import '../widgets/sipon_network_image.dart';
import 'cocktail_detail_page.dart';
import 'cocktail_list_page.dart';
import 'ingredient_list_page.dart';
import 'language_transform.dart';
import 'virtual_drinking_page.dart';

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
      backgroundColor: Colors.white,
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
                                  color: Colors.white.withValues(
                                    alpha: 0.38 * progress,
                                  ),
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

class _HomeTopBar extends StatefulWidget {
  const _HomeTopBar({
    super.key,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_HomeTopBar> createState() => _HomeTopBarState();
}

class _HomeTopBarState extends State<_HomeTopBar> {
  static const Duration _searchAnimationDuration = Duration(milliseconds: 280);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SiponApiService _cocktailApi = SiponApiService();
  final List<CocktailInfo> _suggestions = [];
  Timer? _searchDebounce;
  // 展开动画结束后再请求焦点唤起键盘，避免键盘滑入与宽度/遮罩模糊动画
  // 叠加在同一个渲染窗口内导致掉帧。
  Timer? _focusRequestDebounce;
  bool _loadingSuggestions = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _focusRequestDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() {
        _suggestions.clear();
        _loadingSuggestions = false;
      });
      return;
    }

    setState(() => _loadingSuggestions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 260), () async {
      try {
        final data = await _cocktailApi.searchCocktails(
          keyword: keyword,
          page: const SiponPage(limit: 3),
        );
        if (!mounted || _searchController.text.trim() != keyword) return;
        setState(() {
          _suggestions
            ..clear()
            ..addAll(CocktailInfo.listFromJson(data));
          _loadingSuggestions = false;
        });
      } on Exception {
        if (mounted && _searchController.text.trim() == keyword) {
          setState(() => _loadingSuggestions = false);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _HomeTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.expanded && widget.expanded) {
      // 延迟到展开动画（280ms）结束后再弹键盘，错开 raster 压力峰值。
      _focusRequestDebounce?.cancel();
      _focusRequestDebounce = Timer(_searchAnimationDuration, () {
        if (mounted && widget.expanded) _searchFocusNode.requestFocus();
      });
    } else if (oldWidget.expanded && !widget.expanded) {
      _focusRequestDebounce?.cancel();
      _searchFocusNode.unfocus();
    }
  }

  void _openSearch() {
    if (!widget.expanded) {
      widget.onExpandedChanged(true);
      return;
    }
    _submitSearch();
  }

  void _submitSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      _searchFocusNode.requestFocus();
      return;
    }

    _searchFocusNode.unfocus();
    widget.onExpandedChanged(false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocktailListPage(initialKeyword: keyword),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  duration: _searchAnimationDuration,
                  curve: Curves.easeOutCubic,
                  opacity: widget.expanded ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: widget.expanded,
                    child: Center(
                      child: Image.asset(
                        HomePage.nameAsset,
                        width: 82,
                        height: 30,
                      ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: _searchAnimationDuration,
                  curve: Curves.easeOutCubic,
                  opacity: widget.expanded ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: widget.expanded,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: SiponCityButton(),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: text.t('搜索'),
                    child: AnimatedContainer(
                      duration: _searchAnimationDuration,
                      curve: Curves.easeOutCubic,
                      width: widget.expanded ? constraints.maxWidth : 44,
                      height: 44,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      // 图标固定贴右缘，输入框占左侧弹性空间随容器展开/收拢；
                      // 不能用条件直接增删输入框（Row 会塌缩，图标瞬间跳位）。
                      child: Row(
                        children: [
                          Expanded(
                            child: widget.expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      // 不用 autofocus：焦点由展开动画结束后的
                                      // 延迟请求统一发起，保证键盘错峰弹出。
                                      textInputAction: TextInputAction.search,
                                      onChanged: _onSearchChanged,
                                      onSubmitted: (_) => _submitSearch(),
                                      style: const TextStyle(
                                        color: HomePage.ink,
                                        fontSize: 14,
                                        letterSpacing: 0,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: text.t('搜索鸡尾酒'),
                                        hintStyle: const TextStyle(
                                          color: HomePage.muted,
                                          fontSize: 13,
                                          letterSpacing: 0,
                                        ),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Tooltip(
                            message: text.t('搜索'),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _openSearch,
                                child: Center(
                                  child: Image.asset(
                                    HomePage.searchAsset,
                                    width: 22,
                                    height: 22,
                                    color: const Color(0xFF6B666B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.expanded && (_loadingSuggestions || _suggestions.isNotEmpty))
          _CocktailSuggestions(
            loading: _loadingSuggestions,
            items: _suggestions,
            onSelected: (item) {
              final keyword = item.name ?? item.nameEn ?? '';
              if (keyword.isEmpty) return;
              _searchController.text = keyword;
              _submitSearch();
            },
          ),
      ],
    );
  }
}

class _CocktailSuggestions extends StatelessWidget {
  const _CocktailSuggestions({
    required this.loading,
    required this.items,
    required this.onSelected,
  });

  final bool loading;
  final List<CocktailInfo> items;
  final ValueChanged<CocktailInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: loading
          ? const SizedBox(
              height: 52,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    leading: const Icon(
                      Icons.local_bar_outlined,
                      color: HomePage.brand,
                      size: 20,
                    ),
                    title: Text(
                      item.name ?? item.nameEn ?? text.t('鸡尾酒'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: HomePage.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => onSelected(item),
                  ),
              ],
            ),
    );
  }
}

class _VirtualDrinkingPrompt extends StatelessWidget {
  const _VirtualDrinkingPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Material(
      color: const Color(0xFF253040),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 17, 15, 17),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF283749), Color(0xFF4A3446)],
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.nightlife_rounded,
                color: Color(0xFFF4D89B),
                size: 36,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.t('虚拟小酌'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text.t('选一杯酒，走进属于你的场景'),
                      style: const TextStyle(
                        color: Color(0xFFE2D6D4),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white70,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeRecordPrompt extends StatelessWidget {
  const _HomeRecordPrompt({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1F9A3D78)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x109A3D78),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_graph_rounded, color: HomePage.brand, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.t('看见你的饮酒习惯'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomePage.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text.t('少一点模糊印象，多一点清楚记录'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: HomePage.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(82, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: HomePage.brand,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(text.t('记一笔')),
          ),
        ],
      ),
    );
  }
}

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
      style: const TextStyle(
        color: HomePage.muted,
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
          const SizedBox(height: 6),
          Center(
            child: SizedBox(height: 116, child: _DrinkVisual(product: product)),
          ),
        ],
      ),
    );

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
            style: const TextStyle(
              color: HomePage.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        TextButton(
          onPressed: onMorePressed ?? () {},
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
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HomePage.line),
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
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: HomePage.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
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
      ),
    );
  }
}

class _CocktailScroller extends StatefulWidget {
  const _CocktailScroller();

  @override
  State<_CocktailScroller> createState() => _CocktailScrollerState();
}

class _CocktailScrollerState extends State<_CocktailScroller> {
  static const int _homeLimit = 10;

  /// 加载失败/返回为空时回退渲染的静态素材卡片。
  static const List<_CocktailItem> _fallbackItems = [
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

  final CocktailRecommendationStore _recommendations =
      CocktailRecommendationStore();
  List<CocktailInfo> _cocktails = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 每次冷启动随机抽取推荐；接口失败退缓存池，缓存也缺失时保持静态素材。
  Future<void> _load() async {
    final list = await _recommendations.loadRecommendations(count: _homeLimit);
    if (!mounted || list.isEmpty) return;
    setState(() => _cocktails = list);
    // 卡片就位后预取详情封面（640 中图），点进详情时直接命中内存缓存。
    _precacheDetailCovers();
  }

  /// 把推荐酒款的详情封面图提前拉入图片缓存；失败静默，由详情页兜底。
  void _precacheDetailCovers() {
    final context = this.context;
    if (!context.mounted) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final cocktail in _cocktails) {
      final url = cocktail.resolvedMediumImageUrl();
      if (url == null || url.isEmpty) continue;
      precacheImage(cocktailDetailCoverImageProvider(url, dpr), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    final slides = List<Widget>.generate(
      _cocktails.isEmpty ? _fallbackItems.length : _cocktails.length,
      (index) {
        if (_cocktails.isEmpty) {
          // 加载中/失败时回退静态素材；点击进入鸡尾酒百科列表页。
          return _CocktailCard(
            item: _fallbackItems[index].translated(text),
            onTap: () => _pushCocktailList(context),
          );
        }
        final cocktail = _cocktails[index];
        return _CocktailCard(
          item: _CocktailItem(
            imagePath: HomePage.cocktailOneAsset,
            title: cocktail.name ?? cocktail.nameEn ?? '',
            subtitle: cocktail.nameEn ?? cocktail.difficulty ?? '',
          ),
          // 小卡按文档用 320px 缩略图档，缺省自动回退原图。
          imageUrl: cocktail.resolvedThumbnailUrl(),
          onTap: () => _openDetail(cocktail),
        );
      },
    );

    return SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: slides.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          if (index == slides.length) {
            return const SizedBox(width: 23);
          }
          return slides[index];
        },
      ),
    );
  }

  /// 打开鸡尾酒百科详情页。
  void _openDetail(CocktailInfo cocktail) {
    final id = cocktail.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocktailDetailPage(
          cocktailId: id,
          // 带上已有摘要，详情页先渲染封面/名称，不再等接口转圈。
          initialSummary: cocktail,
        ),
      ),
    );
  }
}

/// 鸡尾酒推荐卡：上方图 + 下方标题/副标题的竖卡。
class _CocktailCard extends StatelessWidget {
  const _CocktailCard({required this.item, this.imageUrl, this.onTap});

  final _CocktailItem item;

  /// 真实数据时的网络图片地址；为空时使用 [item] 的本地素材图。
  final String? imageUrl;

  /// 点击回调；为空时卡片不可点击。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    final imageWidth = (142 * MediaQuery.devicePixelRatioOf(context)).round();
    final imageHeight = (142 / 0.82 * MediaQuery.devicePixelRatioOf(context))
        .round();

    return SizedBox(
      width: 142,
      child: Material(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 0.82,
                child: (url != null && url.isNotEmpty)
                    ? SiponNetworkImage(
                        url: url,
                        fallbackAsset: item.imagePath,
                        cacheWidth: imageWidth,
                        cacheHeight: imageHeight,
                      )
                    : Image.asset(item.imagePath, fit: BoxFit.cover),
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
