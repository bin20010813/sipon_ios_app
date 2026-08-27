import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import 'map_display_options.dart';
import 'map_models.dart';
import 'map_scene_controller.dart';
import 'map_viewport.dart';
import 'sipon_map_host.dart';
import 'sipon_map_protocol.dart';

/// 迁移期的回退引擎：原 `MapSceneController` 的完整 Mapbox 实现整体搬到这里，
/// 内容基本未动。验收稳定后（指南 P5）随 `mapbox_maps_flutter` 一起删除。
///
/// [MapboxMapHost] 把引擎实例包成统一的 [SiponMapHost]：
/// - [SiponMapHost.invoke] 不适用（Mapbox 走插件 API，控制器直接持有实例）；
/// - [emitEvent] 负责把插件回调（styleLoaded / idle）送进统一事件入口。
class MapboxMapHost implements SiponMapHost {
  MapboxMapHost(this.nativeMap);

  /// 地图页唯一持有 `MapboxMap` 的地方之一；控制器通过它工作。
  /// （字段名不能叫 `mapbox`，会遮住 import 前缀。）
  final mapbox.MapboxMap nativeMap;

  final SiponEventSink _sink = SiponEventSink();

  void emitEvent(String method, Object? arguments) =>
      _sink.emit(method, arguments);

  @override
  Future<Object?> invoke(String method,
      [Map<String, Object?> args = const {}]) async {
    // Mapbox 引擎的指令不走通用通道；控制器在各自方法里直接调用插件 API。
    // 这里只把少数约定事件转成统一事件流，兜住误用。
    switch (method) {
      case SiponMapEvents.onViewportSettled:
        emitEvent(method, args);
      default:
        break;
    }
    return null;
  }

  @override
  void onNativeCall(void Function(String method, Object? arguments) handler) {
    _sink.attachHandler(handler);
  }
}

/// `MapBaseStyle` 到 Mapbox 样式 URI 的映射。light 与 streets 都并进了
/// standard；muted 用 DARK 近似；satellite 维持带路名的影像街景。
String mapboxStyleUriFor(MapBaseStyle style) {
  switch (style) {
    case MapBaseStyle.muted:
      return mapbox.MapboxStyles.DARK;
    case MapBaseStyle.satellite:
      return mapbox.MapboxStyles.SATELLITE_STREETS;
    case MapBaseStyle.standard:
      return mapbox.MapboxStyles.STANDARD;
  }
}

/// 地图侧的唯一负责人（Mapbox 引擎实现）：样式、source、图层、annotation、
/// 相机、装饰物。
// ignore: comment_references
/// 它是整个地图页里**唯一**持有 [MapboxMapHost.nativeMap] 的地方。
class MapboxSceneController extends MapSceneController {
  MapboxSceneController({
    required super.onViewportSettled,
    required super.onVenueTapped,
    required super.onBlankTapped,
  });

  static const String circleSourceId = 'sipon_geojson_points_source';
  static const String heatmapSourceId = 'sipon_heatmap_points_source';
  static const String selectionSourceId = 'sipon_selected_point_source';
  static const String circleLayerId = 'sipon_geojson_points_circle';
  static const String heatmapLayerId = 'sipon_points_heatmap';
  static const String selectionHaloLayerId = 'sipon_selected_point_halo';
  static const String selectionCoreLayerId = 'sipon_selected_point_core';
  static const String markerManagerId = 'sipon_marker_annotations';
  static const String tapInteractionId = 'sipon_map_tap';

  mapbox.MapboxMap? _map;
  mapbox.PointAnnotationManager? _markerManager;
  mapbox.Cancelable? _markerTapCancelable;
  MapboxMapHost? _host;

  String? _markerSignature;
  String? _selectionSignature;
  String? _circleSignature;
  String? _heatmapSignature;
  MapLayerMode? _appliedLayerMode;

  @override
  bool get isAttached => _map != null;

  @override
  Future<void> attach(
    SiponMapHost host, {
    required String city,
    MapBaseStyle style = MapBaseStyle.standard,
  }) async {
    _host = host as MapboxMapHost;
    host.onNativeCall(handleNativeEvent);
    final map = _host!.nativeMap;
    _map = map;
    resetStyleCaches();

    // 初始相机跟原来的 `_configureMap` 一致：先给城市级视野，让用户一眼看到
    // 整片城区，再由自己的手势或「回到总览」拉近。
    await map.setCamera(cameraForCity(city, zoom: MapSceneController.cityZoom));
    await map.compass.updateSettings(
      mapbox.CompassSettings(
        enabled: false,
        position: mapbox.OrnamentPosition.TOP_RIGHT,
        marginTop: 20,
        marginRight: 16,
      ),
    );
    await map.scaleBar.updateSettings(
      mapbox.ScaleBarSettings(enabled: false, position: mapbox.OrnamentPosition.BOTTOM_LEFT),
    );
    await map.gestures.updateSettings(
      mapbox.GesturesSettings(
        rotateEnabled: true,
        pinchToZoomEnabled: true,
        scrollEnabled: true,
      ),
    );
    await _pushOrnaments();

    map.addInteraction(
      mapbox.TapInteraction.onMap(_handleMapTap),
      interactionID: tapInteractionId,
    );
  }

  @override
  void detach() {
    super.detachCommon();
    _markerTapCancelable?.cancel();
    _markerTapCancelable = null;
    _markerManager = null;
    _host = null;
    _map = null;
  }

  /// 样式重新加载后 source / layer / annotation 全被清空了，缓存的指纹也得作废，
  /// 否则下一帧会以为「没变化」而什么都不画。
  @override
  Future<void> setStyle(MapBaseStyle style) async {
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

    resetAllSignatures();
    frameSignature = null;
    await map.style.setStyleURI(mapboxStyleUriFor(style));
  }

  @override
  void handleNativeEvent(String method, Object? arguments) {
    switch (method) {
      case SiponMapEvents.onStyleLoaded:
        unawaited(handleStyleLoaded());
      case SiponMapEvents.onViewportSettled:
        // Mapbox 的 idle 不带数据，走基类的「去抖 + readViewport」路径。
        handleViewportSettled();
      default:
        break;
    }
  }

  // ---------------------------------------------------------------- 视野与相机

  /// 读当前相机看到的范围。相机还没就绪时 Mapbox 会给无穷大，退回整个中国。
  @override
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

  mapbox.CameraOptions cameraForCity(String city, {required double zoom}) {
    final center = mapCenterForCity(city);

    return mapbox.CameraOptions(
      center: _point(center.longitude, center.latitude),
      zoom: zoom,
      pitch: MapSceneController.defaultPitch,
      bearing: MapSceneController.defaultBearing,
      padding: _padding,
    );
  }

  mapbox.MbxEdgeInsets get _padding =>
      mapbox.MbxEdgeInsets(top: 0, left: 0, bottom: cameraBottomPadding, right: 0);

  @override
  Future<void> easeForPaddingOnly() async {
    final map = _map;
    if (map == null) {
      return;
    }

    // 没有要聚焦的目标就只动 padding，中心与缩放交给 Mapbox 自己重新取景。
    await map.easeTo(
      mapbox.CameraOptions(padding: _padding),
      mapbox.MapAnimationOptions(duration: MapSceneController.focusDuration.inMilliseconds),
    );
  }

  Future<void> _pushOrnaments() async {
    final map = _map;
    if (map == null) {
      return;
    }

    await Future.wait([
      map.logo.updateSettings(
        mapbox.LogoSettings(
          position: mapbox.OrnamentPosition.BOTTOM_LEFT,
          marginLeft: 12,
          marginBottom: ornamentBottomMargin,
        ),
      ),
      map.attribution.updateSettings(
        mapbox.AttributionSettings(
          position: mapbox.OrnamentPosition.BOTTOM_RIGHT,
          marginRight: 12,
          marginBottom: ornamentBottomMargin,
        ),
      ),
    ]);
  }

  @override
  Future<void> focusOn({
    required double longitude,
    required double latitude,
  }) async {
    await _map?.flyTo(
      mapbox.CameraOptions(
        center: _point(longitude, latitude),
        zoom: MapSceneController.focusZoom,
        pitch: MapSceneController.focusPitch,
        bearing: MapSceneController.focusBearing,
        padding: _padding,
      ),
      mapbox.MapAnimationOptions(duration: MapSceneController.focusDuration.inMilliseconds),
    );
  }

  @override
  Future<void> flyToCity(String city, {required double zoom}) async {
    await _map?.flyTo(
      cameraForCity(city, zoom: zoom),
      mapbox.MapAnimationOptions(duration: 780),
    );
  }

  // -------------------------------------------------------------------- 命中

  void _handleMapTap(mapbox.MapContentGestureContext context) {
    unawaited(_resolveTap(context.touchPosition));
  }

  Future<void> _resolveTap(mapbox.ScreenCoordinate touch) async {
    final map = _map;
    if (map == null) {
      return;
    }

    List<mapbox.QueriedRenderedFeature?> hits;
    try {
      hits = await map.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenBox(
          mapbox.ScreenBox(
            min: mapbox.ScreenCoordinate(x: touch.x - MapSceneController.tapSlop, y: touch.y - MapSceneController.tapSlop),
            max: mapbox.ScreenCoordinate(x: touch.x + MapSceneController.tapSlop, y: touch.y + MapSceneController.tapSlop),
          ),
        ),
        // 选中高亮也算命中目标：热力图层级下圆点整层摘掉了，此时它是地图上
        // 唯一还能点的点。
        mapbox.RenderedQueryOptions(layerIds: [circleLayerId, selectionCoreLayerId]),
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

  String? _venueIdFromHits(List<mapbox.QueriedRenderedFeature?> hits) {
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

  /// 帧指纹闸门已在基类 [render] 里过掉，这里只剩逐部分比对与真正的渲染。
  @override
  Future<void> performRender(MapSceneFrame frame) async {
    final map = _map;
    if (map == null) {
      return;
    }

    await _renderCircles(map, frame.circlePoints);
    await _renderHeatmap(map, frame.heatmapPoints);
    await _renderSelection(map, frame.selected);
    await _renderMarkers(map, frame.markers);
    await _applyLayerMode(map, frame.layerMode);
  }

  Future<void> _renderCircles(mapbox.MapboxMap map, List<MapPoint> points) async {
    final signature = _pointsSignature(points);
    if (signature != _circleSignature) {
      await _upsertSource(map, sourceId: circleSourceId, points: points);
      _circleSignature = signature;
    }
    if (await map.style.styleLayerExists(circleLayerId)) {
      return;
    }

    await map.style.addLayer(
      mapbox.CircleLayer(
        id: circleLayerId,
        sourceId: circleSourceId,
        slot: mapbox.LayerSlot.TOP,
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
        circleOpacityExpression: _fadeInExpression(mapCircleFullOpacity),
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

  Future<void> _renderHeatmap(mapbox.MapboxMap map, List<MapPoint> points) async {
    final signature = _pointsSignature(points);
    if (signature != _heatmapSignature) {
      await _upsertSource(map, sourceId: heatmapSourceId, points: points);
      _heatmapSignature = signature;
    }
    if (await map.style.styleLayerExists(heatmapLayerId)) {
      return;
    }

    await map.style.addLayer(
      mapbox.HeatmapLayer(
        id: heatmapLayerId,
        sourceId: heatmapSourceId,
        slot: mapbox.LayerSlot.MIDDLE,
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
  Future<void> _renderSelection(mapbox.MapboxMap map, MapPoint? selected) async {
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
      mapbox.CircleLayer(
        id: selectionHaloLayerId,
        sourceId: selectionSourceId,
        slot: mapbox.LayerSlot.TOP,
        circleColorExpression: _circleColorExpression,
        circleRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          6,
          13,
          8,
          16,
          12,
        ],
        circleOpacity: 0.22,
        circleBlur: 0.35,
        circleEmissiveStrength: 1,
      ),
    );
    await map.style.addLayer(
      mapbox.CircleLayer(
        id: selectionCoreLayerId,
        sourceId: selectionSourceId,
        slot: mapbox.LayerSlot.TOP,
        circleColorExpression: _circleColorExpression,
        circleRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          3.5,
          13,
          5,
          16,
          7.5,
        ],
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 3,
        circleOpacity: 1,
        circleEmissiveStrength: 1,
      ),
    );
  }

  Future<void> _renderMarkers(
    mapbox.MapboxMap map,
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
        mapbox.PointAnnotationOptions(
          geometry: _point(marker.longitude, marker.latitude),
          iconImage: 'marker-15',
          iconSize: 1.35,
          iconAnchor: mapbox.IconAnchor.BOTTOM,
          textField: marker.label,
          textSize: 12,
          textOffset: const [0, 1.15],
          textAnchor: mapbox.TextAnchor.TOP,
          textColor: const Color(0xFF0F172A).toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 1.5,
          customData: {'venueId': marker.venueId},
        ),
    ]);
    _markerSignature = signature;
  }

  Future<mapbox.PointAnnotationManager?> _ensureMarkerManager(
    mapbox.MapboxMap map,
  ) async {
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

  Future<void> _applyLayerMode(mapbox.MapboxMap map, MapLayerMode mode) async {
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
  /// queryRenderedFeatures 命中，在热力图上点一下就选中了一家看不见的酒吧。
  ///
  /// [armed] 为 false（手动选了「点位」）时把两者都还原：没有热力图接手，
  /// 缩小了也得留着点。
  Future<void> _applyZoomHandoff(mapbox.MapboxMap map, {required bool armed}) async {
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
      armed ? _fadeInExpression(mapCircleFullOpacity) : mapCircleFullOpacity,
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

  Future<void> _setLayerVisible(mapbox.MapboxMap map, String layerId, bool visible) =>
      _setLayerProperty(map, layerId, 'visibility', visible ? 'visible' : 'none');

  Future<void> _setLayerProperty(
    mapbox.MapboxMap map,
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
    mapbox.MapboxMap map, {
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
      mapbox.GeoJsonSource(id: sourceId, data: data, generateId: true),
    );
  }

  String _pointsSignature(List<MapPoint> points) =>
      points.map((point) => point.id).join(',');

  void resetAllSignatures() {
    _markerSignature = null;
    _selectionSignature = null;
    _circleSignature = null;
    _heatmapSignature = null;
    _appliedLayerMode = null;
    frameSignature = null;
  }

  @override
  void resetStyleCaches() => resetAllSignatures();
}

mapbox.Point _point(double longitude, double latitude) =>
    mapbox.Point(coordinates: mapbox.Position(longitude, latitude));
