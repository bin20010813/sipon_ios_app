import 'package:flutter/material.dart' hide Visibility;

import '../../../shared/localization/language_transform.dart';
import '../models/map_display_options.dart';
import '../models/map_models.dart';
import '../../../shared/widgets/sipon_city_picker.dart';
import 'map_theme.dart';

/// 顶部一组悬浮控件：城市按钮 + 搜索框 + 分类筛选 + 状态提示条。
class MapSearchAndFilters extends StatelessWidget {
  const MapSearchAndFilters({
    super.key,
    required this.selectedKind,
    required this.poiFilter,
    required this.status,
    required this.onCategoryToggled,
    required this.onFilterPressed,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.suggestions,
    required this.onVenueSelected,
  });

  /// 当前分类筛选。null 表示不筛选（顶部没有「全部」pill，
  /// 取消筛选的方式是再点一次已选中的那个）。
  final MapVenueKind? selectedKind;
  final MapPoiFilter poiFilter;
  final MapDataStatus status;
  final ValueChanged<MapVenueKind> onCategoryToggled;
  final VoidCallback onFilterPressed;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  /// 当前搜索词下的候选酒吧（视野内过滤 + 远端搜索合并后的结果），
  /// 供搜索框下拉展示。实现方式与规划路线页的内联搜索一致。
  final List<MapVenue> suggestions;
  final ValueChanged<MapVenue> onVenueSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final filterPills = <Widget>[
      for (final category in mapCategoryFilters)
        MapCategoryPill(
          category: category,
          selected: category.kind == selectedKind,
          onTap: () => onCategoryToggled(category.kind),
        ),
      _FilterIconPill(filter: poiFilter, onPressed: onFilterPressed),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Row(
                children: [
                  const SiponCityButton(
                    backgroundColor: Color(0xF7FFFFFF),
                    foregroundColor: MapDesign.ink,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MapSearchField(
                      hint: text.t('搜索喜欢的酒或者酒吧...'),
                      initialValue: searchQuery,
                      onChanged: onSearchChanged,
                      suggestions: suggestions,
                      onVenueSelected: onVenueSelected,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: Padding(
                padding: EdgeInsets.zero,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (
                        var index = 0;
                        index < filterPills.length;
                        index++
                      ) ...[
                        if (index > 0) const SizedBox(width: 8),
                        filterPills[index],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (status.needsBanner) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _MapStatusBanner(status: status),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapSearchField extends StatefulWidget {
  const _MapSearchField({
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    required this.suggestions,
    required this.onVenueSelected,
  });

  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;

  /// 当前搜索词下命中的候选（已由数据层排好序），下拉最多展示
  /// [_maxSuggestions] 条。
  final List<MapVenue> suggestions;
  final ValueChanged<MapVenue> onVenueSelected;

  @override
  State<_MapSearchField> createState() => _MapSearchFieldState();
}

/// 与规划路线页 `_InlineBarSearchField` 同一套实现：聚焦输入时用
/// Overlay + CompositedTransformFollower 挂一条候选列表，点击候选选中。
class _MapSearchFieldState extends State<_MapSearchField> {
  static const int _maxSuggestions = 6;

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  final _focusNode = FocusNode();
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _resultsOverlay;
  double _fieldWidth = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _MapSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
    // 远端搜索结果是异步合并进来的，候选到达后要刷新挂着的下拉。
    _syncResultsOverlay();
  }

  void _handleFocusChanged() {
    if (!mounted) return;
    setState(() {});
    _syncResultsOverlay();
  }

  void _syncResultsOverlay() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = _fieldKey.currentContext?.findRenderObject();
      if (renderObject is RenderBox) {
        _fieldWidth = renderObject.size.width;
      }
      final shouldShow =
          _focusNode.hasFocus &&
          _controller.text.trim().isNotEmpty &&
          widget.suggestions.isNotEmpty;
      if (shouldShow) {
        if (_resultsOverlay == null) {
          _resultsOverlay = OverlayEntry(builder: (_) => _buildResults());
          Overlay.of(context, rootOverlay: true).insert(_resultsOverlay!);
        } else {
          _resultsOverlay!.markNeedsBuild();
        }
      } else {
        _resultsOverlay?.remove();
        _resultsOverlay = null;
      }
    });
  }

  Widget _buildResults() {
    final results = widget.suggestions.take(_maxSuggestions).toList();
    final panelHeight = (results.length * 56.0).clamp(0.0, 336.0).toDouble();
    return Positioned(
      width: _fieldWidth,
      height: panelHeight,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 52),
        child: Material(
          elevation: 6,
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE6E3E5)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: 56,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final venue = results[index];
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Image.asset(
                    venue.iconAsset,
                    width: 18,
                    height: 18,
                    color: MapDesign.brand,
                  ),
                  title: Text(
                    venue.name,
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${venue.address}  |  ${venue.distance}',
                    style: const TextStyle(
                      color: MapDesign.muted,
                      fontSize: 11,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    _controller.text = venue.name;
                    _controller.selection = TextSelection.collapsed(
                      offset: _controller.text.length,
                    );
                    _focusNode.unfocus();
                    widget.onVenueSelected(venue);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _resultsOverlay?.remove();
    _controller.dispose();
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            key: _fieldKey,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE6E3E5), width: 1),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF8E7588),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: (value) {
                      widget.onChanged(value);
                      setState(() {});
                      _syncResultsOverlay();
                    },
                    onSubmitted: widget.onChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(
                        color: Color(0xFFA198A0),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      widget.onChanged('');
                      setState(() {});
                      _syncResultsOverlay();
                    },
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF9B939B),
                      size: 18,
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

class MapCategoryPill extends StatelessWidget {
  const MapCategoryPill({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final MapCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Material(
      color: selected ? MapDesign.brand : Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 13, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                category.iconAsset,
                width: 18,
                height: 18,
                color: selected ? Colors.white : MapDesign.brand,
              ),
              const SizedBox(width: 5),
              Text(
                text.t(category.label),
                style: TextStyle(
                  color: selected ? Colors.white : MapDesign.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterIconPill extends StatelessWidget {
  const _FilterIconPill({required this.filter, required this.onPressed});

  final MapPoiFilter filter;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final active = filter.isActive;
    final maxPrice = filter.maxAveragePrice;
    final minimumRating = filter.minimumRating;
    final parts = <String>[
      if (maxPrice != null) '≤¥${maxPrice.toStringAsFixed(0)}',
      if (minimumRating != null) '≥${minimumRating.toStringAsFixed(1)}',
    ];

    return Material(
      color: active ? MapDesign.brand : Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                MapAssets.filter,
                width: 18,
                height: 18,
                color: active ? Colors.white : MapDesign.ink,
              ),
              const SizedBox(width: 5),
              Text(
                active ? parts.join(' · ') : text.t('筛选'),
                style: TextStyle(
                  color: active ? Colors.white : MapDesign.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部状态提示条。
///
/// 只说[MapDataStatus]自带的那句话——异常字符串不再拼进界面。要看细节去
/// 地图工具弹窗。
class _MapStatusBanner extends StatelessWidget {
  const _MapStatusBanner({required this.status});

  final MapDataStatus status;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text.t(status.label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: status == MapDataStatus.failed
                ? MapDesign.alert
                : MapDesign.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class MapLocateButton extends StatelessWidget {
  const MapLocateButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.my_location_rounded,
            color: Color(0xFF737176),
            size: 25,
          ),
        ),
      ),
    );
  }
}
