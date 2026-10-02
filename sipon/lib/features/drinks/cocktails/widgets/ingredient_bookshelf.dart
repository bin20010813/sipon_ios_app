import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/sipon_theme_colors.dart';
import '../../../../shared/services/sipon_api_models.dart';
import '../../../../shared/widgets/sipon_network_image.dart';

/// 三层配料书架，封面按 3:4 展示，各层首尾相接循环移动。
class IngredientBookshelf extends StatelessWidget {
  const IngredientBookshelf({
    super.key,
    required this.items,
    required this.fallbackAsset,
    required this.onIngredientTap,
  });

  final List<IngredientInfo> items;
  final String fallbackAsset;
  final ValueChanged<IngredientInfo> onIngredientTap;

  @override
  Widget build(BuildContext context) {
    final books = items
        .where((item) => (item.name ?? item.nameEn ?? '').trim().isNotEmpty)
        .toList();
    if (books.isEmpty) return const SizedBox.shrink();

    final rows = List.generate(3, (row) {
      final entries = [
        for (var index = row; index < books.length; index += 3) books[index],
      ];
      return entries.isEmpty ? books : entries;
    });
    final labelHeight = MediaQuery.textScalerOf(context).scale(12) * 2.8;
    // viewPadding 不随键盘展开归零，避免封面尺寸跟着安全区变化。
    final bottomPadding = 20 + MediaQuery.viewPaddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        const topPadding = 14.0;
        const rowGap = 18.0;
        final rowHeight =
            (constraints.maxHeight - topPadding - bottomPadding - rowGap * 2) /
            3;
        final coverHeight = (rowHeight - labelHeight - 28).clamp(88.0, 168.0);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: Column(
            children: [
              for (var row = 0; row < 3; row++) ...[
                if (row > 0) const SizedBox(height: rowGap),
                _LoopingIngredientShelf(
                  items: rows[row],
                  row: row,
                  moveRight: row != 1,
                  coverWidth: coverHeight * 3 / 4,
                  labelHeight: labelHeight,
                  fallbackAsset: fallbackAsset,
                  onIngredientTap: onIngredientTap,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LoopingIngredientShelf extends StatefulWidget {
  const _LoopingIngredientShelf({
    required this.items,
    required this.row,
    required this.moveRight,
    required this.coverWidth,
    required this.labelHeight,
    required this.fallbackAsset,
    required this.onIngredientTap,
  });

  final List<IngredientInfo> items;
  final int row;
  final bool moveRight;
  final double coverWidth;
  final double labelHeight;
  final String fallbackAsset;
  final ValueChanged<IngredientInfo> onIngredientTap;

  @override
  State<_LoopingIngredientShelf> createState() =>
      _LoopingIngredientShelfState();
}

class _LoopingIngredientShelfState extends State<_LoopingIngredientShelf>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _bookGap = 14.0;
  static const _pixelsPerSecond = 18.0;
  late final AnimationController _motion;
  bool _holding = false;
  bool _appActive = true;
  double _dragOffset = 0;

  double get _bookExtent => widget.coverWidth + _bookGap;
  double get _cycleWidth => _bookExtent * widget.items.length;
  Duration get _period => Duration(
    microseconds: (_cycleWidth / _pixelsPerSecond * 1000000).round(),
  );

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _LoopingIngredientShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.coverWidth != widget.coverWidth) {
      _motion.stop();
      _syncMotion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _syncMotion() {
    final animate =
        _appActive &&
        !_holding &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_motion.isAnimating) _motion.repeat(period: _period);
    } else {
      _motion.stop();
    }
  }

  void _hold(bool holding) {
    _holding = holding;
    _syncMotion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bookHeight = widget.coverWidth * 4 / 3 + 10 + widget.labelHeight;

    return Column(
      children: [
        SizedBox(
          height: bookHeight + 6,
          child: Listener(
            onPointerDown: (_) => _hold(true),
            onPointerUp: (_) => _hold(false),
            onPointerCancel: (_) => _hold(false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _dragOffset = (_dragOffset - details.delta.dx) % _cycleWidth;
                });
              },
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 只创建视口内的封面；取模后自然衔接下一轮，没有回跳。
                    final visibleCount =
                        (constraints.maxWidth / _bookExtent).ceil() + 1;
                    return AnimatedBuilder(
                      animation: _motion,
                      builder: (context, _) {
                        final direction = widget.moveRight ? -1 : 1;
                        final offset =
                            (_motion.value * _cycleWidth * direction +
                                _dragOffset +
                                widget.row * _bookExtent * 0.35) %
                            _cycleWidth;
                        final first = (offset / _bookExtent).floor();
                        final leading = -(offset % _bookExtent);

                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var slot = 0; slot < visibleCount; slot++)
                              Positioned(
                                left: leading + slot * _bookExtent,
                                top: 6,
                                width: widget.coverWidth,
                                height: bookHeight,
                                child: _IngredientBook(
                                  item:
                                      widget.items[(first + slot) %
                                          widget.items.length],
                                  labelHeight: widget.labelHeight,
                                  fallbackAsset: widget.fallbackAsset,
                                  onTap: widget.onIngredientTap,
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Container(
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [scheme.surface, context.siponColors.subtleSurface],
            ),
            border: Border.all(color: scheme.onSurface.withValues(alpha: 0.09)),
            boxShadow: [
              BoxShadow(
                color: context.siponColors.shadow,
                blurRadius: 8,
                offset: const Offset(0, 5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 书本封面：3:4 图片与下方居中的配料名称。
class _IngredientBook extends StatelessWidget {
  const _IngredientBook({
    required this.item,
    required this.labelHeight,
    required this.fallbackAsset,
    required this.onTap,
  });

  final IngredientInfo item;
  final double labelHeight;
  final String fallbackAsset;
  final ValueChanged<IngredientInfo> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = item.name ?? item.nameEn ?? '';
    final url = item.resolvedImageUrl();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.id == null ? null : () => onTap(item),
        borderRadius: BorderRadius.circular(6),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final dpr = MediaQuery.devicePixelRatioOf(context);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: context.siponColors.shadow,
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (url != null && url.isNotEmpty)
                            SiponNetworkImage(
                              url: url,
                              fallbackAsset: fallbackAsset,
                              cacheWidth: math.max(
                                1,
                                (constraints.maxWidth * dpr).round(),
                              ),
                              cacheHeight: math.max(
                                1,
                                (constraints.maxHeight * dpr).round(),
                              ),
                            )
                          else
                            Image.asset(fallbackAsset, fit: BoxFit.cover),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: 5,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    context.siponColors.scrim.withValues(
                                      alpha: 0.2,
                                    ),
                                    context.siponColors.scrim.withValues(
                                      alpha: 0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: labelHeight,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
