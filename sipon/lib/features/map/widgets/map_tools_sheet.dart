import 'package:flutter/material.dart';

import '../../../app/theme/sipon_theme_colors.dart';
import '../../../shared/localization/language_transform.dart';
import '../models/map_models.dart';

/// 地图工具栏打开的 POI 组合筛选面板。
///
/// 分类仍由地图顶部的分类 pill 控制；这里的人均上限与最低评分会与分类按
/// AND 关系同时生效。
class MapPoiFilterSheet extends StatefulWidget {
  const MapPoiFilterSheet({
    super.key,
    required this.initialFilter,
    required this.onApply,
  });

  final MapPoiFilter initialFilter;
  final ValueChanged<MapPoiFilter> onApply;

  @override
  State<MapPoiFilterSheet> createState() => _MapPoiFilterSheetState();
}

class _MapPoiFilterSheetState extends State<MapPoiFilterSheet> {
  static const List<double> _priceOptions = [20, 50, 100, 200];
  static const List<double> _ratingOptions = [4, 4.5, 4.8];

  double? _maxAveragePrice;
  double? _minimumRating;

  @override
  void initState() {
    super.initState();
    _maxAveragePrice = widget.initialFilter.maxAveragePrice;
    _minimumRating = widget.initialFilter.minimumRating;
  }

  void _reset() {
    setState(() {
      _maxAveragePrice = null;
      _minimumRating = null;
    });
  }

  void _apply() {
    widget.onApply(
      MapPoiFilter(
        maxAveragePrice: _maxAveragePrice,
        minimumRating: _minimumRating,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text.t('筛选'),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              TextButton(onPressed: _reset, child: Text(text.t('重置'))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text.t('可与酒吧类型同时筛选'),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          _FilterSection(
            title: text.t('人均价格'),
            children: [
              _FilterChoice(
                label: text.t('不限'),
                selected: _maxAveragePrice == null,
                onTap: () => setState(() => _maxAveragePrice = null),
              ),
              for (final value in _priceOptions)
                _FilterChoice(
                  label: '¥${value.toStringAsFixed(0)} ${text.t('以下')}',
                  selected: _maxAveragePrice == value,
                  onTap: () => setState(() => _maxAveragePrice = value),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _FilterSection(
            title: text.t('最低评分'),
            children: [
              _FilterChoice(
                label: text.t('不限'),
                selected: _minimumRating == null,
                onTap: () => setState(() => _minimumRating = null),
              ),
              for (final value in _ratingOptions)
                _FilterChoice(
                  label: '${value.toStringAsFixed(1)} ${text.t('以上')}',
                  selected: _minimumRating == value,
                  onTap: () => setState(() => _minimumRating = value),
                ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _apply,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              child: Text(text.t('应用筛选')),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: scheme.primary,
      backgroundColor: siponColors.subtleSurface,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimary : scheme.onSurface,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    );
  }
}
