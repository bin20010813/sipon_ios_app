import 'package:flutter/material.dart' hide Visibility;

import '../../pages/language_transform.dart';
import '../../services/map/map_display_options.dart';
import '../../services/map/map_models.dart';
import '../sipon_city_picker.dart';
import 'map_theme.dart';

/// 顶部一组悬浮控件：城市按钮 + 搜索框 + 分类筛选 + 状态提示条。
class MapSearchAndFilters extends StatelessWidget {
  const MapSearchAndFilters({
    super.key,
    required this.selectedKind,
    required this.status,
    required this.onCategoryToggled,
    required this.onFilterPressed,
  });

  /// 当前分类筛选。null 表示不筛选（顶部没有「全部」pill，
  /// 取消筛选的方式是再点一次已选中的那个）。
  final MapVenueKind? selectedKind;
  final MapDataStatus status;
  final ValueChanged<MapVenueKind> onCategoryToggled;
  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 10, 26, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const SiponCityButton(
                  backgroundColor: Color(0xF7FFFFFF),
                  foregroundColor: MapDesign.ink,
                ),
                const SizedBox(width: 10),
                Expanded(child: _MapSearchField(hint: text.t('搜索喜欢的酒或者酒吧...'))),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  for (final category in mapCategoryFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: MapCategoryPill(
                        category: category,
                        selected: category.kind == selectedKind,
                        onTap: () => onCategoryToggled(category.kind),
                      ),
                    ),
                  _FilterIconPill(onPressed: onFilterPressed),
                ],
              ),
            ),
            if (status.needsBanner) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: _MapStatusBanner(status: status),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapSearchField extends StatelessWidget {
  const _MapSearchField({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.98),
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x559A3D78), width: 1.1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F9A3D78),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
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
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFA198A0),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
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
  const _FilterIconPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 42,
          height: 36,
          child: Center(
            child: Image.asset(
              MapAssets.filter,
              width: 20,
              height: 20,
              color: MapDesign.ink,
            ),
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
