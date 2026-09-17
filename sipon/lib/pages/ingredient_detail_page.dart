import 'package:flutter/material.dart';

import '../services/sipon_api_client.dart';
import '../services/sipon_api_models.dart';
import '../services/sipon_api_service.dart';
import 'cocktail_detail_page.dart';
import 'language_transform.dart';

/// 配料百科——详情页（GET /api/ingredients/{id} + 相关鸡尾酒列表）。
class IngredientDetailPage extends StatefulWidget {
  const IngredientDetailPage({super.key, required this.ingredientId});

  final int ingredientId;

  @override
  State<IngredientDetailPage> createState() => _IngredientDetailPageState();
}

class _IngredientDetailPageState extends State<IngredientDetailPage> {
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
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
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFCFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
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
    if (_loading && ingredient == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && ingredient == null) {
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
              onPressed: _load,
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
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          sliver: SliverList.list(
            children: [
              // 名称与分类信息。
              Text(
                name,
                style: const TextStyle(
                  color: _ink,
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
                  style: const TextStyle(
                    color: _muted,
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
                  color: Colors.white.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.t('可用此配料调制的鸡尾酒'),
                        style: const TextStyle(
                          color: _ink,
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
          style: const TextStyle(color: _muted, fontSize: 13, letterSpacing: 0),
        ),
      );
    }
    if (_cocktails.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text.t('暂未收录相关鸡尾酒'),
          style: const TextStyle(color: _muted, fontSize: 13, letterSpacing: 0),
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
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => SizedBox(
            height: height,
            child: Image.asset(fallbackAsset, fit: BoxFit.cover),
          ),
        ),
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
    return Tooltip(
      message: back,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          fixedSize: const Size(40, 40),
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          foregroundColor: _IngredientDetailPageState._ink,
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
        color: const Color(0xFFFFE8F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: _IngredientDetailPageState._brand,
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
                    style: const TextStyle(
                      color: _IngredientDetailPageState._ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  if (cocktail.ingredientCount != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${cocktail.ingredientCount}种用料',
                      style: const TextStyle(
                        color: _IngredientDetailPageState._muted,
                        fontSize: 11,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: _IngredientDetailPageState._muted,
            ),
          ],
        ),
      ),
    );
  }
}
