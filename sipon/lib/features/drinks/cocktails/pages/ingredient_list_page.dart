import 'package:flutter/material.dart';

import '../../../../shared/services/sipon_api_client.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';
import '../../../../shared/widgets/sipon_network_image.dart';
import 'ingredient_detail_page.dart';
import '../../../../shared/localization/language_transform.dart';

/// 配料百科——列表页（GET /api/ingredients，支持分类筛选）。
class IngredientListPage extends StatefulWidget {
  const IngredientListPage({super.key, this.initialCategory});

  /// 进入页面时预选的分类值（后端枚举，如 rum/vodka/gin）；为空表示全部。
  final String? initialCategory;

  @override
  State<IngredientListPage> createState() => _IngredientListPageState();
}

class _IngredientListPageState extends State<IngredientListPage> {
  static const int _pageSize = 20;
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列2.png';

  /// 分类筛选项：中文标签 + 后端分类值（null 表示全部）。
  static const List<(String, String?)> _categories = [
    ('全部', null),
    ('基酒', 'base'),
    ('利口酒', 'liqueur'),
    ('金酒', 'gin'),
    ('威士忌', 'whiskey'),
    ('朗姆酒', 'rum'),
    ('伏特加', 'vodka'),
    ('白兰地', 'brandy'),
    ('龙舌兰', 'tequila'),
  ];

  final SiponApiService _api = SiponApiService();
  final ScrollController _scrollController = ScrollController();

  final List<IngredientInfo> _items = [];
  bool _loading = false;
  bool _loaded = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String? _category;

  @override
  void initState() {
    super.initState();
    // 带上预选分类（如首页配料入口传入的 rum/gin 等）。
    _category = widget.initialCategory;
    // 监听滚动到底部，触发分页加载更多。
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 拉取配料列表；[reset] 为 true 时回到第一页重载。
  Future<void> _load({required bool reset}) async {
    if (_loading || _loadingMore) return;
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    final offset = reset ? 0 : _items.length;
    try {
      final list = await _api.searchIngredients(
        category: _category,
        page: SiponPage(limit: _pageSize, offset: offset),
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(IngredientInfo.listFromJson(list));
        _loaded = true;
        _hasMore = list.length >= _pageSize;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      if (reset) {
        setState(() => _error = _describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// 滚动接近底部时加载下一页。
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 160) {
      if (_hasMore) {
        _load(reset: false);
      }
    }
  }

  /// 切换分类：重新拉取第一页。
  void _selectCategory(String? category) {
    if (category == _category) return;
    _category = category;
    _load(reset: true);
  }

  /// 打开配料详情页。
  void _openDetail(IngredientInfo item) {
    final id = item.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IngredientDetailPage(ingredientId: id),
      ),
    );
  }

  /// 把异常转为用户可读文案。
  String _describeError(Exception error) {
    if (error is SiponApiException) {
      final detail = error.message?.trim();
      if (detail != null && detail.isNotEmpty) return detail;
    }
    return error.toString();
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFCFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          // bottom:false 让列表视口延伸到屏幕底，内容可滚过小白条区域；
          // 底部空间由列表自身的 padding 预留。
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                    child: _IngredientTopBar(
                      title: text.t('配料'),
                      back: text.back,
                    ),
                  ),
                  // 分类筛选条。
                  _CategoryFilter(
                    categories: _categories,
                    selectedIndex: _categories
                        .indexWhere((entry) => entry.$2 == _category)
                        .clamp(0, _categories.length - 1),
                    onSelected: (index) =>
                        _selectCategory(_categories[index].$2),
                  ),
                  Expanded(child: _buildBody(text)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 依据加载/错误/空/列表状态渲染内容区。
  Widget _buildBody(SiponAppText text) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: _muted),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                text.t(_error!),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: () => _load(reset: true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFE8F6),
                foregroundColor: _brand,
              ),
              child: Text(text.t('点击重试')),
            ),
          ],
        ),
      );
    }
    if (_loaded && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.liquor_rounded, size: 40, color: _muted),
            const SizedBox(height: 10),
            Text(
              text.t('没有找到相关配料'),
              style: const TextStyle(
                color: _muted,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      // 底部预留系统安全区（Home Indicator），内容滚动时可经过小白条区域。
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        28 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        final item = _items[index];
        return _IngredientCard(item: item, onTap: () => _openDetail(item));
      },
    );
  }
}

/// 顶部：返回按钮 + 标题。
class _IngredientTopBar extends StatelessWidget {
  const _IngredientTopBar({required this.title, required this.back});

  final String title;
  final String back;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Tooltip(
            message: back,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                backgroundColor: Colors.white.withValues(alpha: 0.78),
                foregroundColor: _IngredientListPageState._ink,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _IngredientListPageState._ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 横向分类筛选条。
class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<(String, String?)> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? _IngredientListPageState._brand
                    : Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                text.t(categories[index].$1),
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : _IngredientListPageState._muted,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 单条配料卡片：左侧图 + 右侧名称/分类/基酒角标。
class _IngredientCard extends StatelessWidget {
  const _IngredientCard({required this.item, required this.onTap});

  final IngredientInfo item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = item.name ?? (item.nameEn ?? '');
    if (name.isEmpty) return const SizedBox.shrink();
    final imageUrl = item.resolvedImageUrl();

    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _IngredientThumb(
                imageUrl: imageUrl,
                fallbackAsset: _IngredientListPageState._fallbackAsset,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _IngredientListPageState._ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    if (item.nameEn != null && item.nameEn!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.nameEn!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _IngredientListPageState._muted,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.category != null && item.category!.isNotEmpty)
                          Text(
                            item.category!,
                            style: const TextStyle(
                              color: _IngredientListPageState._muted,
                              fontSize: 11,
                              letterSpacing: 0,
                            ),
                          ),
                        if (item.baseSpirit == true) ...[
                          const SizedBox(width: 8),
                          const _BaseSpiritBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: _IngredientListPageState._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 网络图 + 本地素材回退的配料缩略图。
class _IngredientThumb extends StatelessWidget {
  const _IngredientThumb({this.imageUrl, required this.fallbackAsset});

  final String? imageUrl;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SiponNetworkImage(
          url: url,
          fallbackAsset: fallbackAsset,
          width: 72,
          height: 72,
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        fallbackAsset,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// "基酒"角标。
class _BaseSpiritBadge extends StatelessWidget {
  const _BaseSpiritBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          '基酒',
          style: TextStyle(
            color: _IngredientListPageState._brand,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
