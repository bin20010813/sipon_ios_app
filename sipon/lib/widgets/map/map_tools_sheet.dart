import 'package:flutter/material.dart' hide Visibility;

import '../../pages/language_transform.dart';
import '../../services/map/map_display_options.dart';
import 'map_theme.dart';

/// 「筛选」按钮弹出的地图工具面板：底图样式、数据图层、当前数据概览、相机快捷键。
class MapToolsSheet extends StatelessWidget {
  const MapToolsSheet({
    super.key,
    required this.currentStyle,
    required this.currentLayerMode,
    required this.effectiveLayerMode,
    required this.status,
    required this.visibleCount,
    required this.markerCount,
    required this.failureDetail,
    required this.onStyleChanged,
    required this.onLayerModeChanged,
    required this.onResetCamera,
    required this.onFocusDowntown,
  });

  final MapboxStyle currentStyle;

  /// 用户选的模式，驱动上面的三选一。
  final MapLayerMode currentLayerMode;

  /// 叠上当前缩放之后真正画出来的模式，驱动下面的状态徽标。缩到城市视野时它会
  /// 是「热力」，哪怕用户选的是「全部」。
  final MapLayerMode effectiveLayerMode;

  final MapDataStatus status;

  /// 当前筛选下的点位总数（圆点与热力用的就是这一份）。
  final int visibleCount;

  /// 其中画了文字标签的数量（按缩放抽样后的结果）。
  final int markerCount;

  /// 取数失败时的原始错误。只在这个诊断面板里露出，不进主界面。
  final String? failureDetail;

  final ValueChanged<MapboxStyle> onStyleChanged;
  final ValueChanged<MapLayerMode> onLayerModeChanged;
  final VoidCallback onResetCamera;
  final VoidCallback onFocusDowntown;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final detail = failureDetail;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text.t('地图工具'),
            style: const TextStyle(
              color: MapDesign.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _ToolSection(
            title: text.t('地图样式'),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in MapboxStyle.values)
                  _StyleOption(
                    label: text.t(style.label),
                    selected: style == currentStyle,
                    onTap: () => onStyleChanged(style),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ToolSection(
            title: text.t('数据图层'),
            child: SegmentedButton<MapLayerMode>(
              segments: [
                for (final mode in MapLayerMode.values)
                  ButtonSegment<MapLayerMode>(
                    value: mode,
                    icon: Icon(mode.icon),
                    label: Text(text.t(mode.label)),
                  ),
              ],
              selected: {currentLayerMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  onLayerModeChanged(selection.first),
            ),
          ),
          if (effectiveLayerMode != currentLayerMode) ...[
            const SizedBox(height: 8),
            Text(
              text.t('已缩小到城市视野，当前只画热力图'),
              style: const TextStyle(
                color: MapDesign.muted,
                fontSize: 11,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 原来这里是 marker / geojson / heatmap 三个"已加载"勾勾，
          // 但三个状态永远一起变，看不出任何信息。换成真正在变的数字。
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LayerStatusChip(
                label: text.t('点位'),
                value: '$visibleCount',
                active: effectiveLayerMode.showsPoints && visibleCount > 0,
                color: MapDesign.brand,
              ),
              _LayerStatusChip(
                label: text.t('标签'),
                value: '$markerCount',
                active: markerCount > 0,
                color: const Color(0xFF10B981),
              ),
              _LayerStatusChip(
                label: text.t('热力'),
                value: effectiveLayerMode.showsHeatmap
                    ? text.t('开')
                    : text.t('关'),
                active: effectiveLayerMode.showsHeatmap,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            text.t(status.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: status == MapDataStatus.failed
                  ? MapDesign.alert
                  : MapDesign.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MapDesign.muted,
                fontSize: 11,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ToolActionButton(
                  label: text.t('回到总览'),
                  icon: Icons.my_location_outlined,
                  onTap: onResetCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToolActionButton(
                  label: text.t('聚焦城区'),
                  icon: Icons.center_focus_strong_outlined,
                  onTap: onFocusDowntown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _StyleOption extends StatelessWidget {
  const _StyleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: MapDesign.brand,
      labelStyle: TextStyle(
        color: selected ? Colors.white : MapDesign.ink,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(
        color: selected ? MapDesign.brand : const Color(0xFFECE6EA),
      ),
    );
  }
}

class _ToolActionButton extends StatelessWidget {
  const _ToolActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: MapDesign.brandSurface,
        foregroundColor: MapDesign.brand,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _LayerStatusChip extends StatelessWidget {
  const _LayerStatusChip({
    required this.label,
    required this.value,
    required this.active,
    required this.color,
  });

  final String label;
  final String value;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.11) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.26)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? color : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: active ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
