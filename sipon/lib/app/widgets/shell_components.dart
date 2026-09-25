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
          // 棣栭〉鎼滅储閬僵灞曞紑鏃跺悓姝ラ殣钘忓簳鏍忥細鏃㈤伩鍏嶅簳鏍忔诞鍦ㄦā绯婂眰涔嬩笂锛?
          // 涔熼槻姝㈡悳绱㈡ā寮忎笅璇偣 tab 鍒囬〉鍚庨椤垫畫鐣欐悳绱㈢姸鎬併€?
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
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(34, 0, 34, bottomGap),
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
          );
        },
      ),
    );
  }
}

class _SiponBottomJumpBar extends StatelessWidget {
  const _SiponBottomJumpBar({
    required this.currentIndex,
    required this.onTabSelected,
    required this.onPlusPressed,
  });

  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onPlusPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: colors.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: SizedBox(
                height: 62,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _SiponBottomJumpItem(
                      tooltip: text.homeTab,
                      icon: Icons.home_rounded,
                      selected: currentIndex == 0,
                      activeColor: colors.primary,
                      inactiveColor: colors.onSurfaceVariant,
                      onPressed: () => onTabSelected(0),
                    ),
                    _SiponBottomJumpItem(
                      tooltip: text.mapTab,
                      icon: Icons.map_rounded,
                      selected: currentIndex == 1,
                      activeColor: colors.primary,
                      inactiveColor: colors.onSurfaceVariant,
                      onPressed: () => onTabSelected(1),
                    ),
                    _SiponBottomJumpItem(
                      tooltip: text.profileTab,
                      icon: Icons.person_rounded,
                      selected: currentIndex == 2,
                      activeColor: colors.primary,
                      inactiveColor: colors.onSurfaceVariant,
                      onPressed: () => onTabSelected(2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SiponBottomPlusButton(onPressed: onPlusPressed),
        ],
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
      label: '鏇村鎿嶄綔',
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onPressed,
          radius: 32,
          highlightShape: BoxShape.circle,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              Icons.add_rounded,
              color: scheme.onSurfaceVariant,
              size: 28,
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
    required this.activeColor,
    required this.inactiveColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        label: tooltip,
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            fixedSize: const Size(70, 52),
            backgroundColor: Colors.transparent,
            foregroundColor: selected ? scheme.onPrimary : inactiveColor,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          icon: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 58,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? activeColor : Colors.transparent,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(child: Icon(icon, size: 28)),
          ),
        ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
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
      child: Icon(icon, color: color, size: 22),
    );
  }
}
