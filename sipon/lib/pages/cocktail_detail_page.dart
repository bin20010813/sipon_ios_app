import 'package:flutter/material.dart';

import '../services/sipon_api_client.dart';
import '../services/sipon_api_models.dart';
import '../services/sipon_api_service.dart';
import 'language_transform.dart';

/// 鸡尾酒百科——详情页（GET /api/cocktails/{id}）。
class CocktailDetailPage extends StatefulWidget {
  const CocktailDetailPage({super.key, required this.cocktailId});

  final int cocktailId;

  @override
  State<CocktailDetailPage> createState() => _CocktailDetailPageState();
}

class _CocktailDetailPageState extends State<CocktailDetailPage> {
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列1.png';

  final SiponApiService _api = SiponApiService();

  CocktailDetailInfo? _detail;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
      setState(() {
        _detail = CocktailDetailInfo.fromJson(json);
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
              child: _buildBody(text, detail),
            ),
          ),
        ),
      ),
    );
  }

  /// 依据加载/错误/详情状态渲染内容。
  Widget _buildBody(SiponAppText text, CocktailDetailInfo? detail) {
    if (_loading && detail == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && detail == null) {
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
    if (detail == null) {
      return const SizedBox.shrink();
    }

    final summary = detail.summary;
    final name = summary.name ?? (summary.nameEn ?? '');
    final imageUrl = summary.resolvedImageUrl();
    final ingredients = detail.sortedIngredients;

    return CustomScrollView(
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
                const SizedBox(height: 16),
                // 豆瓣图书详情页式头部：左竖版封面 + 右书名/评分/标签。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailCover(
                      imageUrl: imageUrl,
                      fallbackAsset: _fallbackAsset,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          if (summary.nameEn != null &&
                              summary.nameEn!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              summary.nameEn!,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                          if (summary.starRating != null) ...[
                            const SizedBox(height: 12),
                            _DoubanRating(rating: summary.starRating!),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
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
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          sliver: SliverList.list(
            children: [
              // 简介。
              if (summary.description != null &&
                  summary.description!.isNotEmpty) ...[
                _SectionBlock(
                  title: text.t('简介'),
                  child: Text(
                    summary.description!,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              // 用料清单。
              _SectionBlock(
                title: text.t('用料'),
                child: ingredients.isEmpty
                    ? Text(
                        text.t('暂无用料信息'),
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          letterSpacing: 0,
                        ),
                      )
                    : Column(
                        children: [
                          for (var index = 0; index < ingredients.length; index++)
                            _RecipeLineTile(index: index, line: ingredients[index]),
                        ],
                      ),
              ),
              // 背后的故事。
              if (detail.story != null && detail.story!.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionBlock(
                  title: text.t('背后的故事'),
                  child: Text(
                    detail.story!,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 豆瓣图书详情页式竖版封面（图书比例，约 2:2.75）。
class _DetailCover extends StatelessWidget {
  const _DetailCover({this.imageUrl, required this.fallbackAsset});

  final String? imageUrl;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    const coverWidth = 128.0;
    const coverHeight = 176.0;
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          width: coverWidth,
          height: coverHeight,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.asset(
        fallbackAsset,
        width: 128,
        height: 176,
        fit: BoxFit.cover,
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
    return Row(
      children: [
        for (var i = 0; i < rating.clamp(0, 5); i++)
          const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF2A33C)),
        const SizedBox(width: 6),
        Text(
          '$rating',
          style: const TextStyle(
            color: Color(0xFFF2A33C),
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 2),
        const Text(
          '分',
          style: TextStyle(
            color: _CocktailDetailPageState._muted,
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
    return Tooltip(
      message: back,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          fixedSize: const Size(40, 40),
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          foregroundColor: _CocktailDetailPageState._ink,
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
        color: const Color(0xFFFFE8F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: _CocktailDetailPageState._brand,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

/// 白底圆角内容区块。
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
              title,
              style: const TextStyle(
                color: _CocktailDetailPageState._ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// 单行用料：序号 + 用量文本。
class _RecipeLineTile extends StatelessWidget {
  const _RecipeLineTile({required this.index, required this.line});

  final int index;
  final RecipeLine line;

  @override
  Widget build(BuildContext context) {
    final amount = line.amountText;
    if (amount == null || amount.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFFFE8F6),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: _CocktailDetailPageState._brand,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              amount,
              style: const TextStyle(
                color: _CocktailDetailPageState._ink,
                fontSize: 14,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}