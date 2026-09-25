import 'package:flutter/material.dart';

import '../../../../app/theme/sipon_theme_colors.dart';
import '../../../../shared/services/sipon_api_client.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';
import '../../../../shared/widgets/sipon_network_image.dart';
import 'cocktail_detail_page.dart';
import '../../../../shared/localization/language_transform.dart';

/// 配料百科——详情页（GET /api/ingredients/{id} + 相关鸡尾酒列表）。
class IngredientDetailPage extends StatefulWidget {
  const IngredientDetailPage({super.key, required this.ingredientId});

  final int ingredientId;

  @override
  State<IngredientDetailPage> createState() => _IngredientDetailPageState();
}

class _IngredientDetailPageState extends State<IngredientDetailPage> {
  // 私有浅色色板已移除：品牌/正文/次要文字统一在 build 中读主题语义色
  // （scheme.primary / scheme.onSurface / scheme.onSurfaceVariant）。
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列2.png';

  final SiponApiService _api = SiponApiService();

  IngredientInfo? _ingredient;
  List<CocktailInfo> _cocktails = const [];
  bool _loading = false;
  bool _cocktailsLoaded = false;
  bool _cocktailsFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 并行拉取配料详情与"可用此配料调制的鸡尾酒"，互不阻塞。
  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _cocktailsFailed = false;
    });
    try {
      final results = await Future.wait<Object?>([
        _api.getIngredientDetail(widget.ingredientId),
        _safeGetCocktails(),
      ]);
      if (!mounted) return;
      setState(() {
        _ingredient = IngredientInfo.fromJson(results[0]);
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// 拉取相关鸡尾酒列表；失败不阻塞详情展示，置失败标记。
  Future<Object?> _safeGetCocktails() async {
    try {
      final list = await _api.getCocktailsByIngredient(
        widget.ingredientId,
        page: const SiponPage(limit: 20),
      );
      if (mounted) {
        setState(() {
          _cocktails = CocktailInfo.listFromJson(list);
          _cocktailsLoaded = true;
        });
      }
      return null;
    } on Exception {
      if (mounted) {
        setState(() => _cocktailsFailed = true);
      }
      return null;
    }
  }

  /// 打开鸡尾酒详情页。
  void _openCocktail(CocktailInfo item) {
    final id = item.id;
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocktailDetailPage(cocktailId: id),
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
    final ingredient = _ingredient;

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
              child: _buildBody(text, ingredient),
            ),
          ),
        ),
      ),
    );
  }

  /// 依据加载/错误/详情状态渲染内容。
  Widget _buildBody(SiponAppText text, IngredientInfo? ingredient) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading && ingredient == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && ingredient == null) {
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
    if (ingredient == null) {
      return const SizedBox.shrink();
    }

    final name = ingredient.name ?? (ingredient.nameEn ?? '');

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              // 顶部大图。
              _IngredientHero(
                imageUrl: ingredient.resolvedImageUrl(),
                fallbackAsset: _fallbackAsset,
              ),
              // 悬浮返回按钮。
              Positioned(
                top: 10,
                left: 22,
                child: _IngredientBackButton(back: text.back),
              ),
            ],
          ),
        ),
        SliverPadding(
          // 底部预留系统安全区（Home Indicator）。
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            28 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.list(
            children: [
              // 名称与分类信息。
              Text(
                name,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              if (ingredient.nameEn != null &&
                  ingredient.nameEn!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  ingredient.nameEn!,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (ingredient.category != null &&
                      ingredient.category!.isNotEmpty)
                    _IngredientTag(label: ingredient.category!),
                  if (ingredient.baseSpirit == true) ...[
                    const SizedBox(width: 8),
                    const _IngredientTag(label: '基酒'),
                  ],
                ],
              ),
              // 相关鸡尾酒区块。
              const SizedBox(height: 18),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.t('可用此配料调制的鸡尾酒'),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildCocktailList(text),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 依据相关鸡尾酒加载状态渲染子列表。
  Widget _buildCocktailList(SiponAppText text) {
    final scheme = Theme.of(context).colorScheme;
    if (!_cocktailsLoaded && !_cocktailsFailed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (_cocktailsFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text.t('相关鸡尾酒加载失败'),
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
            letterSpacing: 0,
          ),
        ),
      );
    }
    if (_cocktails.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text.t('暂未收录相关鸡尾酒'),
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13,
            letterSpacing: 0,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final cocktail in _cocktails)
          _RelatedCocktailTile(
            cocktail: cocktail,
            onTap: () => _openCocktail(cocktail),
          ),
      ],
    );
  }
}

/// 顶部大图：网络图 + 本地素材回退。
class _IngredientHero extends StatelessWidget {
  const _IngredientHero({this.imageUrl, required this.fallbackAsset});

  final String? imageUrl;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    const height = 240.0;
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        height: height,
        child: SiponNetworkImage(url: url, fallbackAsset: fallbackAsset),
      );
    }
    return SizedBox(
      height: height,
      child: Image.asset(fallbackAsset, fit: BoxFit.cover),
    );
  }
}

/// 悬浮的圆形返回按钮。
class _IngredientBackButton extends StatelessWidget {
  const _IngredientBackButton({required this.back});

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

/// 小标签（分类 / 基酒）。
class _IngredientTag extends StatelessWidget {
  const _IngredientTag({required this.label});

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

/// 相关鸡尾酒行：名称 + 用量数 + 简介，点击跳详情。
class _RelatedCocktailTile extends StatelessWidget {
  const _RelatedCocktailTile({required this.cocktail, required this.onTap});

  final CocktailInfo cocktail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = cocktail.name ?? (cocktail.nameEn ?? '');
    if (name.isEmpty) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  if (cocktail.ingredientCount != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${cocktail.ingredientCount}种用料',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
