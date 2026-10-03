import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/sipon_theme_colors.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../data/cocktail_image_cache.dart';
import '../data/recipe_ingredient_repository.dart';

/// 用料图片从中央依次发出，沿扇形展开；用量保持水平，便于阅读。
class RecipeIngredientFan extends StatefulWidget {
  const RecipeIngredientFan({
    super.key,
    required this.items,
    required this.animationTriggered,
    this.loading = false,
    this.onIngredientTap,
  });

  final List<RecipeIngredient> items;
  final bool animationTriggered;
  final bool loading;
  final ValueChanged<IngredientInfo>? onIngredientTap;

  @override
  State<RecipeIngredientFan> createState() => _RecipeIngredientFanState();
}

class _RecipeIngredientFanState extends State<RecipeIngredientFan>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _controller.value = 1;
    } else {
      _scheduleAnimationStart();
    }
  }

  @override
  void didUpdateWidget(covariant RecipeIngredientFan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationTriggered != widget.animationTriggered ||
        (oldWidget.loading && !widget.loading) ||
        (oldWidget.items.isEmpty && widget.items.isNotEmpty)) {
      _scheduleAnimationStart();
    }
  }

  void _scheduleAnimationStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _started ||
          !widget.animationTriggered ||
          widget.loading ||
          widget.items.isEmpty) {
        return;
      }
      _started = true;
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // 多配料分行发牌，避免窄屏上封面与用量被挤成细条。
        final perRow = width >= 340 ? 4 : 3;
        return Column(
          children: [
            for (var start = 0; start < widget.items.length; start += perRow)
              _buildRow(
                context,
                width,
                start,
                widget.items.skip(start).take(perRow).toList(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    double width,
    int start,
    List<RecipeIngredient> items,
  ) {
    const gap = 10.0;
    const sidePadding = 24.0;
    const topPadding = 18.0;
    const arcHeight = 14.0;
    final cardWidth = math
        .min(
          kRecipeIngredientCardMaxWidth,
          (width - sidePadding * 2 - gap * (items.length - 1)) / items.length,
        )
        .clamp(24.0, kRecipeIngredientCardMaxWidth);
    final coverHeight = cardWidth * 4 / 3;
    final amountStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );
    final amountHeight = items.fold<double>(0, (height, item) {
      final painter = TextPainter(
        text: TextSpan(text: item.line.amountText ?? '', style: amountStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: cardWidth);
      final result = math.max(height, painter.height);
      painter.dispose();
      return result;
    });
    final height =
        topPadding + arcHeight + coverHeight + 16 + amountHeight + 16;
    final images = [
      for (final item in items)
        _IngredientImage(
          ingredient: item.ingredient,
          width: cardWidth,
          height: coverHeight,
        ),
    ];

    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(
            children: [
              for (var index = 0; index < items.length; index++)
                _buildCard(
                  items[index],
                  images[index],
                  index: index,
                  start: start,
                  count: items.length,
                  width: width,
                  cardWidth: cardWidth,
                  coverHeight: coverHeight,
                  amountHeight: amountHeight,
                  amountStyle: amountStyle,
                  gap: gap,
                  topPadding: topPadding,
                  arcHeight: arcHeight,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    RecipeIngredient item,
    Widget image, {
    required int index,
    required int start,
    required int count,
    required double width,
    required double cardWidth,
    required double coverHeight,
    required double amountHeight,
    required TextStyle amountStyle,
    required double gap,
    required double topPadding,
    required double arcHeight,
  }) {
    final delay = 0.42 * (start + index) / math.max(1, widget.items.length - 1);
    final progress = Interval(
      delay,
      delay + 0.58,
      curve: Curves.easeOutCubic,
    ).transform(_controller.value);
    final middle = (count - 1) / 2;
    final direction = count == 1 ? 0.0 : (index - middle) / middle;
    final originX = (width - cardWidth) / 2;
    final targetX = originX + (index - middle) * (cardWidth + gap);
    final targetY = topPadding + direction.abs() * arcHeight;
    final enabled =
        item.ingredient.id != null && widget.onIngredientTap != null;
    final label = [
      item.ingredient.name ?? item.ingredient.nameEn ?? item.line.code ?? '',
      item.line.amountText ?? '',
    ].where((part) => part.isNotEmpty).join('，');

    return Positioned(
      key: ValueKey('recipe-card-${start + index}'),
      left: originX + (targetX - originX) * progress,
      top: topPadding + 28 + (targetY - topPadding - 28) * progress,
      width: cardWidth,
      child: IgnorePointer(
        ignoring: progress < 1,
        child: Opacity(
          opacity: widget.loading ? 0.35 : (progress * 4).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.88 + progress * 0.12,
            child: Semantics(
              label: label,
              button: enabled,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled
                    ? () => widget.onIngredientTap!(item.ingredient)
                    : null,
                child: Column(
                  children: [
                    Transform.rotate(
                      angle: direction * 0.16 * progress,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: cardWidth,
                        height: coverHeight,
                        child: image,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: cardWidth,
                      height: amountHeight,
                      child: Text(
                        item.line.amountText ?? '',
                        textAlign: TextAlign.center,
                        style: amountStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IngredientImage extends StatelessWidget {
  const _IngredientImage({
    required this.ingredient,
    required this.width,
    required this.height,
  });

  final IngredientInfo ingredient;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = ingredient.resolvedImageUrl();
    final placeholder = ColoredBox(
      color: context.siponColors.brandSurface,
      child: Center(
        child: Icon(
          Icons.liquor_outlined,
          size: width * 0.45,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: context.siponColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: url == null
            ? placeholder
            : Image(
                image: CocktailImageCache.instance.ingredientProvider(url, dpr),
                width: width,
                height: height,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                frameBuilder: (context, child, frame, synchronouslyLoaded) =>
                    synchronouslyLoaded || frame != null ? child : placeholder,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}
