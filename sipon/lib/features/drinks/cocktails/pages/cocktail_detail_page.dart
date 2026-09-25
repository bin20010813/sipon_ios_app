import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/sipon_theme_colors.dart';
import '../../../../shared/services/sipon_api_client.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/services/sipon_api_service.dart';
import '../../virtual_drinking/models/virtual_drinking_models.dart';
import '../../../../shared/localization/language_transform.dart';
import '../../virtual_drinking/pages/virtual_drinking_page.dart';

/// 封面显示尺寸（逻辑像素）；预取与展示共用，保证解码缓存键一致。
const double kCocktailDetailCoverWidth = 260.0;
const double kCocktailDetailCoverHeight = 347.0;

/// 详情封面的图片 Provider：按封面显示尺寸（260×347 × dpr）解码。
/// 首页/列表预取与详情页展示必须共用同一 Provider（同一缓存键），
/// 预取后点进详情才能直接命中内存缓存；磁盘缓存由 CachedNetworkImageProvider 提供。
ImageProvider cocktailDetailCoverImageProvider(String url, double dpr) =>
    ResizeImage(
      CachedNetworkImageProvider(url),
      width: (kCocktailDetailCoverWidth * dpr).round(),
      height: (kCocktailDetailCoverHeight * dpr).round(),
    );

/// 鸡尾酒百科——详情页（GET /api/cocktails/{id}）。
class CocktailDetailPage extends StatefulWidget {
  const CocktailDetailPage({
    super.key,
    required this.cocktailId,
    this.initialSummary,
  });

  final int cocktailId;

  /// 上游列表页已拿到的摘要；先渲染封面与名称，详情接口后台补齐用料与故事，
  /// 避免封面等接口返回后才开始下载图片。
  final CocktailInfo? initialSummary;

  @override
  State<CocktailDetailPage> createState() => _CocktailDetailPageState();
}

class _CocktailDetailPageState extends State<CocktailDetailPage> {
  // 私有浅色色板已移除：品牌/正文/次要文字统一在 build 中读主题语义色
  // （scheme.primary / scheme.onSurface / scheme.onSurfaceVariant）。
  static const String _fallbackAsset = 'assest/首页/图片素材/鸡尾酒系列1.png';

  final SiponApiService _api = SiponApiService();
  late final Future<String?> _virtualDrinkCode = _findVirtualDrinkCode();

  CocktailDetailInfo? _detail;
  bool _loading = false;
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

  Future<String?> _findVirtualDrinkCode() async {
    try {
      final catalog = VirtualDrinkingCatalog.fromJson(
        await _api.getVirtualDrinkingBootstrap(),
      );
      for (final drink in catalog.drinks) {
        if (drink.cocktailId == widget.cocktailId) return drink.code;
      }
    } on Exception {
      // 目录不可用时仍可正常阅读鸡尾酒百科。
    }
    return null;
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
                // 居中大图头部。
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: _DetailCover(
                        imageUrl: imageUrl,
                        fallbackAsset: _fallbackAsset,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                      const SizedBox(height: 5),
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
                      const SizedBox(height: 12),
                      Center(child: _DoubanRating(rating: summary.starRating!)),
                    ],
                    const SizedBox(height: 12),
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
            18,
            22,
            28 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverList.list(
            children: [
              FutureBuilder<String?>(
                future: _virtualDrinkCode,
                builder: (context, snapshot) {
                  final code = snapshot.data;
                  if (code == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              VirtualDrinkingPage(initialDrinkCode: code),
                        ),
                      ),
                      icon: const Icon(Icons.nightlife_rounded),
                      label: Text(text.t('在虚拟小酌体验这杯')),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  );
                },
              ),
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
                const SizedBox(height: 12),
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
                    : Column(
                        children: [
                          for (
                            var index = 0;
                            index < ingredients.length;
                            index++
                          )
                            _RecipeLineTile(
                              index: index,
                              line: ingredients[index],
                            ),
                        ],
                      ),
              ),
              // 背后的故事。
              if (detail.story != null && detail.story!.isNotEmpty) ...[
                const SizedBox(height: 12),
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
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 居中大图封面。
class _DetailCover extends StatelessWidget {
  const _DetailCover({this.imageUrl, required this.fallbackAsset});

  final String? imageUrl;
  final String fallbackAsset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const coverWidth = 260.0;
    const coverHeight = 347.0;
    const radius = 24.0;
    final url = imageUrl;

    Widget image() {
      if (url != null && url.isNotEmpty) {
        return Container(
          // 加载中/淡入前的占位底色，跟随主题占位色，深色下不再闪白。
          color: context.siponColors.skeleton,
          child: Image(
            image: cocktailDetailCoverImageProvider(
              url,
              MediaQuery.devicePixelRatioOf(context),
            ),
            width: coverWidth,
            height: coverHeight,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: child,
              );
            },
            errorBuilder: (_, _, _) => Image.asset(
              fallbackAsset,
              width: coverWidth,
              height: coverHeight,
              fit: BoxFit.cover,
            ),
          ),
        );
      }
      return Image.asset(
        fallbackAsset,
        width: coverWidth,
        height: coverHeight,
        fit: BoxFit.cover,
      );
    }

    return SizedBox(
      width: coverWidth,
      height: coverHeight + 27,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                // 封面投影与高光都随主题，深色下不再出现白色亮边。
                BoxShadow(
                  color: context.siponColors.shadow,
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 9),
                ),
                BoxShadow(
                  color: scheme.surface.withValues(alpha: 0.7),
                  blurRadius: 6,
                  spreadRadius: -2,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  image(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 36,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        // 封面底部渐隐到页面表面色，深色下不再出现白色亮带。
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.surface.withValues(alpha: 0),
                            scheme.surface.withValues(alpha: 0.22),
                            scheme.surface.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: coverHeight + 1,
            height: 36,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              // dstIn 蒙版语义：白色代表保留、透明代表擦除，与主题无关，保留常量。
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.transparent],
              ).createShader(bounds),
              child: ClipRect(
                child: Opacity(
                  opacity: 0.25,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: coverWidth - 16,
                    maxWidth: coverWidth - 16,
                    minHeight: coverHeight,
                    maxHeight: coverHeight,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..scale(1.0, -1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: image(),
                      ),
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
        padding: const EdgeInsets.all(16),
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
    final scheme = Theme.of(context).colorScheme;
    final ingredientName = line.name ?? line.nameEn ?? line.code;
    final amount = line.amountText;
    if ((ingredientName == null || ingredientName.isEmpty) &&
        (amount == null || amount.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.siponColors.brandSurface,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: scheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  height: 1.4,
                  letterSpacing: 0,
                ),
                children: [
                  if (ingredientName != null && ingredientName.isNotEmpty)
                    TextSpan(
                      text: ingredientName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  if (ingredientName != null &&
                      ingredientName.isNotEmpty &&
                      amount != null &&
                      amount.isNotEmpty)
                    const TextSpan(text: '  '),
                  if (amount != null && amount.isNotEmpty)
                    TextSpan(text: amount),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
