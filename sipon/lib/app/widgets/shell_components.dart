part of '../sipon_app.dart';

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.mapSheetProgress,
    required this.searchOverlayActive,
    required this.currentIndex,
    required this.reserveHeight,
    required this.bottomGap,
    required this.onTabSelected,
    required this.onPlusPressed,
  });

  final ValueListenable<double> mapSheetProgress;
  final ValueListenable<bool> searchOverlayActive;
  final int currentIndex;
  final double reserveHeight;
  final double bottomGap;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onPlusPressed;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ValueListenableBuilder<double>(
      valueListenable: mapSheetProgress,
      builder: (context, sheetProgress, _) => ValueListenableBuilder<bool>(
        valueListenable: searchOverlayActive,
        builder: (context, searchActive, _) {
          final progress = currentIndex == 1 ? sheetProgress : 0.0;
          // 首页搜索或键盘显示时隐藏底栏，避免误触导航。
          final hidden = keyboardVisible || searchActive;
          return Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              ignoring: hidden || progress > 0.05,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                offset: hidden ? const Offset(0, 1.25) : Offset.zero,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: hidden ? 0 : 1,
                  child: Transform.translate(
                    offset: Offset(0, (reserveHeight + 12) * progress),
                    child: Opacity(
                      opacity: 1 - progress,
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: HomePage.contentMaxWidth,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              HomePage.contentHorizontalPadding,
                              0,
                              HomePage.contentHorizontalPadding,
                              bottomGap,
                            ),
                            child: _SiponBottomJumpBar(
                              currentIndex: currentIndex,
                              onTabSelected: onTabSelected,
                              onPlusPressed: onPlusPressed,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SiponBottomJumpBar extends StatefulWidget {
  static const double height = 62;
  static const double contentInset = 9;
  static const double itemCornerRadius = 30;
  static const double cornerRadius = itemCornerRadius + contentInset;
  static const double itemWidth = 60;
  static const double itemHeight = height - contentInset * 2;

  const _SiponBottomJumpBar({
    required this.currentIndex,
    required this.onTabSelected,
    required this.onPlusPressed,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onPlusPressed;

  @override
  State<_SiponBottomJumpBar> createState() => _SiponBottomJumpBarState();
}

class _SiponBottomJumpBarState extends State<_SiponBottomJumpBar> {
  double? _dragPosition;
  double _dragOrigin = 0;
  double _dragStartIndex = 0;

  void _startDrag(double dx) {
    _dragOrigin = dx;
    _dragStartIndex = widget.currentIndex.toDouble();
    setState(() => _dragPosition = _dragStartIndex);
  }

  void _updateDrag(double dx, double slotWidth) {
    if (_dragPosition == null || slotWidth <= 0) return;
    final direction = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
    setState(() {
      _dragPosition =
          (_dragStartIndex + direction * (dx - _dragOrigin) / slotWidth).clamp(
            0.0,
            3.0,
          );
    });
  }

  void _endDrag() {
    final index = _dragPosition?.round();
    setState(() => _dragPosition = null);
    if (index != null && index != widget.currentIndex) {
      widget.onTabSelected(index);
    }
  }

  void _cancelDrag() => setState(() => _dragPosition = null);

  @override
  void didUpdateWidget(covariant _SiponBottomJumpBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) _dragPosition = null;
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final colors = Theme.of(context).colorScheme;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final labels = [
      text.homeTab,
      text.mapTab,
      text.momentsTab,
      text.profileTab,
    ];
    const icons = [
      Icons.home_rounded,
      Icons.map_rounded,
      Icons.explore_rounded,
      Icons.person_rounded,
    ];

    return Row(
      children: [
        Expanded(
          child: _SiponNavigationGlass(
            radius: _SiponBottomJumpBar.cornerRadius,
            child: SizedBox(
              height: _SiponBottomJumpBar.height,
              child: Padding(
                padding: const EdgeInsets.all(_SiponBottomJumpBar.contentInset),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final slotWidth = constraints.maxWidth / icons.length;
                    final indicatorWidth = math.min(
                      _SiponBottomJumpBar.itemWidth,
                      slotWidth,
                    );
                    final position =
                        _dragPosition ?? widget.currentIndex.toDouble();
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (details) =>
                          _startDrag(details.localPosition.dx),
                      onHorizontalDragUpdate: (details) =>
                          _updateDrag(details.localPosition.dx, slotWidth),
                      onHorizontalDragEnd: (_) => _endDrag(),
                      onHorizontalDragCancel: _cancelDrag,
                      onLongPressStart: (details) =>
                          _startDrag(details.localPosition.dx),
                      onLongPressMoveUpdate: (details) =>
                          _updateDrag(details.localPosition.dx, slotWidth),
                      onLongPressEnd: (_) => _endDrag(),
                      onLongPressCancel: _cancelDrag,
                      child: Stack(
                        children: [
                          AnimatedPositionedDirectional(
                            duration: reduceMotion || _dragPosition != null
                                ? Duration.zero
                                : const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            start:
                                position * slotWidth +
                                (slotWidth - indicatorWidth) / 2,
                            top: 0,
                            width: indicatorWidth,
                            height: _SiponBottomJumpBar.itemHeight,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(
                                    _SiponBottomJumpBar.itemCornerRadius,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.primary.withValues(
                                        alpha: 0.22,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var index = 0; index < icons.length; index++)
                                Expanded(
                                  child: _SiponBottomJumpItem(
                                    tooltip: labels[index],
                                    icon: icons[index],
                                    selected: widget.currentIndex == index,
                                    highlighted: position.round() == index,
                                    inactiveColor: colors.onSurfaceVariant,
                                    onPressed: () =>
                                        widget.onTabSelected(index),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SiponBottomPlusButton(onPressed: widget.onPlusPressed),
      ],
    );
  }
}

class _SiponNavigationGlass extends StatelessWidget {
  const _SiponNavigationGlass({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: dark ? 0.24 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  dark
                      ? scheme.surface.withValues(alpha: 0.56)
                      : Colors.white.withValues(alpha: 0.72),
                  dark
                      ? scheme.surface.withValues(alpha: 0.36)
                      : Colors.white.withValues(alpha: 0.54),
                ],
              ),
              border: Border.all(
                color: dark
                    ? scheme.onSurface.withValues(alpha: 0.16)
                    : Colors.white.withValues(alpha: 0.70),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SiponBottomPlusButton extends StatelessWidget {
  const _SiponBottomPlusButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: SiponLanguageScope.textOf(context).t('更多操作'),
      child: _SiponNavigationGlass(
        radius: 27,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox.square(
              dimension: 54,
              child: Center(
                child: _SiponBottomIcon(
                  icon: Icons.add_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SiponBottomJumpItem extends StatelessWidget {
  const _SiponBottomJumpItem({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.highlighted,
    required this.inactiveColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final bool highlighted;
  final Color inactiveColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      // Reserve touch-and-hold for dragging the navigation capsule.
      triggerMode: TooltipTriggerMode.manual,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            iconSize: _SiponBottomIcon.size,
            visualDensity: VisualDensity.standard,
            alignment: Alignment.center,
            minimumSize: Size.zero,
            fixedSize: const Size(
              _SiponBottomJumpBar.itemWidth,
              _SiponBottomJumpBar.itemHeight,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: Colors.transparent,
            foregroundColor: highlighted ? scheme.onPrimary : inactiveColor,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                _SiponBottomJumpBar.itemCornerRadius,
              ),
            ),
          ),
          icon: AnimatedScale(
            scale: highlighted ? 1.06 : 1,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: _SiponBottomIcon(icon: icon),
          ),
        ),
      ),
    );
  }
}

class _SiponBottomIcon extends StatelessWidget {
  const _SiponBottomIcon({required this.icon, this.color});

  static const double size = 30;

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    // Center the visual weight of asymmetric glyphs within the shared icon box.
    final offset = switch (icon) {
      Icons.person_rounded => const Offset(0, 1),
      _ => Offset.zero,
    };

    return SizedBox.square(
      dimension: size,
      child: Transform.translate(
        offset: offset,
        child: Icon(icon, color: color, size: size),
      ),
    );
  }
}

class _SiponPlusSheet extends StatelessWidget {
  const _SiponPlusSheet({
    required this.onPlanRoute,
    required this.onCheckIn,
    required this.onAddVenue,
  });

  final VoidCallback onPlanRoute;
  final VoidCallback onCheckIn;
  final VoidCallback onAddVenue;

  static const double _backgroundBlurSigma = 18;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    final glassTint = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.10),
      scheme.surface,
    ).withValues(alpha: 0.76);
    final mediaQuery = MediaQuery.of(context);
    final viewInsets = mediaQuery.viewInsets.bottom;
    final bottomSafeInset = _bottomBarBottomGapFor(
      mediaQuery.viewPadding.bottom,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: ColoredBox(color: scheme.scrim.withValues(alpha: 0.4)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: viewInsets + bottomSafeInset,
            child: Padding(
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: scheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    // Keep the frosted-glass blur constant across theme modes;
                    // theme changes only affect the translucent surface tint.
                    filter: ImageFilter.blur(
                      sigmaX: _backgroundBlurSigma,
                      sigmaY: _backgroundBlurSigma,
                    ),
                    child: ColoredBox(
                      color: glassTint,
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: scheme.shadow.withValues(
                                      alpha: 0.13,
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                text.plusSheetTitle,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                text.plusSheetHint,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 18),
                              _SiponPlusSheetGrid(
                                onPlanRoute: onPlanRoute,
                                onCheckIn: onCheckIn,
                                onAddVenue: onAddVenue,
                              ),
                            ],
                          ),
                        ),
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

class _SiponPlusSheetGrid extends StatefulWidget {
  const _SiponPlusSheetGrid({
    required this.onPlanRoute,
    required this.onCheckIn,
    required this.onAddVenue,
  });

  final VoidCallback onPlanRoute;
  final VoidCallback onCheckIn;
  final VoidCallback onAddVenue;

  @override
  State<_SiponPlusSheetGrid> createState() => _SiponPlusSheetGridState();
}

class _SiponPlusSheetGridState extends State<_SiponPlusSheetGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _animatedCard({required int index, required Widget child}) {
    final start = index * 0.16;
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 0.72 + index * 0.1, curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final progress = animation.value;
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - progress)),
            child: Transform.scale(
              scale: 0.9 + progress * 0.1,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _animatedCard(
                index: 0,
                child: _SiponPlusActionCard(
                  icon: Icons.alt_route_rounded,
                  title: text.plusPlanRoute,
                  accent: Color(0xFF3F7CA8), // 内容固有色：路线动作图标，不随主题变化
                  onTap: widget.onPlanRoute,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _animatedCard(
                index: 1,
                child: _SiponPlusActionCard(
                  icon: Icons.location_on_rounded,
                  title: text.plusCheckInBar,
                  accent: Color(0xFFE08A3C), // 内容固有色：打卡动作图标，不随主题变化
                  onTap: widget.onCheckIn,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _animatedCard(
          index: 2,
          child: _SiponPlusActionCard(
            icon: Icons.add_business_rounded,
            title: text.plusAddVenue,
            accent: Color(0xFF5E9B67), // 内容固有色：新增地点动作图标，不随主题变化
            onTap: widget.onAddVenue,
          ),
        ),
      ],
    );
  }
}

class _SiponPlusActionCard extends StatelessWidget {
  const _SiponPlusActionCard({
    required this.icon,
    required this.title,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 78,
      child: Material(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.of(context).pop();
            Future<void>.delayed(Duration.zero, onTap);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                _PlusIconBubble(icon: icon, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlusIconBubble extends StatelessWidget {
  const _PlusIconBubble({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}
