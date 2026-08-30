import 'package:flutter/material.dart';

/// 可切换的底图样式。MapKit 当前提供 3 个档位：
/// - `standard` 同时承接原来的 light 与 streets；
/// - `muted` 用 muted emphasis + 强制深色界面近似原来的 dark；
/// - `satellite` 用带路名的混合影像，对应原 SATELLITE_STREETS 的观感。
///
/// 这一文件刻意不依赖任何地图引擎包：[MapBaseStyle.id] 是 MethodChannel 的
/// 协议值（见 `SiponMapChannel`），由原生侧翻译成底图配置。
enum MapBaseStyle {
  standard('标准'),
  muted('暗色'),
  satellite('卫星');

  const MapBaseStyle(this.label);

  final String label;

  /// MethodChannel 协议里用的 key，同时也是名字稳定的外部引用。
  String get id => name;

  static MapBaseStyle fromId(String? id) => MapBaseStyle.values.firstWhere(
    (style) => style.id == id,
    orElse: () => MapBaseStyle.standard,
  );
}

/// 数据图层的显示组合。
enum MapLayerMode {
  pointsAndHeatmap('全部', Icons.layers_outlined),
  pointsOnly('点位', Icons.scatter_plot_outlined),
  heatmapOnly('热力', Icons.local_fire_department_outlined);

  const MapLayerMode(this.label, this.icon);

  final String label;
  final IconData icon;

  bool get showsPoints => this != MapLayerMode.heatmapOnly;
  bool get showsHeatmap => this != MapLayerMode.pointsOnly;
}

/// 缩放小于这个层级就把画面交给热力图：圆点与文字标注全部退场。
///
/// 取 12 是因为它略高于 `MapSceneController.cityZoom`（11.8）——「聚焦城区」之后
/// 看到的就是一整张热力图，往里推到街区尺度点位才登场。
const double mapHeatmapHandoffZoom = 12;

/// 圆点恢复到完全不透明的层级。与 [mapHeatmapHandoffZoom] 之间是淡入淡出区间，
/// Dart 侧算好透明度下发，原生按最新缩放执行。
const double mapPointsRestoredZoom = 13.2;

/// 圆点完全显现时的不透明度。
const double mapCircleFullOpacity = 0.92;

/// 在淡入淡出区间内按缩放线性插值出圆点的当前透明度；区间外截断到两端。
double mapCircleFadeForZoom(double zoom) {
  if (!zoom.isFinite || zoom <= mapHeatmapHandoffZoom) {
    return 0;
  }
  if (zoom >= mapPointsRestoredZoom) {
    return mapCircleFullOpacity;
  }

  final t =
      (zoom - mapHeatmapHandoffZoom) /
      (mapPointsRestoredZoom - mapHeatmapHandoffZoom);
  return t * mapCircleFullOpacity;
}

/// 手动选的图层模式叠上当前缩放，得到真正画出来的模式。
///
/// 抽成顶层纯函数是为了能直接测：这条规则决定地图在哪个层级换脸。
MapLayerMode mapEffectiveLayerMode(MapLayerMode selected, double zoom) {
  if (!selected.showsHeatmap) {
    // 显式选了「点位」：没有热力图能接手，缩小了也得把点留着，
    // 否则只剩一张空地图。
    return selected;
  }
  if (zoom.isFinite && zoom < mapHeatmapHandoffZoom) {
    return MapLayerMode.heatmapOnly;
  }

  return selected;
}

/// 地图数据的加载态。
///
/// 原来有 `_markersLoaded` / `_geoJsonLoaded` / `_heatmapLoaded` 三个 bool，
/// 但它们永远同时置位，等价于一个状态；合并成这个枚举。
enum MapDataStatus {
  idle('等待地图'),
  loading('正在加载地图数据'),
  ready('地图数据已加载'),
  empty('当前视野暂无可展示酒吧'),
  failed('地图数据加载失败');

  const MapDataStatus(this.label);

  final String label;

  bool get isBusy => this == MapDataStatus.loading;

  /// 只有这两种态需要在顶部提示条上说一句。
  bool get needsBanner =>
      this == MapDataStatus.loading ||
      this == MapDataStatus.empty ||
      this == MapDataStatus.failed;
}
