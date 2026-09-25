part of '../pages/home_page.dart';

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
        color: Theme.of(context).colorScheme.surface,
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
                  style: TextStyle(
                    color: HomePage.inkOf(context),
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
                  style: TextStyle(
                    color: HomePage.mutedOf(context),
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
