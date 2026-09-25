import 'package:flutter/material.dart';

import '../../../../shared/services/sipon_api_client.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';
import '../../../../shared/widgets/sipon_network_image.dart';
import 'cocktail_detail_page.dart';
import 'ingredient_list_page.dart';
import '../../../../shared/localization/language_transform.dart';

/// 鸡尾酒百科——列表/搜索页（GET /api/cocktails）。
class CocktailListPage extends StatefulWidget {
  const CocktailListPage({super.key, this.initialKeyword});

  final String? initialKeyword;

  @override
  State<CocktailListPage> createState() => _CocktailListPageState();
}

class _CocktailListPageState extends State<CocktailListPage> {
  static const int _pageSize = 20;
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列1.png';

  final SiponApiService _api = SiponApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<CocktailInfo> _items = [];
  bool _loading = false;
  bool _loaded = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _keyword = '';
  int _nextOffset = 0;

  @override
  void initState() {
    super.initState();
    _keyword = widget.initialKeyword?.trim() ?? '';
    _searchController.text = _keyword;
    // 监听滚动到底部，触发分页加载更多。
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 拉取鸡尾酒列表；[reset] 为 true 时回到第一页重载。
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
    final offset = reset ? 0 : _nextOffset;
    try {
      final list = await _api.searchCocktails(
        keyword: _keyword.isEmpty ? null : _keyword,
        page: SiponPage(limit: _pageSize, offset: offset),
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(CocktailInfo.listFromJson(list));
        _nextOffset = offset + list.length;
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

  /// 搜索框提交：以关键词重新拉取第一页。
  void _onSearchSubmitted(String value) {
    final keyword = value.trim();
    if (keyword == _keyword) return;
    _keyword = keyword;
    _load(reset: true);
  }

  /// 打开鸡尾酒详情页。
  void _openDetail(CocktailInfo item) {
    final id = item.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocktailDetailPage(
          cocktailId: id,
          // 带上列表已有摘要，详情页先渲染封面/名称，不再等接口转圈。
          initialSummary: item,
        ),
      ),
    );
  }

  /// 打开配料百科列表页。
  void _openIngredientList() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const IngredientListPage()));
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
                    child: _ListTopBar(
                      title: text.t('鸡尾酒'),
                      back: text.back,
                      trailing: TextButton(
                        onPressed: () => _openIngredientList(),
                        style: TextButton.styleFrom(
                          foregroundColor: _brand,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(48, 34),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          text.t('配料'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
                    child: _SearchField(
                      controller: _searchController,
                      hint: text.t('搜索鸡尾酒'),
                      onSubmit: _onSearchSubmitted,
                    ),
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
      return _ErrorRetry(
        message: text.t(_error!),
        onRetry: () => _load(reset: true),
      );
    }
    if (_loaded && _items.isEmpty) {
      return _EmptyView(message: text.t('没有找到相关鸡尾酒'));
    }

    return ListView.separated(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      // 底部预留系统安全区（Home Indicator），内容滚动时可经过小白条区域。
      padding: EdgeInsets.fromLTRB(
        22,
        10,
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
        return _CocktailListCard(item: item, onTap: () => _openDetail(item));
      },
    );
  }
}

/// 列表页顶部：返回按钮 + 标题（可带右侧操作）。
class _ListTopBar extends StatelessWidget {
  const _ListTopBar({required this.title, required this.back, this.trailing});

  final String title;
  final String back;

  /// 右侧可选操作（如跳转配料百科）。
  final Widget? trailing;

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
                foregroundColor: _CocktailListPageState._ink,
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
                color: _CocktailListPageState._ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// 关键词搜索输入框。
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: onSubmit,
      style: const TextStyle(
        color: _CocktailListPageState._ink,
        fontSize: 15,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: _CocktailListPageState._muted,
          fontSize: 14,
          letterSpacing: 0,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 20,
          color: _CocktailListPageState._muted,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.9),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// 单条鸡尾酒横向卡片：左侧图 + 右侧名称/评分/简介。
class _CocktailListCard extends StatelessWidget {
  const _CocktailListCard({required this.item, required this.onTap});

  final CocktailInfo item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = item.name ?? (item.nameEn ?? '');
    if (name.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CocktailThumb(
                // 96pt 小图用 320 档即可，避免 96px 的坑位加载整张原图。
                imageUrl: item.resolvedThumbnailUrl(),
                fallbackAsset: _CocktailListPageState._fallbackAsset,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _CocktailListPageState._ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        if (item.starRating != null)
                          _StarRating(rating: item.starRating!),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _CocktailListPageState._muted,
                          fontSize: 12,
                          height: 1.35,
                          letterSpacing: 0,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.difficulty != null &&
                            item.difficulty!.isNotEmpty)
                          _Tag(label: item.difficulty!),
                        if (item.ingredientCount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${item.ingredientCount}种用料',
                            style: const TextStyle(
                              color: _CocktailListPageState._muted,
                              fontSize: 11,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
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

/// 网络图 + 本地素材回退的鸡尾酒/配料缩略图。
class _CocktailThumb extends StatelessWidget {
  const _CocktailThumb({this.imageUrl, required this.fallbackAsset});

  final String? imageUrl;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SiponNetworkImage(
          url: url,
          fallbackAsset: fallbackAsset,
          width: 96,
          height: 96,
          // 按显示尺寸解码，避免小坑位全尺寸解码原图。
          cacheWidth: (96 * dpr).round(),
          cacheHeight: (96 * dpr).round(),
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
        width: 96,
        height: 96,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// 星星评分显示（1-5 星）。
class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final count = rating.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF2A33C)),
        const SizedBox(width: 2),
        Text(
          '$rating',
          style: const TextStyle(
            color: _CocktailListPageState._muted,
            fontSize: 11,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// 小型标签（如难度）。
class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: _CocktailListPageState._brand,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// 加载失败 + 点击重试。
class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 40,
            color: _CocktailListPageState._muted,
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _CocktailListPageState._muted,
                fontSize: 13,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE8F6),
              foregroundColor: _CocktailListPageState._brand,
            ),
            child: Text(text.t('点击重试')),
          ),
        ],
      ),
    );
  }
}

/// 空列表提示。
class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_bar_rounded,
            size: 40,
            color: _CocktailListPageState._muted,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              color: _CocktailListPageState._muted,
              fontSize: 13,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
