part of '../pages/home_page.dart';

class _HomeTopBar extends StatefulWidget {
  const _HomeTopBar({
    super.key,
    required this.expanded,
    required this.onExpandedChanged,
  });

  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_HomeTopBar> createState() => _HomeTopBarState();
}

class _HomeTopBarState extends State<_HomeTopBar> {
  static const Duration _searchAnimationDuration = Duration(milliseconds: 280);

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SiponApiService _cocktailApi = SiponApiService();
  final List<CocktailInfo> _suggestions = [];
  Timer? _searchDebounce;
  // 展开动画结束后再请求焦点唤起键盘，避免键盘滑入与宽度/遮罩模糊动画
  // 叠加在同一个渲染窗口内导致掉帧。
  Timer? _focusRequestDebounce;
  bool _loadingSuggestions = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _focusRequestDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final keyword = value.trim();
    if (keyword.isEmpty) {
      setState(() {
        _suggestions.clear();
        _loadingSuggestions = false;
      });
      return;
    }

    setState(() => _loadingSuggestions = true);
    _searchDebounce = Timer(const Duration(milliseconds: 260), () async {
      try {
        final data = await _cocktailApi.searchCocktails(
          keyword: keyword,
          page: const SiponPage(limit: 3),
        );
        if (!mounted || _searchController.text.trim() != keyword) return;
        setState(() {
          _suggestions
            ..clear()
            ..addAll(CocktailInfo.listFromJson(data));
          _loadingSuggestions = false;
        });
      } on Exception {
        if (mounted && _searchController.text.trim() == keyword) {
          setState(() => _loadingSuggestions = false);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _HomeTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.expanded && widget.expanded) {
      // 延迟到展开动画（280ms）结束后再弹键盘，错开 raster 压力峰值。
      _focusRequestDebounce?.cancel();
      _focusRequestDebounce = Timer(_searchAnimationDuration, () {
        if (mounted && widget.expanded) _searchFocusNode.requestFocus();
      });
    } else if (oldWidget.expanded && !widget.expanded) {
      _focusRequestDebounce?.cancel();
      _searchFocusNode.unfocus();
    }
  }

  void _openSearch() {
    if (!widget.expanded) {
      widget.onExpandedChanged(true);
      return;
    }
    _submitSearch();
  }

  void _submitSearch() {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) {
      _searchFocusNode.requestFocus();
      return;
    }

    _searchFocusNode.unfocus();
    widget.onExpandedChanged(false);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CocktailListPage(initialKeyword: keyword),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 52,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  duration: _searchAnimationDuration,
                  curve: Curves.easeOutCubic,
                  opacity: widget.expanded ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: widget.expanded,
                    child: Center(
                      child: SvgPicture.asset(
                        HomePage.nameAsset,
                        width: 82,
                        height: 30,
                        // SVG 已改为 fill="currentColor"，此处跟随主题：
                        // 浅色下为深色字、深色下为白色，自动适配深浅色切换。
                        colorFilter: ColorFilter.mode(
                          HomePage.inkOf(context),
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  duration: _searchAnimationDuration,
                  curve: Curves.easeOutCubic,
                  opacity: widget.expanded ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: widget.expanded,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: SiponCityButton(),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Tooltip(
                    message: text.t('搜索'),
                    child: AnimatedContainer(
                      duration: _searchAnimationDuration,
                      curve: Curves.easeOutCubic,
                      width: widget.expanded ? constraints.maxWidth : 44,
                      height: 44,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      // 图标固定贴右缘，输入框占左侧弹性空间随容器展开/收拢；
                      // 不能用条件直接增删输入框（Row 会塌缩，图标瞬间跳位）。
                      child: Row(
                        children: [
                          Expanded(
                            child: widget.expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      // 不用 autofocus：焦点由展开动画结束后的
                                      // 延迟请求统一发起，保证键盘错峰弹出。
                                      textInputAction: TextInputAction.search,
                                      onChanged: _onSearchChanged,
                                      onSubmitted: (_) => _submitSearch(),
                                      style: TextStyle(
                                        color: HomePage.inkOf(context),
                                        fontSize: 14,
                                        letterSpacing: 0,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: text.t('搜索鸡尾酒'),
                                        hintStyle: TextStyle(
                                          color: HomePage.mutedOf(context),
                                          fontSize: 13,
                                          letterSpacing: 0,
                                        ),
                                        // The pill owns the background and
                                        // shape. Do not inherit the global
                                        // filled input background here.
                                        filled: false,
                                        fillColor: Colors.transparent,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        focusedErrorBorder: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                          Tooltip(
                            message: text.t('搜索'),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _openSearch,
                                child: Center(
                                  child: Image.asset(
                                    HomePage.searchAsset,
                                    width: 22,
                                    height: 22,
                                    color: HomePage.mutedOf(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.expanded && (_loadingSuggestions || _suggestions.isNotEmpty))
          _CocktailSuggestions(
            loading: _loadingSuggestions,
            items: _suggestions,
            onSelected: (item) {
              final keyword = item.name ?? item.nameEn ?? '';
              if (keyword.isEmpty) return;
              _searchController.text = keyword;
              _submitSearch();
            },
          ),
      ],
    );
  }
}

class _CocktailSuggestions extends StatelessWidget {
  const _CocktailSuggestions({
    required this.loading,
    required this.items,
    required this.onSelected,
  });

  final bool loading;
  final List<CocktailInfo> items;
  final ValueChanged<CocktailInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: siponColors.shadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: loading
          ? const SizedBox(
              height: 52,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : Column(
              children: [
                for (final item in items)
                  ListTile(
                    dense: true,
                    minVerticalPadding: 0,
                    leading: Icon(
                      Icons.local_bar_outlined,
                      color: scheme.primary,
                      size: 20,
                    ),
                    title: Text(
                      item.name ?? item.nameEn ?? text.t('鸡尾酒'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: HomePage.inkOf(context),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => onSelected(item),
                  ),
              ],
            ),
    );
  }
}

BoxDecoration _homePromptDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final siponColors = context.siponColors;
  return BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: scheme.outlineVariant),
    boxShadow: [
      BoxShadow(
        color: siponColors.shadow,
        blurRadius: 18,
        offset: Offset(0, 8),
      ),
    ],
  );
}

class _VirtualDrinkingPrompt extends StatelessWidget {
  const _VirtualDrinkingPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: _homePromptDecoration(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Icon(
                  Icons.nightlife_rounded,
                  color: scheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.t('虚拟小酌'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: HomePage.inkOf(context),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text.t('选一杯酒，走进属于你的场景'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: HomePage.mutedOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: scheme.primary,
                    size: 17,
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

class _HomeRecordPrompt extends StatelessWidget {
  const _HomeRecordPrompt({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: _homePromptDecoration(context),
      child: Row(
        children: [
          Icon(Icons.auto_graph_rounded, color: scheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.t('看见你的饮酒习惯'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: HomePage.inkOf(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text.t('少一点模糊印象，多一点清楚记录'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: HomePage.mutedOf(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(82, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(text.t('记一笔')),
          ),
        ],
      ),
    );
  }
}
