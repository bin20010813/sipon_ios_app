import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_display_options.dart';
import 'map_models.dart';
import 'map_viewport.dart';

/// 一帧要画到地图上的全部内容。
///
/// 页面每次 `setState` 后把它整体交给 [MapSceneController]，控制器自己比对
/// 哪些部分真的变了。这样「什么时候下发」只有一个入口。
class MapSceneFrame {
  const MapSceneFrame({
    required this.circlePoints,
    required this.heatmapPoints,
    required this.markers,
    required this.layerMode,
    this.selected,
  });

  final List<MapPoint> circlePoints;
  final List<MapPoint> heatmapPoints;
  final List<MapMarkerSpec> markers;
  final MapLayerMode layerMode;

  /// 当前选中的那个点，用来画高亮光环。没有选中就是 null。
  final MapPoint? selected;

  /// 整帧指纹。相同就说明这一帧跟上一帧画出来一模一样，可以整段跳过。
  String get signature => [
    layerMode.name,
    selected?.id ?? '',
    circlePoints.map((point) => point.id).join(','),
    heatmapPoints.map((point) => point.id).join(','),
    markerAnnotationSignature(markers),
  ].join('#');
}

/// 地图侧的唯一负责人：样式、source、图层、annotation、相机、装饰物。
///
/// 它是整个地图页里**唯一**持有 [MapboxMap] 的地方。页面不再直接碰 Mapbox，
/// 于是「相机为什么动了」永远只有这个文件里的几个方法可查。
///
/// 三个回调把地图事件翻译成业务意图交回页面：
/// - [onViewportSettled]：相机停稳（已去抖）后的视野，页面拿去决定要不要取数；
/// - [onVenueTapped]：点中了某个点位；
/// - [onBlankTapped]：点在空白处。原来点空白毫无反应，现在用来收起面板。
class MapSceneController {
  MapSceneController({
    required this.onViewportSettled,
    required this.onVenueTapped,
    required this.onBlankTapped,
  });

  final void Function(MapViewport viewport) onViewportSettled;
  final void Function(String venueId) onVenueTapped;
  final VoidCallback onBlankTapped;

  static const String circleSourceId = 'sipon_geojson_points_source';
  static const String heatmapSourceId = 'sipon_heatmap_points_source';
  static const String selectionSourceId = 'sipon_selected_point_source';
  static const String circleLayerId = 'sipon_geojson_points_circle';
  static const String heatmapLayerId = 'sipon_points_heatmap';
  static const String selectionHaloLayerId = 'sipon_selected_point_halo';
  static const String selectionCoreLayerId = 'sipon_selected_point_core';
  static const String markerManagerId = 'sipon_marker_annotations';
  static const String tapInteractionId = 'sipon_map_tap';

  /// 相机停下后再等这么久才回调。一次 `flyTo` 会连着抛好几个 idle，
  /// 去抖之后只剩最后一个。
  static const Duration idleDebounce = Duration(milliseconds: 220);

  /// 与面板动画同时长，两条动画节奏一致。
  static const Duration focusDuration = Duration(milliseconds: 420);
  static const double defaultZoom = 15.05;
  static const double cityZoom = 11.8;
  static const double focusZoom = 15.4;
  static const double defaultPitch = 24;
  static const double defaultBearing = -12;
  static const double focusPitch = 30;
  static const double focusBearing = -18;

  /// 命中测试的容差（逻辑像素）。圆点半径只有 4~11px，手指比它大得多，
  /// 按点查询几乎点不中，所以按方框查。
  static const double tapSlop = 18;

  /// 圆点完全显现时的透明度。
  static const double _circleOpaque = 0.92;

  MapboxMap? _map;
  PointAnnotationManager? _markerManager;
  Cancelable? _markerTapCancelable;
  Timer? _idleDebounceTimer;

  String? _markerSignature;
  String? _selectionSignature;
  String? _circleSignature;
  String? _heatmapSignature;
  MapLayerMode? _appliedLayerMode;

  /// 整帧指纹。页面每次 `setState` 都会重新下发一帧，但绝大多数 `setState`
  /// （面板形变、语言切换以外的重建）跟地图内容无关。先比整帧指纹能省掉
  /// 后面 5 次 `styleLayerExists` 平台往返。
  String? _frameSignature;

  /// 相机 padding 的下边距。每次相机调用都显式带上它——不带的话 Mapbox 会
  /// 沿用上一次的值，原来聚焦过详情之后 padding 就一直粘着不还。
  double _cameraBottomPadding = 0;
  double _ornamentBottomMargin = 184;

  bool get isAttached => _map != null;

  Future<void> attach(MapboxMap map, {required String city}) async {
    _map = map;
    _resetStyleCaches();

    // 初始相机跟原来的 `_configureMap` 一致：先给城市级视野，让用户一眼看到
    // 整片城区，再由自己的手势或「回到总览」拉近。
    await map.setCamera(cameraForCity(city, zoom: cityZoom));
    await map.compass.updateSettings(
      CompassSettings(
        enabled: false,
        position: OrnamentPosition.TOP_RIGHT,
        marginTop: 20,
        marginRight: 16,
      ),
    );
    await map.scaleBar.updateSettings(
      ScaleBarSettings(enabled: false, position: OrnamentPosition.BOTTOM_LEFT),
    );
    await map.gestures.updateSettings(
      GesturesSettings(
        rotateEnabled: true,
        pinchToZoomEnabled: true,
        scrollEnabled: true,
      ),
    );
    await _pushOrnaments();

    map.addInteraction(
      TapInteraction.onMap(_handleMapTap),
      interactionID: tapInteractionId,
    );
  }

  void detach() {
    _idleDebounceTimer?.cancel();
    _idleDebounceTimer = null;
    _markerTapCancelable?.cancel();
    _markerTapCancelable = null;
    _markerManager = null;
    _map = null;
  }

  /// 样式重新加载后 source / layer / annotation 全被清空了，缓存的指纹也得作废，
  /// 否则下一帧会以为「没变化」而什么都不画。
  void handleStyleLoaded() => _resetStyleCaches();

  void _resetStyleCaches() {
    _markerSignature = null;
    _selectionSignature = null;
    _circleSignature = null;
    _heatmapSignature = null;
    _appliedLayerMode = null;
    _frameSignature = null;
  }

  Future<void> setStyle(MapboxStyle style) async {
    final map = _map;
    if (map == null) {
      return;
    }

    final manager = _markerManager;
    _markerTapCancelable?.cancel();
    _markerTapCancelable = null;
    _markerManager = null;
    if (manager != null) {
      // 只丢 Dart 引用不够，原生侧同 id 的 manager 还在，重建会撞车。
      await map.annotations.removeAnnotationManager(manager);
    }

    _resetStyleCaches();
    await map.style.setStyleURI(style.uri);
  }

  // ---------------------------------------------------------------- 视野与相机

  /// 读当前相机看到的范围。相机还没就绪时 Mapbox 会给无穷大，退回整个中国。
  Future<MapViewport?> readViewport() async {
    final map = _map;
    if (map == null) {
      return null;
    }

    try {
      final camera = await map.getCameraState();
      final bounds = await map.coordinateBoundsForCamera(
        camera.toCameraOptions(),
      );

      return MapViewport(
        bounds: bounds.infiniteBounds
            ? const MapBoundsBox.china()
            : MapBoundsBox(
                west: bounds.southwest.coordinates.lng.toDouble(),
                south: bounds.southwest.coordinates.lat.toDouble(),
                east: bounds.northeast.coordinates.lng.toDouble(),
                north: bounds.northeast.coordinates.lat.toDouble(),
              ),
        zoom: camera.zoom,
      );
    } catch (_) {
      return null;
    }
  }

  /// 接 `MapWidget.onMapIdleListener`。去抖后读一次视野回调给页面。
  void handleMapIdle() {
    _idleDebounceTimer?.cancel();
    _idleDebounceTimer = Timer(idleDebounce, () async {
      final viewport = await readViewport();
      if (viewport != null && _map != null) {
        onViewportSettled(viewport);
      }
    });
  }

  CameraOptions cameraForCity(String city, {required double zoom}) {
    final center = mapCenterForCity(city);

    return CameraOptions(
      center: _point(center.longitude, center.latitude),
      zoom: zoom,
      pitch: defaultPitch,
      bearing: defaultBearing,
      padding: _padding,
    );
  }

  MbxEdgeInsets get _padding =>
      MbxEdgeInsets(top: 0, left: 0, bottom: _cameraBottomPadding, right: 0);

  /// 面板落定后调一次：相机取景、相机 padding、地图装饰物一次对齐。
  ///
  /// **相机意图的唯一出口。** 原来 `_expandVenueDetails` / `_collapseVenueDetails`
  /// / `_settleVenueSheet` / `_showSelectedVenueOnMap` 各自调一遍 `_focusVenue`，
  /// 参数还微妙不同；184 / 250 / `extent * h + 8` 三个装饰物魔数也分散在
  /// `_configureMap` 和 `_updateMapOrnaments` 里各写一遍。现在都收在这里。
  Future<void> applyStage({
    required double cameraBottomPadding,
    required double ornamentBottomMargin,
    MapLatLng? focus,
  }) async {
    final paddingChanged = _cameraBottomPadding != cameraBottomPadding;
    _cameraBottomPadding = cameraBottomPadding;
    _ornamentBottomMargin = ornamentBottomMargin;
    await _pushOrnaments();

    final map = _map;
    if (map == null) {
      return;
    }
    if (focus != null) {
      await focusOn(longitude: focus.longitude, latitude: focus.latitude);
      return;
    }
    if (!paddingChanged) {
      return;
    }

    // 没有要聚焦的目标就只动 padding，中心与缩放交给 Mapbox 自己重新取景。
    await map.easeTo(
      CameraOptions(padding: _padding),
      MapAnimationOptions(duration: focusDuration.inMilliseconds),
    );
  }

  Future<void> _pushOrnaments() async {
    final map = _map;
    if (map == null) {
      return;
    }

    await Future.wait([
      map.logo.updateSettings(
        LogoSettings(
          position: OrnamentPosition.BOTTOM_LEFT,
          marginLeft: 12,
          marginBottom: _ornamentBottomMargin,
        ),
      ),
      map.attribution.updateSettings(
        AttributionSettings(
          position: OrnamentPosition.BOTTOM_RIGHT,
          marginRight: 12,
          marginBottom: _ornamentBottomMargin,
        ),
      ),
    ]);
  }

  /// 把某个坐标居中。相机意图现在只有这一处出口。
  Future<void> focusOn({
    required double longitude,
    required double latitude,
  }) async {
    await _map?.flyTo(
      CameraOptions(
        center: _point(longitude, latitude),
        zoom: focusZoom,
        pitch: focusPitch,
        bearing: focusBearing,
        padding: _padding,
      ),
      MapAnimationOptions(duration: focusDuration.inMilliseconds),
    );
  }

  Future<void> flyToCity(String city, {required double zoom}) async {
    await _map?.flyTo(
      cameraForCity(city, zoom: zoom),
      MapAnimationOptions(duration: 780),
    );
  }

  // -------------------------------------------------------------------- 命中

  void _handleMapTap(MapContentGestureContext context) {
    unawaited(_resolveTap(context.touchPosition));
  }

  Future<void> _resolveTap(ScreenCoordinate touch) async {
    final map = _map;
    if (map == null) {
      return;
    }

    List<QueriedRenderedFeature?> hits;
    try {
      hits = await map.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(x: touch.x - tapSlop, y: touch.y - tapSlop),
            max: ScreenCoordinate(x: touch.x + tapSlop, y: touch.y + tapSlop),
          ),
        ),
        // 选中高亮也算命中目标：热力图层级下圆点整层摘掉了，此时它是地图上
        // 唯一还能点的点。
        RenderedQueryOptions(layerIds: [circleLayerId, selectionCoreLayerId]),
      );
    } catch (_) {
      return;
    }

    if (_map == null) {
      return;
    }

    final venueId = _venueIdFromHits(hits);
    if (venueId != null) {
      onVenueTapped(venueId);
    } else {
      onBlankTapped();
    }
  }

  String? _venueIdFromHits(List<QueriedRenderedFeature?> hits) {
    for (final hit in hits) {
      final properties = hit?.queriedFeature.feature['properties'];
      if (properties is! Map) {
        continue;
      }
      final venueId = properties['venueId'];
      if (venueId is String && venueId.isNotEmpty) {
        return venueId;
      }
    }

    return null;
  }

  // -------------------------------------------------------------------- 渲染

  /// 把一帧内容下发到地图。整帧没变就直接返回；变了再逐部分比指纹，
  /// 只碰真的需要改的那几个 source / layer。
  Future<void> render(MapSceneFrame frame) async {
    final map = _map;
    if (map == null) {
      return;
    }

    final signature = frame.signature;
    if (signature == _frameSignature) {
      return;
    }
    _frameSignature = signature;

    await _renderCircles(map, frame.circlePoints);
    await _renderHeatmap(map, frame.heatmapPoints);
    await _renderSelection(map, frame.selected);
    await _renderMarkers(map, frame.markers);
    await _applyLayerMode(map, frame.layerMode);
  }

  Future<void> _renderCircles(MapboxMap map, List<MapPoint> points) async {
    final signature = _pointsSignature(points);
    if (signature != _circleSignature) {
      await _upsertSource(map, sourceId: circleSourceId, points: points);
      _circleSignature = signature;
    }
    if (await map.style.styleLayerExists(circleLayerId)) {
      return;
    }

    await map.style.addLayer(
      CircleLayer(
        id: circleLayerId,
        sourceId: circleSourceId,
        slot: LayerSlot.TOP,
        // 热力图层级以下整层摘掉，见 _applyZoomHandoff。
        minZoom: mapHeatmapHandoffZoom,
        circleColorExpression: _circleColorExpression,
        circleRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          4,
          13,
          7,
          16,
          11,
        ],
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 1.5,
        circleOpacityExpression: _fadeInExpression(_circleOpaque),
        circleStrokeOpacityExpression: _fadeInExpression(1),
        circleEmissiveStrength: 0.4,
      ),
    );
  }

  /// 按 `category` 属性给圆点上色，颜色取自 [MapVenueKind]，
  /// 新增一种类型不用再回来改表达式。
  List<Object> get _circleColorExpression => [
    'match',
    ['get', 'category'],
    for (final kind in MapVenueKind.values) ...[
      kind.id,
      ['rgba', kind.circleRed, kind.circleGreen, kind.circleBlue, 0.9],
    ],
    ['rgba', 71, 85, 105, 0.88],
  ];

  Future<void> _renderHeatmap(MapboxMap map, List<MapPoint> points) async {
    final signature = _pointsSignature(points);
    if (signature != _heatmapSignature) {
      await _upsertSource(map, sourceId: heatmapSourceId, points: points);
      _heatmapSignature = signature;
    }
    if (await map.style.styleLayerExists(heatmapLayerId)) {
      return;
    }

    await map.style.addLayer(
      HeatmapLayer(
        id: heatmapLayerId,
        sourceId: heatmapSourceId,
        slot: LayerSlot.MIDDLE,
        maxZoom: 16,
        heatmapWeightExpression: [
          'interpolate',
          ['linear'],
          ['get', 'weight'],
          0,
          0,
          8,
          1,
        ],
        heatmapIntensityExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          0.7,
          14,
          1.6,
        ],
        heatmapRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          16,
          14,
          34,
          16,
          46,
        ],
        heatmapOpacityExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          10,
          0.88,
          15,
          0.45,
        ],
        heatmapColorExpression: const [
          'interpolate',
          ['linear'],
          ['heatmap-density'],
          0,
          'rgba(33,102,172,0)',
          0.2,
          'rgb(103,169,207)',
          0.4,
          'rgb(209,229,240)',
          0.6,
          'rgb(253,219,199)',
          0.8,
          'rgb(239,138,98)',
          1,
          'rgb(178,24,43)',
        ],
      ),
    );
  }

  /// 选中高亮：一圈半透明光环 + 一个描白边的实心点。原来完全没有这个反馈，
  /// 点了某家酒吧只有卡片变，地图上看不出选了哪个。
  Future<void> _renderSelection(MapboxMap map, MapPoint? selected) async {
    final points = selected == null ? const <MapPoint>[] : [selected];
    final signature = _pointsSignature(points);
    if (signature != _selectionSignature) {
      await _upsertSource(map, sourceId: selectionSourceId, points: points);
      _selectionSignature = signature;
    }
    if (await map.style.styleLayerExists(selectionCoreLayerId)) {
      return;
    }

    await map.style.addLayer(
      CircleLayer(
        id: selectionHaloLayerId,
        sourceId: selectionSourceId,
        slot: LayerSlot.TOP,
        circleColorExpression: _circleColorExpression,
        circleRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          8,
          13,
          10,
          16,
          15,
        ],
        circleOpacity: 0.22,
        circleBlur: 0.35,
        circleEmissiveStrength: 1,
      ),
    );
    await map.style.addLayer(
      CircleLayer(
        id: selectionCoreLayerId,
        sourceId: selectionSourceId,
        slot: LayerSlot.TOP,
        circleColorExpression: _circleColorExpression,
        circleRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          4.5,
          13,
          6.5,
          16,
          9.5,
        ],
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
        circleOpacity: 1,
        circleEmissiveStrength: 1,
      ),
    );
  }

  Future<void> _renderMarkers(
    MapboxMap map,
    List<MapMarkerSpec> markers,
  ) async {
    final signature = markerAnnotationSignature(markers);
    final manager = await _ensureMarkerManager(map);
    if (manager == null || signature == _markerSignature) {
      return;
    }

    await manager.deleteAll();
    await manager.createMulti([
      for (final marker in markers)
        PointAnnotationOptions(
          geometry: _point(marker.longitude, marker.latitude),
          iconImage: 'marker-15',
          iconSize: 1.35,
          iconAnchor: IconAnchor.BOTTOM,
          textField: marker.label,
          textSize: 12,
          textOffset: const [0, 1.15],
          textAnchor: TextAnchor.TOP,
          textColor: const Color(0xFF0F172A).toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 1.5,
          customData: {'venueId': marker.venueId},
        ),
    ]);
    _markerSignature = signature;
  }

  Future<PointAnnotationManager?> _ensureMarkerManager(MapboxMap map) async {
    final existing = _markerManager;
    if (existing != null) {
      return existing;
    }

    final manager = await map.annotations.createPointAnnotationManager(
      id: markerManagerId,
    );
    if (_map == null) {
      return null;
    }

    _markerManager = manager;
    await manager.setIconAllowOverlap(true);
    await manager.setTextAllowOverlap(false);

    _markerTapCancelable?.cancel();
    _markerTapCancelable = manager.tapEvents(
      onTap: (annotation) {
        final venueId = annotation.customData?['venueId'];
        if (venueId is String && venueId.isNotEmpty) {
          onVenueTapped(venueId);
        }
      },
    );

    return manager;
  }

  Future<void> _applyLayerMode(MapboxMap map, MapLayerMode mode) async {
    if (mode == _appliedLayerMode) {
      return;
    }

    _appliedLayerMode = mode;
    await _applyZoomHandoff(map, armed: mode.showsHeatmap);
    await _setLayerVisible(map, circleLayerId, mode.showsPoints);
    await _setLayerVisible(map, heatmapLayerId, mode.showsHeatmap);
    // 选中高亮不跟模式走：它是「详情卡片说的是哪一家」的唯一锚点，热力图层级
    // 只剩它一个点，不构成干扰。
  }

  /// 缩放交接：圆点与文字标注在 [mapHeatmapHandoffZoom] 以下退场，画面让给热力图。
  ///
  /// 圆点用 zoom 表达式淡出（GPU 逐帧插值，捏合过程中就是连续的），再叠一层
  /// `minzoom` 彻底摘掉——只淡出不摘的话，透明度为 0 的圆点照样会被
  /// [queryRenderedFeatures] 命中，在热力图上点一下就选中了一家看不见的酒吧。
  ///
  /// [armed] 为 false（手动选了「点位」）时把两者都还原：没有热力图接手，
  /// 缩小了也得留着点。
  Future<void> _applyZoomHandoff(MapboxMap map, {required bool armed}) async {
    await _setLayerProperty(
      map,
      circleLayerId,
      'minzoom',
      armed ? mapHeatmapHandoffZoom : 0.0,
    );
    await _setLayerProperty(
      map,
      circleLayerId,
      'circle-opacity',
      armed ? _fadeInExpression(_circleOpaque) : _circleOpaque,
    );
    await _setLayerProperty(
      map,
      circleLayerId,
      'circle-stroke-opacity',
      armed ? _fadeInExpression(1) : 1.0,
    );

    // 文字标注是 PointAnnotation，管理器没有按缩放隐藏的接口，但它背后就是一个
    // 普通图层，图层 id 即管理器的 id。真正的保证在 Dart 侧（越过分界线就不生成
    // 标注），这里只是让捏合过程中立刻消失，而不是等相机停稳才消失。
    final markerLayerId = _markerManager?.id;
    if (markerLayerId != null) {
      await _setLayerProperty(
        map,
        markerLayerId,
        'minzoom',
        armed ? mapHeatmapHandoffZoom : 0.0,
      );
    }
  }

  /// 圆点在 [mapHeatmapHandoffZoom] → [mapPointsRestoredZoom] 之间淡入。
  List<Object> _fadeInExpression(double opaque) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    mapHeatmapHandoffZoom,
    0,
    mapPointsRestoredZoom,
    opaque,
  ];

  Future<void> _setLayerVisible(MapboxMap map, String layerId, bool visible) =>
      _setLayerProperty(
        map,
        layerId,
        'visibility',
        visible ? 'visible' : 'none',
      );

  Future<void> _setLayerProperty(
    MapboxMap map,
    String layerId,
    String property,
    Object value,
  ) async {
    if (!await map.style.styleLayerExists(layerId)) {
      return;
    }

    await map.style.setStyleLayerProperty(layerId, property, value);
  }

  Future<void> _upsertSource(
    MapboxMap map, {
    required String sourceId,
    required List<MapPoint> points,
  }) async {
    final data = jsonEncode({
      'type': 'FeatureCollection',
      'features': [for (final point in points) point.toFeature()],
    });

    if (await map.style.styleSourceExists(sourceId)) {
      await map.style.setStyleSourceProperty(sourceId, 'data', data);
      return;
    }

    await map.style.addSource(
      GeoJsonSource(id: sourceId, data: data, generateId: true),
    );
  }

  String _pointsSignature(List<MapPoint> points) =>
      points.map((point) => point.id).join(',');
}

Point _point(double longitude, double latitude) =>
    Point(coordinates: Position(longitude, latitude));
