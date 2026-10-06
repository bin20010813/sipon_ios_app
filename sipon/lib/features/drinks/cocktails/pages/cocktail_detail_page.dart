import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../../../app/theme/sipon_theme_colors.dart';
import '../../../../shared/services/sipon_api_client.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';
// 虚拟饮酒模块暂时停用。
// import '../../virtual_drinking/models/virtual_drinking_models.dart';
import '../../../../shared/localization/language_transform.dart';
// 虚拟饮酒模块暂时停用。
// import '../../virtual_drinking/pages/virtual_drinking_page.dart';
import '../data/recipe_ingredient_repository.dart';
import '../data/cocktail_image_cache.dart';
import '../widgets/drink_detail_cover.dart';
import '../widgets/recipe_ingredient_fan.dart';
import 'ingredient_detail_page.dart';

export '../widgets/drink_detail_cover.dart'
    show
        kCocktailDetailCoverWidth,
        kCocktailDetailCoverHeight,
        cocktailDetailCoverImageProvider;

/// 鸡尾酒百科——详情页（GET /api/cocktails/{id}）。
class CocktailDetailPage extends StatefulWidget {
  const CocktailDetailPage({
    super.key,
    required this.cocktailId,
    this.initialSummary,
    this.apiService,
  });

  final int cocktailId;

  /// 上游列表页已拿到的摘要；先渲染封面与名称，详情接口后台补齐用料与故事，
  /// 避免封面等接口返回后才开始下载图片。
  final CocktailInfo? initialSummary;
  final SiponApiService? apiService;

  @override
  State<CocktailDetailPage> createState() => _CocktailDetailPageState();
}

class _CocktailDetailPageState extends State<CocktailDetailPage> {
  // 私有浅色色板已移除：品牌/正文/次要文字统一在 build 中读主题语义色
  // （scheme.primary / scheme.onSurface / scheme.onSurfaceVariant）。
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列1.png';

  late final SiponApiService _api = widget.apiService ?? SiponApiService();
  // 虚拟饮酒模块暂时停用。
  //   late final Future<String?> _virtualDrinkCode = _findVirtualDrinkCode();

  CocktailDetailInfo? _detail;
  List<RecipeIngredient> _recipeIngredients = const [];
  final Set<String> _preloadedRecipeImageUrls = {};

  bool _loading = false;
  bool _recipeAnimationTriggered = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSummary;
    if (initial != null) {
      _detail = CocktailDetailInfo(summary: initial);
    }
    _load();
  }

  /// 拉取鸡尾酒详情。
  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final json = await _api.getCocktailDetail(widget.cocktailId);
      if (!mounted) return;
      final detail = CocktailDetailInfo.fromJson(json);
      final lines = detail.sortedIngredients;
      _preloadedRecipeImageUrls.clear();
      setState(() {
        _detail = detail;
        _recipeIngredients = lines.map(RecipeIngredient.fromLine).toList();
      });
      if (lines.isNotEmpty) {
        _preloadRecipeImages(_recipeIngredients);
        unawaited(_loadRecipeImages(lines));
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRecipeImages(List<RecipeLine> lines) async {
    await RecipeIngredientRepository(_api).resolve(
      lines,
      onUpdate: (items) {
        if (!mounted) return;
        setState(() => _recipeIngredients = items);
        _preloadRecipeImages(items);
      },
    );
  }

  void _preloadRecipeImages(List<RecipeIngredient> items) {
    final pending = <IngredientInfo>[];
    for (final item in items) {
      final url = item.ingredient.resolvedImageUrl();
      if (url != null && _preloadedRecipeImageUrls.add(url)) {
        pending.add(item.ingredient);
      }
    }
    if (pending.isEmpty) return;
    unawaited(
      CocktailImageCache.instance.preloadRecipeIngredients(pending, context),
    );
  }

  void _openIngredient(IngredientInfo ingredient) {
    final id = ingredient.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IngredientDetailPage(ingredientId: id),
      ),
    );
  }

  //   Future<String?> _findVirtualDrinkCode() async {
  //     try {
  //       final catalog = VirtualDrinkingCatalog.fromJson(
  //         await _api.getVirtualDrinkingBootstrap(),
  //       );
  //       for (final drink in catalog.drinks) {
  //         if (drink.cocktailId == widget.cocktailId) return drink.code;
  //       }
  //     } on Exception {
  //       // 目录不可用时仍可正常阅读鸡尾酒百科。
  //     }
  //     return null;
  //   }
  //
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
    final detail = _detail;

    return Scaffold(
      body: DecoratedBox(
        // 页面渐变跟随主题外观。
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: context.siponColors.pageGradient,
            stops: const [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          // bottom:false 让详情内容视口延伸到屏幕底，内容可滚过小白条区域；
          // 底部空间由 CustomScrollView 末尾的 SliverPadding 预留。
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: _buildBody(text, detail),
            ),
          ),
        ),
      ),
    );
  }

  /// 依据加载/错误/详情状态渲染内容。
  Widget _buildBody(SiponAppText text, CocktailDetailInfo? detail) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && detail == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                text.t(_error!),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: context.siponColors.brandSurface,
                foregroundColor: scheme.primary,
              ),
              child: Text(text.t('点击重试')),
            ),
          ],
        ),
      );
    }
    if (detail == null) {
      return const SizedBox.shrink();
    }

    final summary = detail.summary;
    final name = summary.name ?? (summary.nameEn ?? '');
    // 封面用长边 640px 中图：详情展示尺寸下与原图几乎无差，下载体积小得多；
    // 后端未生成中图时 resolvedMediumImageUrl 已逐级回退缩略图/原图。
    final imageUrl =
        summary.resolvedMediumImageUrl() ?? summary.resolvedImageUrl();
    final ingredients = detail.sortedIngredients;

    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (!_recipeAnimationTriggered &&
            notification.depth == 0 &&
            notification.direction == ScrollDirection.reverse) {
          setState(() => _recipeAnimationTriggered = true);
        }
        return false;
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 返回按钮。
                  _FloatingBackButton(back: text.back),
                  const SizedBox(height: 8),
                  // 居中大图头部。
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(
                        child: SizedBox(
                          width: 240,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: DrinkDetailCover(
                              imageUrl: imageUrl,
                              fallbackAsset: _fallbackAsset,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      if (summary.nameEn != null &&
                          summary.nameEn!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          summary.nameEn!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                      if (summary.starRating != null) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: _DoubanRating(rating: summary.starRating!),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (summary.difficulty != null &&
                              summary.difficulty!.isNotEmpty)
                            _MetaTag(label: summary.difficulty!),
                          if (summary.ingredientCount != null)
                            _MetaTag(label: '${summary.ingredientCount}种用料'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            // 底部预留系统安全区（Home Indicator）。
            padding: EdgeInsets.fromLTRB(
              22,
              12,
              22,
              28 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                //                 FutureBuilder<String?>(
                //                   future: _virtualDrinkCode,
                //                   builder: (context, snapshot) {
                //                     final code = snapshot.data;
                //                     if (code == null) return const SizedBox.shrink();
                //                     return Padding(
                //                       padding: const EdgeInsets.only(bottom: 18),
                //                       child: FilledButton.icon(
                //                         onPressed: () => Navigator.of(context).push(
                //                           MaterialPageRoute<void>(
                //                             builder: (_) =>
                //                                 VirtualDrinkingPage(initialDrinkCode: code),
                //                           ),
                //                         ),
                //                         icon: const Icon(Icons.nightlife_rounded),
                //                         label: Text(text.t('在虚拟小酌体验这杯')),
                //                         style: FilledButton.styleFrom(
                //                           backgroundColor: scheme.primary,
                //                           minimumSize: const Size.fromHeight(46),
                //                         ),
                //                       ),
                //                     );
                //                   },
                //                 ),
                // 简介。
                if (summary.description != null &&
                    summary.description!.isNotEmpty) ...[
                  _SectionBlock(
                    title: text.t('简介'),
                    child: Text(
                      summary.description!,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 16,
                        height: 1.5,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // 背后的故事。
                if (detail.story != null && detail.story!.isNotEmpty) ...[
                  _SectionBlock(
                    title: text.t('背后的故事'),
                    child: Text(
                      detail.story!,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 16,
                        height: 1.5,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                // 用料清单。
                _SectionBlock(
                  title: text.t('用料'),
                  child: ingredients.isEmpty
                      ? Text(
                          text.t(_loading ? '加载中…' : '暂无用料信息'),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 15,
                            letterSpacing: 0,
                          ),
                        )
                      : RecipeIngredientFan(
                          key: ValueKey(widget.cocktailId),
                          items: _recipeIngredients,
                          animationTriggered: _recipeAnimationTriggered,
                          onIngredientTap: _openIngredient,
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

/// 豆瓣风格评分：星星 + 分值大字。
class _DoubanRating extends StatelessWidget {
  const _DoubanRating({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rating.clamp(0, 5); i++)
          Icon(
            Icons.star_rounded,
            size: 18,
            color: context.siponColors.starRating,
          ),
        const SizedBox(width: 6),
        Text(
          '$rating',
          style: TextStyle(
            color: context.siponColors.starRating,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '分',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 12,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

/// 悬浮的圆形返回按钮。
class _FloatingBackButton extends StatelessWidget {
  const _FloatingBackButton({required this.back});

  final String back;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: back,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          fixedSize: const Size(40, 40),
          // 悬浮按钮：半透明表面色 + 主题正文色图标。
          backgroundColor: scheme.surface.withValues(alpha: 0.85),
          foregroundColor: scheme.onSurface,
          padding: EdgeInsets.zero,
          shape: const CircleBorder(),
        ),
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      ),
    );
  }
}

/// 元信息小标签。
class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.siponColors.brandSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// 主题表面色圆角内容区块。
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
